import Foundation
import AVFoundation
import simd

/// TrueDepth의 원본 깊이 맵(depth map)을 실제 3D 점군 메시로 변환한다.
/// ARKit의 ARFaceGeometry(표정 계수로 변형되는 가짜 템플릿)와 달리,
/// 이 방식은 카메라가 실제로 측정한 깊이값을 그대로 3D 좌표로 풀어내므로
/// 사람마다 다른 실제 얼굴 형태가 반영된다.
enum DepthMeshBuilder {

    /// - Parameters:
    ///   - depthBuffer: TrueDepth에서 캡처한 Float32(meter) 깊이 맵
    ///   - calibrationData: 깊이 맵과 짝을 이루는 카메라 내부 파라미터
    ///   - step: 다운샘플링 간격 (1=원본 해상도 그대로, 2=절반 해상도 -> 정점 수 1/4)
    ///   - minDepthMeters/maxDepthMeters: 얼굴이 있을 것으로 예상하는 거리 범위 (배경 제거용)
    static func buildMesh(
        depthBuffer: CVPixelBuffer,
        calibrationData: AVCameraCalibrationData?,
        step: Int = 4,
        minDepthMeters: Float = 0.15,
        maxDepthMeters: Float = 0.8,
        // 인접한 두 정점 사이의 3D 거리가 이 값을 넘으면 "같은 표면"이 아니라
        // 실루엣 경계(얼굴 윤곽 vs 배경)로 보고 그 사이는 잇지 않는다.
        maxEdgeMeters: Float = 0.012
    ) -> ScanMesh? {
        guard let calib = calibrationData else { return nil }

        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        guard let base = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)

        // calibrationData의 intrinsic은 컬러 이미지 기준 해상도이므로,
        // 깊이 맵 해상도에 맞게 비례 스케일링한다.
        let intrinsics = calib.intrinsicMatrix
        let refDim = calib.intrinsicMatrixReferenceDimensions
        let scaleX = Float(width) / Float(refDim.width)
        let scaleY = Float(height) / Float(refDim.height)
        let fx = intrinsics.columns.0.x * scaleX
        let fy = intrinsics.columns.1.y * scaleY
        let cx = intrinsics.columns.2.x * scaleX
        let cy = intrinsics.columns.2.y * scaleY

        let gridW = max(1, width / step)
        let gridH = max(1, height / step)

        // 그리드 좌표 -> 실제 생성된 정점 인덱스 매핑 (유효하지 않은 픽셀은 -1)
        var indexMap = [Int32](repeating: -1, count: gridW * gridH)
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(gridW * gridH)

        for gy in 0..<gridH {
            let py = gy * step
            let rowPtr = base.advanced(by: py * bytesPerRow)
            let floatPtr = rowPtr.assumingMemoryBound(to: Float32.self)
            for gx in 0..<gridW {
                let px = gx * step
                let depth = floatPtr[px]
                guard depth.isFinite, depth > minDepthMeters, depth < maxDepthMeters else { continue }

                let x = (Float(px) - cx) / fx * depth
                let y = (Float(py) - cy) / fy * depth
                // 화면 보기 좋게 y/z 방향을 뒤집어 STL 뷰어에서 정면을 보도록 함
                let vertex = SIMD3<Float>(x, -y, -depth)

                indexMap[gy * gridW + gx] = Int32(vertices.count)
                vertices.append(vertex)
            }
        }

        guard !vertices.isEmpty else { return nil }

        var indices: [Int32] = []
        indices.reserveCapacity(gridW * gridH * 6)

        // 두 정점 사이 거리가 maxEdgeMeters를 넘으면 깊이 불연속(실루엣 경계)으로 간주
        func edgeOK(_ a: Int32, _ b: Int32) -> Bool {
            let va = vertices[Int(a)]
            let vb = vertices[Int(b)]
            return simd_distance(va, vb) <= maxEdgeMeters
        }

        for gy in 0..<(gridH - 1) {
            for gx in 0..<(gridW - 1) {
                let i00 = indexMap[gy * gridW + gx]
                let i10 = indexMap[gy * gridW + gx + 1]
                let i01 = indexMap[(gy + 1) * gridW + gx]
                let i11 = indexMap[(gy + 1) * gridW + gx + 1]

                // 네 모서리가 전부 유효하고, 서로 간 거리도 임계값 이내일 때만 삼각형을 만든다
                // (배경/노이즈뿐 아니라 얼굴 윤곽선의 "커튼" 아티팩트도 여기서 걸러진다)
                if i00 >= 0, i10 >= 0, i01 >= 0,
                   edgeOK(i00, i10), edgeOK(i10, i01), edgeOK(i00, i01) {
                    indices.append(contentsOf: [i00, i10, i01])
                }
                if i10 >= 0, i11 >= 0, i01 >= 0,
                   edgeOK(i10, i11), edgeOK(i11, i01), edgeOK(i10, i01) {
                    indices.append(contentsOf: [i10, i11, i01])
                }
            }
        }

        guard !indices.isEmpty else { return nil }
        return ScanMesh(vertices: vertices, triangleIndices: indices)
    }
}
