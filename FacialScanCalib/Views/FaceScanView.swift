import SwiftUI
import AVFoundation

/// Bellus3D FaceApp 스타일의 다각도 유도 촬영 워크플로우:
/// 정면 -> 왼쪽 45~90도 -> 오른쪽 45~90도 순서로, 거리 안내(빨강/초록)를 보면서
/// 각 각도마다 TrueDepth 원본 깊이 데이터를 캡처해 STL로 저장한다.
/// (여러 각도를 하나로 합성/정합하는 건 CloudCompare 등 외부 툴에서 진행)
enum ScanPose: Int, CaseIterable {
    case center, left, right

    var title: String {
        switch self {
        case .center: return "정면"
        case .left: return "왼쪽 45~90도"
        case .right: return "오른쪽 45~90도"
        }
    }

    var instruction: String {
        switch self {
        case .center: return "정면을 바라보고 무표정을 유지하세요."
        case .right: return "고개를 오른쪽으로 45~90도 돌리세요 (왼쪽 뺨이 보이도록)."
        case .left: return "고개를 왼쪽으로 45~90도 돌리세요 (오른쪽 뺨이 보이도록)."
        }
    }

    var fileTag: String {
        switch self {
        case .center: return "center"
        case .left: return "left"
        case .right: return "right"
        }
    }
}

struct FaceScanView: View {
    let calibrationProfile: CalibrationProfile?
    let onFinished: ([URL]) -> Void

    @StateObject private var captureController = TrueDepthCaptureController()

    @State private var pendingDepthBuffer: CVPixelBuffer?
    @State private var pendingCalibData: AVCameraCalibrationData?

    @State private var currentPoseIndex = 0
    @State private var capturedFiles: [URL] = []
    @State private var isCapturing = false
    @State private var errorMessage: String?
    @State private var distanceStatus: DistanceStatus = .unknown

    private var currentPose: ScanPose { ScanPose.allCases[currentPoseIndex] }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                CameraPreviewView(controller: captureController)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                // Bellus3D 스타일 거리 안내 타원 (빨강 -> 초록)
                Ellipse()
                    .stroke(distanceStatus.color, lineWidth: 6)
                    .padding(36)
            }
            .padding(.horizontal)

            VStack(spacing: 4) {
                Text("\(currentPoseIndex + 1) / \(ScanPose.allCases.count)단계 · \(currentPose.title)")
                    .font(.headline)
                Text(currentPose.instruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            Text(distanceStatus.message)
                .font(.footnote)
                .foregroundStyle(distanceStatus.color)

            if !capturedFiles.isEmpty {
                Text("완료된 각도: \(currentPoseIndex)/\(ScanPose.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let calibrationProfile {
                Label(
                    String(format: "보정계수 %.4f 적용됨", calibrationProfile.scale.scaleFactor),
                    systemImage: "checkmark.seal"
                )
                .foregroundStyle(.green)
                .font(.footnote)
            } else {
                Label("교정 없음 (raw만 저장)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.footnote)
            }

            Button {
                captureCurrentPose()
            } label: {
                if isCapturing {
                    ProgressView("메시 생성 중...")
                } else {
                    Label("\(currentPose.title) 캡처", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCapturing || pendingDepthBuffer == nil || distanceStatus != .good)
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .onAppear {
            captureController.start()
            captureController.onFrame = { _, depth, calib in
                pendingDepthBuffer = depth
                pendingCalibData = calib
                distanceStatus = DepthDistanceEstimator.estimate(depthBuffer: depth)
            }
        }
        .onDisappear {
            captureController.stop()
        }
    }

    private func captureCurrentPose() {
        guard let depth = pendingDepthBuffer else { return }
        let calib = pendingCalibData
        let pose = currentPose

        isCapturing = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            guard let mesh = DepthMeshBuilder.buildMesh(depthBuffer: depth, calibrationData: calib) else {
                DispatchQueue.main.async {
                    isCapturing = false
                    errorMessage = "메시 생성 실패. 각도/거리를 다시 맞추고 시도해주세요."
                }
                return
            }

            do {
                let timestamp = Int(Date().timeIntervalSince1970)
                let rawURL = try STLExporter.export(mesh, fileName: "raw_\(pose.fileTag)_\(timestamp)")
                var urls = [rawURL]

                if let profile = calibrationProfile {
                    let corrected = MeshCorrector.applyScaleCorrection(mesh, scaleFactor: profile.scale.scaleFactor)
                    let correctedURL = try STLExporter.export(corrected, fileName: "corrected_\(pose.fileTag)_\(timestamp)")
                    urls.append(correctedURL)
                }

                DispatchQueue.main.async {
                    isCapturing = false
                    capturedFiles.append(contentsOf: urls)

                    if currentPoseIndex < ScanPose.allCases.count - 1 {
                        currentPoseIndex += 1
                        distanceStatus = .unknown
                    } else {
                        onFinished(capturedFiles)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isCapturing = false
                    errorMessage = "STL 저장 실패: \(error.localizedDescription)"
                }
            }
        }
    }
}
