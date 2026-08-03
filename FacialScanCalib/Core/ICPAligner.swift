import Foundation
import simd

/// 여러 프레임의 3D 점군을 하나의 좌표계로 정렬(ICP, Iterative Closest Point)하는 모듈.
/// Horn(1987)의 quaternion 기반 닫힌 형태(closed-form) 강체 변환 계산을 사용하며,
/// 외부 라이브러리 없이 Swift 표준 simd만으로 구현했다 (전체 파이프라인이 온디바이스에서 동작).
enum ICPAligner {

    struct Transform {
        var rotation: simd_quatf
        var translation: SIMD3<Float>

        static let identity = Transform(rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), translation: .zero)

        func apply(_ p: SIMD3<Float>) -> SIMD3<Float> {
            rotation.act(p) + translation
        }

        /// self를 적용한 다음 other를 적용하는 합성 변환 (other ∘ self)
        func then(_ other: Transform) -> Transform {
            Transform(
                rotation: other.rotation * rotation,
                translation: other.rotation.act(translation) + other.translation
            )
        }
    }

    struct AlignmentResult {
        let transform: Transform
        /// 마지막 반복에서 대응점을 찾은 소스 점의 비율 (0~1). 낮으면 정합 신뢰도가 낮다는 뜻.
        let inlierRatio: Float
    }

    /// source 점군을 target 점군에 맞춰 정렬하는 강체 변환을 계산한다.
    /// - Parameters:
    ///   - maxIterations: ICP 반복 횟수 상한
    ///   - maxCorrespondenceDistance: 이 거리보다 먼 최근접점 쌍은 대응점으로 인정하지 않음 (m 단위)
    static func align(
        source: [SIMD3<Float>],
        target: [SIMD3<Float>],
        maxIterations: Int = 20,
        maxCorrespondenceDistance: Float = 0.02
    ) -> AlignmentResult {
        guard !source.isEmpty, !target.isEmpty else {
            return AlignmentResult(transform: .identity, inlierRatio: 0)
        }

        let grid = VoxelGrid(points: target, voxelSize: max(maxCorrespondenceDistance, 0.005))

        var current = Transform.identity
        var prevError = Float.greatestFiniteMagnitude
        var lastInlierRatio: Float = 0

        // 계산량을 줄이기 위해 소스 점을 최대 1500개 정도로 균등 샘플링
        let stride = max(1, source.count / 1500)
        let sampledCount = max(1, source.count / stride)

        for _ in 0..<maxIterations {
            var srcPairs: [SIMD3<Float>] = []
            var tgtPairs: [SIMD3<Float>] = []
            srcPairs.reserveCapacity(1500)
            tgtPairs.reserveCapacity(1500)

            var totalError: Float = 0

            var i = 0
            while i < source.count {
                let p = current.apply(source[i])
                if let (nearest, dist) = grid.nearest(to: p), dist <= maxCorrespondenceDistance {
                    srcPairs.append(p)
                    tgtPairs.append(nearest)
                    totalError += dist * dist
                }
                i += stride
            }

            lastInlierRatio = Float(srcPairs.count) / Float(sampledCount)
            guard srcPairs.count >= 10 else { break }

            let step = hornAlignment(source: srcPairs, target: tgtPairs)
            current = current.then(step)

            let meanError = totalError / Float(srcPairs.count)
            if abs(prevError - meanError) < 1e-8 { break }
            prevError = meanError
        }

        return AlignmentResult(transform: current, inlierRatio: lastInlierRatio)
    }

    /// Horn(1987) 닫힌 형태 해: 대응점 쌍이 주어졌을 때 최적의 강체 변환(회전+이동)을 계산.
    private static func hornAlignment(source: [SIMD3<Float>], target: [SIMD3<Float>]) -> Transform {
        let n = Float(source.count)
        let srcCentroid = source.reduce(SIMD3<Float>.zero, +) / n
        let tgtCentroid = target.reduce(SIMD3<Float>.zero, +) / n

        var Sxx: Float = 0, Sxy: Float = 0, Sxz: Float = 0
        var Syx: Float = 0, Syy: Float = 0, Syz: Float = 0
        var Szx: Float = 0, Szy: Float = 0, Szz: Float = 0

        for i in 0..<source.count {
            let p = source[i] - srcCentroid
            let q = target[i] - tgtCentroid
            Sxx += p.x * q.x; Sxy += p.x * q.y; Sxz += p.x * q.z
            Syx += p.y * q.x; Syy += p.y * q.y; Syz += p.y * q.z
            Szx += p.z * q.x; Szy += p.z * q.y; Szz += p.z * q.z
        }

        let N = simd_float4x4(
            SIMD4<Float>(Sxx + Syy + Szz, Syz - Szy, Szx - Sxz, Sxy - Syx),
            SIMD4<Float>(Syz - Szy, Sxx - Syy - Szz, Sxy + Syx, Szx + Sxz),
            SIMD4<Float>(Szx - Sxz, Sxy + Syx, -Sxx + Syy - Szz, Syz + Szy),
            SIMD4<Float>(Sxy - Syx, Szx + Sxz, Syz + Szy, -Sxx - Syy + Szz)
        )

        let q = dominantEigenvector(of: N)
        let rotation = simd_quatf(ix: q.y, iy: q.z, iz: q.w, r: q.x)
        let translation = tgtCentroid - rotation.act(srcCentroid)

        return Transform(rotation: rotation, translation: translation)
    }

    /// Shifted power iteration으로 대칭 4x4 행렬의 최대(양의) 고유값에 대응하는 고유벡터를 구한다.
    /// (전용 SVD/고유값 라이브러리 없이도 안정적으로 동작하도록 모든 고유값을 양수로 이동시킨 뒤 계산)
    private static func dominantEigenvector(of matrix: simd_float4x4) -> SIMD4<Float> {
        var shift: Float = 0
        for c in 0..<4 {
            for r in 0..<4 {
                shift += abs(matrix[c][r])
            }
        }
        let shifted = matrix + simd_float4x4(diagonal: SIMD4<Float>(repeating: shift))

        var v = SIMD4<Float>(1, 1, 1, 1)
        for _ in 0..<60 {
            let next = shifted * v
            let norm = simd_length(next)
            v = norm > 1e-12 ? next / norm : next
        }
        return v
    }
}

/// 대상 점군에서 최근접점을 빠르게 찾기 위한 균일 격자(voxel grid) 기반 최근접 이웃 탐색.
private struct VoxelGrid {
    private struct Key: Hashable {
        let x: Int32, y: Int32, z: Int32
    }

    private let voxelSize: Float
    private var buckets: [Key: [SIMD3<Float>]] = [:]

    init(points: [SIMD3<Float>], voxelSize: Float) {
        self.voxelSize = voxelSize
        for p in points {
            buckets[Self.key(for: p, voxelSize: voxelSize), default: []].append(p)
        }
    }

    func nearest(to point: SIMD3<Float>) -> (SIMD3<Float>, Float)? {
        let center = Self.key(for: point, voxelSize: voxelSize)

        var best: SIMD3<Float>?
        var bestDistSq = Float.greatestFiniteMagnitude

        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    let key = Key(x: center.x + Int32(dx), y: center.y + Int32(dy), z: center.z + Int32(dz))
                    guard let candidates = buckets[key] else { continue }
                    for c in candidates {
                        let d = simd_distance_squared(c, point)
                        if d < bestDistSq {
                            bestDistSq = d
                            best = c
                        }
                    }
                }
            }
        }

        guard let best else { return nil }
        return (best, sqrt(bestDistSq))
    }

    private static func key(for p: SIMD3<Float>, voxelSize: Float) -> Key {
        Key(
            x: Int32(floor(p.x / voxelSize)),
            y: Int32(floor(p.y / voxelSize)),
            z: Int32(floor(p.z / voxelSize))
        )
    }
}
