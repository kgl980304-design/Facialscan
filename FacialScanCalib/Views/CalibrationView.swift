import SwiftUI
import AVFoundation

/// 체커보드 교정 화면.
/// 사용자가 매번 버튼을 누를 필요 없이, 체커보드가 화면에 잡혀있는 동안
/// 자동으로 일정 간격마다 프레임을 캡처한다 (여러 각도로 천천히 움직이기만 하면 됨).
struct CalibrationView: View {
    let onFinished: (CalibrationProfile) -> Void

    @StateObject private var captureController = TrueDepthCaptureController()
    @StateObject private var calibrationManager = CalibrationManager()

    @State private var pendingColorImage: UIImage?
    @State private var pendingDepthBuffer: CVPixelBuffer?
    @State private var pendingCalibData: AVCameraCalibrationData?

    // 자동 캡처 간격 (초). 너무 짧으면 같은 각도만 여러 번 찍히므로 적당히 텀을 둔다.
    private let autoCaptureInterval: TimeInterval = 1.0
    private let autoCaptureTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                CameraPreviewView(controller: captureController)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(calibrationManager.lastDetectionFound ? .green : .orange, lineWidth: 3)
                    )

                if calibrationManager.isCalibrating {
                    Color.black.opacity(0.4)
                    ProgressView("계산 중...")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal)

            ProgressView(value: Double(calibrationManager.capturedFrameCount),
                         total: Double(calibrationManager.requiredFrameCount))
                .padding(.horizontal)

            Text("\(calibrationManager.capturedFrameCount) / \(calibrationManager.requiredFrameCount) 자동 촬영됨")
                .font(.headline)

            Text(calibrationManager.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("체커보드 전체가 화면 안에 들어오도록 천천히 각도를 바꿔가며 들고 계세요. 초록 테두리일 때 자동으로 촬영됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("다시 시작") {
                calibrationManager.reset()
            }
            .disabled(calibrationManager.isCalibrating)

            Spacer()
        }
        .padding(.top)
        .onAppear {
            captureController.start()
            captureController.onFrame = { image, depth, calib in
                pendingColorImage = image
                pendingDepthBuffer = depth
                pendingCalibData = calib
            }
        }
        .onDisappear {
            captureController.stop()
        }
        .onReceive(autoCaptureTimer) { _ in
            attemptAutoCapture()
        }
        .onChange(of: calibrationManager.resultProfile) { profile in
            if let profile {
                onFinished(profile)
            }
        }
    }

    private func attemptAutoCapture() {
        guard !calibrationManager.isCalibrating else { return }
        guard let image = pendingColorImage, let depth = pendingDepthBuffer else { return }
        calibrationManager.captureFrame(colorImage: image, depthBuffer: depth, calibrationData: pendingCalibData)
    }
}
