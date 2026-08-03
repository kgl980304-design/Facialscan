import ARKit
import Combine
import simd

/// ARKit ARFaceTrackingConfiguration으로 얼굴을 추적하면서, 동시에
/// TrueDepth 원본 깊이 맵(ARFrame.capturedDepthData)에 접근한다.
///
/// 핵심: 프레임 간 정합을 자체 ICP로 직접 계산하지 않고,
/// ARKit이 이미 강건하게 추적해주는 카메라 world transform을 그대로 신뢰해서 쓴다.
/// (Polycam 등 실제 프로덕션 3D 스캔 앱도 자체 SfM 대신 ARKit pose를 그대로/최적화해서 쓰는 방식)
final class ARDepthCaptureController: NSObject, ObservableObject {

    enum TrackingQuality {
        case normal
        case limited(String)
        case notAvailable

        var isUsable: Bool {
            if case .normal = self { return true }
            return false
        }

        var description: String {
            switch self {
            case .normal: return "정상 추적 중"
            case .limited(let reason): return "추적 불안정: \(reason)"
            case .notAvailable: return "추적 불가"
            }
        }
    }

    @Published var trackingQuality: TrackingQuality = .notAvailable
    @Published var errorMessage: String?

    /// 콜백: 깊이 맵, 카메라 world transform(ARKit이 추적한 값), 카메라 calibration(intrinsics), 컬러 픽셀버퍼
    var onFrame: ((CVPixelBuffer, simd_float4x4, AVCameraCalibrationData?, CVPixelBuffer) -> Void)?

    let session = ARSession()

    func start() {
        guard ARFaceTrackingConfiguration.isSupported else {
            errorMessage = "이 기기는 TrueDepth 얼굴 추적을 지원하지 않습니다."
            return
        }
        session.delegate = self
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
    }
}

extension ARDepthCaptureController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        switch frame.camera.trackingState {
        case .normal:
            trackingQuality = .normal
        case .limited(let reason):
            let text: String
            switch reason {
            case .excessiveMotion: text = "움직임이 너무 큼"
            case .insufficientFeatures: text = "특징을 충분히 못 찾음"
            case .initializing: text = "초기화 중"
            case .relocalizing: text = "재추적 중"
            @unknown default: text = "알 수 없음"
            }
            trackingQuality = .limited(text)
        case .notAvailable:
            trackingQuality = .notAvailable
        }

        guard let depthData = frame.capturedDepthData else { return }
        let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)

        onFrame?(
            converted.depthDataMap,
            frame.camera.transform,
            converted.cameraCalibrationData,
            frame.capturedImage
        )
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        errorMessage = "ARSession 오류: \(error.localizedDescription)"
    }
}
