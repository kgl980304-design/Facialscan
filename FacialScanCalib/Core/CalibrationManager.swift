import Foundation
import UIKit
import AVFoundation
import Combine

/// 체커보드를 이용한 카메라 내부 파라미터 교정 + 깊이 스케일 보정을 담당.
final class CalibrationManager: ObservableObject {

    @Published var capturedFrameCount = 0
    @Published var lastDetectionFound = false
    @Published var isCalibrating = false
    @Published var resultProfile: CalibrationProfile?
    @Published var statusMessage = "체커보드를 화면 중앙에 위치시키고 캡처하세요."

    let pattern: CheckerboardPattern
    let requiredFrameCount: Int

    private var collectedCorners: [[CGPoint]] = []
    private var lastImageSize: CGSize = .zero

    // 스케일 보정용: 코너별 (이미지좌표, depth meter) 샘플 누적
    private var scaleSamplesMM: [Double] = []

    init(pattern: CheckerboardPattern = CheckerboardPattern(), requiredFrameCount: Int = 8) {
        self.pattern = pattern
        self.requiredFrameCount = requiredFrameCount
    }

    /// TrueDepthCaptureController의 onFrame 콜백에서 호출.
    /// 사용자가 "캡처" 버튼을 눌렀을 때만 이 함수를 호출하는 방식으로 사용 (자동 연속 캡처가 아님).
    func captureFrame(colorImage: UIImage, depthBuffer: CVPixelBuffer, calibrationData: AVCameraCalibrationData?) {
        lastImageSize = colorImage.size

        let detection = OpenCVWrapper.findChessboardCorners(
            colorImage,
            patternWidth: pattern.cornersX,
            patternHeight: pattern.cornersY
        )

        lastDetectionFound = detection.found
        guard detection.found else {
            statusMessage = "체커보드를 찾지 못했습니다. 각도를 조금 바꿔서 다시 시도하세요."
            return
        }

        let points = detection.corners.map { $0.cgPointValue }
        collectedCorners.append(points)
        capturedFrameCount = collectedCorners.count

        // 인접 코너 간 실측 거리(깊이 기반)를 샘플링해서 스케일 보정에 사용
        if let mm = Self.measureAdjacentSquareSizeMM(
            corners: points,
            patternWidth: pattern.cornersX,
            patternHeight: pattern.cornersY,
            depthBuffer: depthBuffer,
            calibrationData: calibrationData
        ) {
            scaleSamplesMM.append(contentsOf: mm)
        }

        statusMessage = "\(capturedFrameCount)/\(requiredFrameCount) 프레임 캡처됨"

        if capturedFrameCount >= requiredFrameCount {
            runCalibration()
        }
    }

    private func runCalibration() {
        isCalibrating = true
        statusMessage = "카메라 파라미터 계산 중..."

        let imagePointsList: [[NSValue]] = collectedCorners.map { frame in
            frame.map { NSValue(cgPoint: $0) }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let calibResult = OpenCVWrapper.calibrate(
                withImagePointsList: imagePointsList,
                patternWidth: self.pattern.cornersX,
                patternHeight: self.pattern.cornersY,
                squareSize: Float(self.pattern.squareSizeMM),
                imageWidth: Int(self.lastImageSize.width),
                imageHeight: Int(self.lastImageSize.height)
            ) else {
                DispatchQueue.main.async {
                    self.statusMessage = "카메라 교정에 실패했습니다. 다시 시도해주세요."
                    self.isCalibrating = false
                }
                return
            }

            let cameraResult = CameraCalibrationResult(
                cameraMatrix: calibResult.cameraMatrix.map { $0.doubleValue },
                distCoeffs: calibResult.distCoeffs.map { $0.doubleValue },
                reprojectionError: calibResult.reprojectionError,
                timestamp: Date()
            )

            let measuredAvg = self.scaleSamplesMM.isEmpty ? self.pattern.squareSizeMM
                : self.scaleSamplesMM.reduce(0, +) / Double(self.scaleSamplesMM.count)

            let scaleResult = ScaleCalibrationResult(
                measuredSquareSizeMM: measuredAvg,
                knownSquareSizeMM: self.pattern.squareSizeMM,
                sampleCount: self.scaleSamplesMM.count
            )

            let profile = CalibrationProfile(
                camera: cameraResult,
                scale: scaleResult,
                deviceModel: UIDevice.current.model,
                timestamp: Date()
            )

            DispatchQueue.main.async {
                self.resultProfile = profile
                self.isCalibrating = false
                self.statusMessage = String(
                    format: "교정 완료. 재투영 오차 %.3f px, 스케일 보정계수 %.4f",
                    cameraResult.reprojectionError, scaleResult.scaleFactor
                )
                CalibrationStore.save(profile)
            }
        }
    }

    func reset() {
        collectedCorners.removeAll()
        scaleSamplesMM.removeAll()
        capturedFrameCount = 0
        resultProfile = nil
        statusMessage = "체커보드를 화면 중앙에 위치시키고 캡처하세요."
    }

    /// 검출된 코너 그리드에서 가로 방향 인접 코너 쌍들의 실제 3D 거리를 depth map으로 계산.
    private static func measureAdjacentSquareSizeMM(
        corners: [CGPoint],
        patternWidth: Int,
        patternHeight: Int,
        depthBuffer: CVPixelBuffer,
        calibrationData: AVCameraCalibrationData?
    ) -> [Double]? {
        guard let calib = calibrationData else { return nil }
        guard corners.count == patternWidth * patternHeight else { return nil }

        let intrinsics = calib.intrinsicMatrix // simd_float3x3, in pixel units of the *reference* dimensions
        let refDim = calib.intrinsicMatrixReferenceDimensions

        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let depthWidth = CVPixelBufferGetWidth(depthBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthBuffer)
        guard let base = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)

        func depthAt(_ px: CGFloat, _ py: CGFloat) -> Float? {
            // 컬러 이미지 좌표 -> depth map 좌표로 스케일 변환
            let dx = Int(px / refDim.width * CGFloat(depthWidth))
            let dy = Int(py / refDim.height * CGFloat(depthHeight))
            guard dx >= 0, dx < depthWidth, dy >= 0, dy < depthHeight else { return nil }
            let rowPtr = base.advanced(by: dy * bytesPerRow)
            let floatPtr = rowPtr.assumingMemoryBound(to: Float32.self)
            let value = floatPtr[dx]
            guard value.isFinite, value > 0 else { return nil }
            return value // meters
        }

        func to3D(_ point: CGPoint, depthMeters: Float) -> simd_float3 {
            let fx = intrinsics.columns.0.x
            let fy = intrinsics.columns.1.y
            let cx = intrinsics.columns.2.x
            let cy = intrinsics.columns.2.y
            // 컬러 이미지 좌표를 참조 해상도 기준으로 정규화했다고 가정 (동일 센서이므로 큰 오차 없음)
            let x = (Float(point.x) - cx) / fx * depthMeters
            let y = (Float(point.y) - cy) / fy * depthMeters
            return simd_float3(x, y, depthMeters)
        }

        var distancesMM: [Double] = []

        for row in 0..<patternHeight {
            for col in 0..<(patternWidth - 1) {
                let idxA = row * patternWidth + col
                let idxB = row * patternWidth + col + 1
                let a = corners[idxA]
                let b = corners[idxB]
                guard let da = depthAt(a.x, a.y), let db = depthAt(b.x, b.y) else { continue }
                let p3a = to3D(a, depthMeters: da)
                let p3b = to3D(b, depthMeters: db)
                let distMeters = simd_distance(p3a, p3b)
                distancesMM.append(Double(distMeters) * 1000.0)
            }
        }

        return distancesMM.isEmpty ? nil : distancesMM
    }
}

/// 교정 프로파일을 로컬에 저장/로드 (다음 스캔 때 재사용)
enum CalibrationStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("calibration_profile.json")
    }

    static func save(_ profile: CalibrationProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: url)
    }

    static func load() -> CalibrationProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CalibrationProfile.self, from: data)
    }
}
