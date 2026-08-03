import SwiftUI

struct CalibrationView: View {
    let onFinished: (CalibrationProfile) -> Void

    @StateObject private var captureController = TrueDepthCaptureController()
    @StateObject private var calibrationManager = CalibrationManager()

    // 가장 최근 프레임을 잠깐 들고 있다가, 사용자가 "캡처" 버튼을 누를 때 처리
    @State private var pendingColorImage: UIImage?
    @State private var pendingDepthBuffer: CVPixelBuffer?
    @State private var pendingCalibData: AVCameraCalibrationData?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                CameraPreviewView(controller: captureController)
                    .aspectRatio(3/4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(calibrationManager.lastDetectionFound ? .green : .red, lineWidth: 3)
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

            Text(calibrationManager.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                captureCurrentFrame()
            } label: {
                Label("현재 프레임 캡처", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(calibrationManager.isCalibrating)
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
                // 최신 프레임을 계속 갱신 (버튼 탭 시점의 프레임을 사용)
                pendingColorImage = image
                pendingDepthBuffer = depth
                pendingCalibData = calib
            }
        }
        .onDisappear {
            captureController.stop()
        }
        .onChange(of: calibrationManager.resultProfile) { profile in
            if let profile {
                onFinished(profile)
            }
        }
    }

    private func captureCurrentFrame() {
        guard let image = pendingColorImage, let depth = pendingDepthBuffer else { return }
        calibrationManager.captureFrame(colorImage: image, depthBuffer: depth, calibrationData: pendingCalibData)
    }
}
