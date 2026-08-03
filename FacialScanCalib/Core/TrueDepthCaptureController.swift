import AVFoundation
import UIKit
import Combine

/// TrueDepth 카메라에서 컬러 프레임 + 깊이 맵을 동기화하여 캡처.
/// 체커보드 교정 단계에서 사용 (ARKit의 face tracking과 별개로,
/// AVFoundation의 depth data output을 직접 사용해 임의 평면(체커보드)도 측정 가능하게 함).
final class TrueDepthCaptureController: NSObject, ObservableObject {

    @Published var latestColorImage: UIImage?
    @Published var isSessionRunning = false
    @Published var errorMessage: String?

    /// 콜백: 컬러 UIImage, 깊이 맵(CVPixelBuffer, Float32, meters), 카메라 내부 파라미터
    var onFrame: ((UIImage, CVPixelBuffer, AVCameraCalibrationData?) -> Void)?

    let session = AVCaptureSession()

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private let sessionQueue = DispatchQueue(label: "truedepth.session.queue")
    private let dataQueue = DispatchQueue(label: "truedepth.data.queue")

    func start() {
        sessionQueue.async { [weak self] in
            self?.configureSessionIfNeeded()
            if let session = self?.session, !session.isRunning {
                session.startRunning()
                DispatchQueue.main.async { self?.isSessionRunning = true }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isSessionRunning = false }
        }
    }

    private var configured = false

    private func configureSessionIfNeeded() {
        guard !configured else { return }
        configured = true

        session.beginConfiguration()
        session.sessionPreset = .vga640x480 // depth+color 동기 안정성 우선

        guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            DispatchQueue.main.async { self.errorMessage = "TrueDepth 카메라를 찾을 수 없습니다." }
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        videoOutput.setSampleBufferDelegate(nil, queue: nil) // synchronizer가 대신 처리
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true
        }

        session.commitConfiguration()

        synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        synchronizer?.setDelegate(self, queue: dataQueue)

        // 초점거리 등 정확한 depth 계산을 위해 30fps 등 기본값 사용
        try? device.lockForConfiguration()
        device.unlockForConfiguration()
    }
}

extension TrueDepthCaptureController: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                 didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard
            let videoData = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
            !videoData.sampleBufferWasDropped,
            let depthData = synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData,
            !depthData.depthDataWasDropped
        else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(videoData.sampleBuffer) else { return }

        // 깊이 데이터를 Float32(meter) 포맷으로 변환
        let converted = depthData.depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let depthPixelBuffer = converted.depthDataMap
        let calibrationData = converted.cameraCalibrationData

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

        DispatchQueue.main.async {
            self.latestColorImage = uiImage
        }
        onFrame?(uiImage, depthPixelBuffer, calibrationData)
    }
}
