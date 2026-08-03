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
    ///   - minDepthMeters/maxDepthMeters: 얼굴이 있을 것으로 예상하는 거리 범위 (배경 제거 1차 필터)
    ///   - faceBoxInColorPixels/colorImagePixelSize: Vision으로 검출한 얼굴 영역
    ///     (원본/비회전 좌표계). 주어지면 이 영역 밖의 깊이 픽셀은 아예 사용하지 않아
    ///     배경/손/어깨 등이 메시에 섞여 들어오는 걸 방지한다 (2차 필터, 핵심 개선).
    static func buildMesh(
        depthBuffer: CVPixelBuffer,
        calibrationData: AVCameraCalibrationData?,
        step: Int = 4,
        minDepthMeters: Float = 0.15,
        maxDepthMeters: Float = 0.8,
        maxEdgeMeters: Float = 0.012,
        faceBoxInColorPixels: CGRect? = nil,
        colorImagePixelSize: CGSize? = nil,
        removeOutliers: Bool = true,
        outlierRadiusMeters: Float = 0.01,
        outlierMinNeighbors: Int = 4,
        // ARKit이 추적한 카메라 world transform. 주어지면 이 프레임의 점들을
        // 카메라 로컬 좌표가 아니라 ARKit의 공통 world 좌표계로 바로 배치한다.
        // (여러 프레임을 합칠 때 이 값이 있으면 별도 정합 없이 그대로 이어붙이면 된다)
        worldTransform: simd_float4x4? = nil,
        // Apple 팩토리 렌즈 왜곡 보정 테이블 적용 여부 (체커보드 없이 쓸 수 있는 대안 보정)
        applyLensDistortionCorrection: Bool = true
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

        // 얼굴 바운딩 박스를 컬러 이미지 좌표계 -> 깊이 맵 좌표계로 변환
        var faceBoxInDepth: CGRect?
        if let box = faceBoxInColorPixels, let colorSize = colorImagePixelSize,
           colorSize.width > 0, colorSize.height > 0 {
            let cToDx = Double(width) / Double(colorSize.width)
            let cToDy = Double(height) / Double(colorSize.height)
            faceBoxInDepth = CGRect(
                x: box.minX * cToDx,
                y: box.minY * cToDy,
                width: box.width * cToDx,
                height: box.height * cToDy
            )
        }

        let gridW = max(1, width / step)
        let gridH = max(1, height / step)

        var indexMap = [Int32](repeating: -1, count: gridW * gridH)
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(gridW * gridH)

        for gy in 0..<gridH {
            let py = gy * step
            let rowPtr = base.advanced(by: py * bytesPerRow)
            let floatPtr = rowPtr.assumingMemoryBound(to: Float32.self)
            for gx in 0..<gridW {
                let px = gx * step

                // 얼굴 바운딩 박스 밖이면 아예 건너뜀 (배경 1차 제거)
                if let box = faceBoxInDepth,
                   !box.contains(CGPoint(x: px, y: py)) {
                    continue
                }

                let depth = floatPtr[px]
                guard depth.isFinite, depth > minDepthMeters, depth < maxDepthMeters else { continue }

                var correctedPx = Float(px)
                var correctedPy = Float(py)
                if applyLensDistortionCorrection {
                    // lensDistortionLookupTable/opticalCenter는 calibrationData의 기준
                    // 해상도(refDim, 보통 컬러 이미지 해상도) 기준이므로, 깊이 맵 좌표를
                    // 잠시 그 기준으로 되돌려서 보정한 뒤 다시 깊이 맵 좌표로 되돌린다.
                    let refPx = Float(px) / scaleX
                    let refPy = Float(py) / scaleY
                    let corrected = LensDistortionCorrector.correct(
                        point: CGPoint(x: CGFloat(refPx), y: CGFloat(refPy)),
                        calibrationData: calib,
                        imageSize: refDim
                    )
                    correctedPx = Float(corrected.x) * scaleX
                    correctedPy = Float(corrected.y) * scaleY
                }

                let x = (correctedPx - cx) / fx * depth
                let y = (correctedPy - cy) / fy * depth
                let cameraLocalPoint = SIMD3<Float>(x, y, depth)

                let vertex: SIMD3<Float>
                if let worldTransform {
                    // ARKit world 좌표계로 변환 (여러 프레임이 이 좌표계를 공유하므로 그대로 이어붙이면 정합됨)
                    let world4 = worldTransform * SIMD4<Float>(cameraLocalPoint.x, -cameraLocalPoint.y, -cameraLocalPoint.z, 1)
                    vertex = SIMD3<Float>(world4.x, world4.y, world4.z)
                } else {
                    // 단일 프레임만 볼 때 보기 좋게 y/z 방향을 뒤집음
                    vertex = SIMD3<Float>(cameraLocalPoint.x, -cameraLocalPoint.y, -cameraLocalPoint.z)
                }

                indexMap[gy * gridW + gx] = Int32(vertices.count)
                vertices.append(vertex)
            }
        }

        guard !vertices.isEmpty else { return nil }

        // 통계/반경 기반 outlier 제거: 주변에 이웃이 거의 없는 부유 점은 삼각형 생성에서 제외
        let keepMask: [Bool]
        if removeOutliers {
            keepMask = PointCloudFilter.radiusOutlierMask(
                points: vertices,
                radius: outlierRadiusMeters,
                minNeighbors: outlierMinNeighbors
            )
        } else {
            keepMask = Array(repeating: true, count: vertices.count)
        }

        var indices: [Int32] = []
        indices.reserveCapacity(gridW * gridH * 6)

        func edgeOK(_ a: Int32, _ b: Int32) -> Bool {
            simd_distance(vertices[Int(a)], vertices[Int(b)]) <= maxEdgeMeters
        }
        func valid(_ i: Int32) -> Bool {
            i >= 0 && keepMask[Int(i)]
        }

        for gy in 0..<(gridH - 1) {
            for gx in 0..<(gridW - 1) {
                let i00 = indexMap[gy * gridW + gx]
                let i10 = indexMap[gy * gridW + gx + 1]
                let i01 = indexMap[(gy + 1) * gridW + gx]
                let i11 = indexMap[(gy + 1) * gridW + gx + 1]

                if valid(i00), valid(i10), valid(i01),
                   edgeOK(i00, i10), edgeOK(i10, i01), edgeOK(i00, i01) {
                    indices.append(contentsOf: [i00, i10, i01])
                }
                if valid(i10), valid(i11), valid(i01),
                   edgeOK(i10, i11), edgeOK(i11, i01), edgeOK(i10, i01) {
                    indices.append(contentsOf: [i10, i11, i01])
                }
            }
        }

        guard !indices.isEmpty else { return nil }
        return ScanMesh(vertices: vertices, triangleIndices: indices)
    }
}
