import Foundation
import simd

/// 점군 후처리: 주변에 이웃이 충분하지 않은 "부유 노이즈 점"을 제거한다.
/// PCL의 RadiusOutlierRemoval과 동일한 개념 (반경 내 이웃 개수 기준).
enum PointCloudFilter {

    /// - Returns: 각 점을 유지할지 여부 (points와 동일한 순서/길이의 Bool 배열)
    static func radiusOutlierMask(
        points: [SIMD3<Float>],
        radius: Float = 0.01,
        minNeighbors: Int = 4
    ) -> [Bool] {
        guard points.count > minNeighbors else {
            return Array(repeating: true, count: points.count)
        }

        struct Key: Hashable { let x: Int32, y: Int32, z: Int32 }
        func key(_ p: SIMD3<Float>) -> Key {
            Key(x: Int32(floor(p.x / radius)), y: Int32(floor(p.y / radius)), z: Int32(floor(p.z / radius)))
        }

        var buckets: [Key: [Int]] = [:]
        buckets.reserveCapacity(points.count)
        for (i, p) in points.enumerated() {
            buckets[key(p), default: []].append(i)
        }

        var keep = [Bool](repeating: true, count: points.count)
        let radiusSq = radius * radius

        for i in 0..<points.count {
            let k = key(points[i])
            var count = 0
            outer: for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        let neighborKey = Key(x: k.x + Int32(dx), y: k.y + Int32(dy), z: k.z + Int32(dz))
                        guard let idxs = buckets[neighborKey] else { continue }
                        for j in idxs where j != i {
                            if simd_distance_squared(points[i], points[j]) <= radiusSq {
                                count += 1
                                if count >= minNeighbors { break outer }
                            }
                        }
                    }
                }
            }
            keep[i] = count >= minNeighbors
        }

        return keep
    }
}
