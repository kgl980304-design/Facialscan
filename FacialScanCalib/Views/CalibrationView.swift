import SwiftUI
import AVFoundation

/// 체커보드 교정 화면.
/// 1) 라이브 프리뷰 + "자동 촬영" (체커보드가 잡혀있는 동안 자동으로 프레임 수집)
/// 2) 실제로 인식된 코너를 초록 점으로 찍은 사진을 그대로 보여줘서 "진짜 인식하고 있다"를 증명
/// 3) 계산이 끝나면 바로 다음 화면으로 넘어가지 않고, 재투영 오차/보정계수 숫자를
///    직접 보여준 뒤 사용자가 확인하고 다음으로 넘어가도록 함
struct CalibrationView: View {
    let onFinished: (CalibrationProfile) -> Void

    @StateObject private var captureController = TrueDepthCaptureController()
    @StateObject private var calibrationManager = CalibrationManager()

    @State private var pendingColorImage: UIImage?
    @State private var pendingDepthBuffer: CVPixelBuffer?
    @State private var pendingCalibData: AVCameraCalibrationData?

    private let autoCaptureTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        if let profile = calibrationManager.resultProfile {
            resultSummary(profile: profile)
        } else {
            captureScreen
        }
    }

    // MARK: - 1단계: 자동 촬영 화면

    private var captureScreen: some View {
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

            // 실제로 인식된 코너 사진 (실시간 증거)
            if let annotated = calibrationManager.lastAnnotatedImage {
                VStack(spacing: 4) {
                    Text("방금 실제로 인식된 코너 (초록 점)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(uiImage: annotated)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.green, lineWidth: 1))
                }
            }

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

            Text("체커보드 전체가 화면 안에 들어오도록 천천히 각도를 바꿔가며 들고 계세요.")
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
    }

    private func attemptAutoCapture() {
        guard !calibrationManager.isCalibrating else { return }
        guard calibrationManager.resultProfile == nil else { return }
        guard let image = pendingColorImage, let depth = pendingDepthBuffer else { return }
        calibrationManager.captureFrame(colorImage: image, depthBuffer: depth, calibrationData: pendingCalibData)
    }

    // MARK: - 2단계: 보정계수 산출 결과 화면

    private func resultSummary(profile: CalibrationProfile) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("보정계수 산출 완료")
                .font(.title2).bold()

            VStack(alignment: .leading, spacing: 12) {
                resultRow(
                    title: "재투영 오차 (Reprojection Error)",
                    value: String(format: "%.4f px", profile.camera.reprojectionError),
                    detail: "낮을수록 카메라 파라미터 계산이 정확합니다 (보통 1px 미만이 양호)"
                )
                resultRow(
                    title: "실측 사각형 크기",
                    value: String(format: "%.2f mm", profile.scale.measuredSquareSizeMM),
                    detail: String(format: "실제 크기: %.1f mm (체커보드 스펙)", profile.scale.knownSquareSizeMM)
                )
                resultRow(
                    title: "스케일 보정계수",
                    value: String(format: "%.4f", profile.scale.scaleFactor),
                    detail: "이후 스캔에 이 계수를 곱해 실측 오차를 보정합니다"
                )
                resultRow(
                    title: "사용된 깊이 샘플 수",
                    value: "\(profile.scale.sampleCount)개",
                    detail: "체커보드 코너 간 거리를 깊이 데이터로 직접 측정한 샘플 개수"
                )
            }
            .padding()
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Spacer()

            Button {
                onFinished(profile)
            } label: {
                Label("확인, 얼굴 스캔 시작", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            Button("교정 다시 하기") {
                calibrationManager.reset()
            }
            .padding(.bottom)
        }
        .padding(.top, 32)
    }

    private func resultRow(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3).bold()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
