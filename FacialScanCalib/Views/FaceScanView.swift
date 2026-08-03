import SwiftUI
import AVFoundation

/// 회전 단계 순서 (Bellus3D 방식: 정면 -> 오른쪽 -> 정면 복귀 -> 왼쪽 -> 정면 복귀).
/// 각 단계가 진행되는 "동안 계속" 일정 간격으로 프레임을 자동 캡처해서,
/// 인접 프레임끼리 각도 차이가 작아 나중에 CloudCompare에서 정합(ICP)하기 쉽게 한다.
enum ScanStage: Int, CaseIterable {
    case holdCenter, turnRight, returnCenter1, turnLeft, returnCenter2

    var instruction: String {
        switch self {
        case .holdCenter: return "정면을 보고 잠시 멈추세요"
        case .turnRight: return "천천히 고개를 오른쪽으로 돌리세요"
        case .returnCenter1: return "천천히 정면으로 돌아오세요"
        case .turnLeft: return "천천히 고개를 왼쪽으로 돌리세요"
        case .returnCenter2: return "천천히 정면으로 돌아오세요"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .holdCenter: return 1.2
        case .turnRight: return 2.6
        case .returnCenter1: return 1.2
        case .turnLeft: return 2.6
        case .returnCenter2: return 1.2
        }
    }
}

/// TrueDepth 원본 깊이 데이터를 이용한 다각도 연속 캡처 얼굴 스캔 화면.
struct FaceScanView: View {
    let calibrationProfile: CalibrationProfile?
    let onFinished: ([URL]) -> Void

    @StateObject private var captureController = TrueDepthCaptureController()

    @State private var pendingDepthBuffer: CVPixelBuffer?
    @State private var pendingCalibData: AVCameraCalibrationData?
    @State private var distanceStatus: DistanceStatus = .unknown

    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var stageIndex = 0
    @State private var stageElapsed: TimeInterval = 0
    @State private var captureAccumulator: TimeInterval = 0
    @State private var capturedFrames: [(depth: CVPixelBuffer, calib: AVCameraCalibrationData?)] = []
    @State private var processedCount = 0
    @State private var processingPhase = ""
    @State private var errorMessage: String?

    // 캡처 간격: 짧을수록 프레임이 촘촘해서 정합하기 쉽지만 파일 수/처리 시간이 늘어난다.
    private let captureInterval: TimeInterval = 0.35
    private let tickTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var currentStage: ScanStage { ScanStage.allCases[stageIndex] }
    private var totalDuration: TimeInterval { ScanStage.allCases.reduce(0) { $0 + $1.duration } }
    private var elapsedTotal: TimeInterval {
        ScanStage.allCases.prefix(stageIndex).reduce(0) { $0 + $1.duration } + stageElapsed
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                CameraPreviewView(controller: captureController)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Ellipse()
                    .stroke(isRecording ? Color.blue : distanceStatus.color, lineWidth: 6)
                    .padding(36)

                if isProcessing {
                    Color.black.opacity(0.45)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text(processingPhase)
                            .foregroundStyle(.white)
                            .font(.footnote)
                    }
                }
            }
            .padding(.horizontal)

            if isRecording {
                ProgressView(value: elapsedTotal, total: totalDuration)
                    .padding(.horizontal)
                Text(currentStage.instruction)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("자동 캡처됨: \(capturedFrames.count)장")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !isProcessing {
                Text(distanceStatus.message)
                    .font(.subheadline)
                    .foregroundStyle(distanceStatus.color)
                Text("버튼을 누르면 정면 → 오른쪽 → 정면 → 왼쪽 → 정면 순서로 안내가 나오고,\n그 동안 자동으로 여러 장을 이어서 캡처합니다. 천천히, 부드럽게 움직여주세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
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

            if !isRecording && !isProcessing {
                Button {
                    startRecording()
                } label: {
                    Label("다각도 스캔 시작", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pendingDepthBuffer == nil || distanceStatus != .good)
                .padding(.horizontal)
            }

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
        .onReceive(tickTimer) { _ in
            guard isRecording else { return }
            advanceRecording(tick: 0.1)
        }
    }

    private func startRecording() {
        capturedFrames.removeAll()
        stageIndex = 0
        stageElapsed = 0
        captureAccumulator = 0
        errorMessage = nil
        isRecording = true
    }

    private func advanceRecording(tick: TimeInterval) {
        stageElapsed += tick
        captureAccumulator += tick

        // 거리가 적정 범위일 때만 캡처 (너무 가깝거나 멀면 그 순간은 건너뛰고 타임라인은 계속 진행)
        if captureAccumulator >= captureInterval {
            captureAccumulator = 0
            if distanceStatus == .good, let depth = pendingDepthBuffer {
                capturedFrames.append((depth: depth, calib: pendingCalibData))
            }
        }

        if stageElapsed >= currentStage.duration {
            stageElapsed = 0
            if stageIndex < ScanStage.allCases.count - 1 {
                stageIndex += 1
            } else {
                isRecording = false
                processCapturedFrames()
            }
        }
    }

    private func processCapturedFrames() {
        guard !capturedFrames.isEmpty else {
            errorMessage = "캡처된 프레임이 없습니다. 거리를 맞추고 다시 시도해주세요."
            return
        }

        isProcessing = true
        processedCount = 0
        processingPhase = "메시 생성 중..."
        let frames = capturedFrames
        let profile = calibrationProfile
        let sessionTimestamp = Int(Date().timeIntervalSince1970)

        DispatchQueue.global(qos: .userInitiated).async {
            var perFrameMeshes: [ScanMesh] = []
            var perFrameURLs: [URL] = []

            for (index, frame) in frames.enumerated() {
                if let mesh = DepthMeshBuilder.buildMesh(depthBuffer: frame.depth, calibrationData: frame.calib) {
                    perFrameMeshes.append(mesh)
                    let tag = String(format: "%03d", index)
                    if let url = try? STLExporter.export(mesh, fileName: "raw_frame\(tag)_\(sessionTimestamp)") {
                        perFrameURLs.append(url)
                    }
                }
                DispatchQueue.main.async {
                    processedCount = index + 1
                    processingPhase = "메시 생성 중... (\(index + 1)/\(frames.count))"
                }
            }

            guard !perFrameMeshes.isEmpty else {
                DispatchQueue.main.async {
                    isProcessing = false
                    errorMessage = "모든 프레임에서 메시 생성에 실패했습니다. 다시 시도해주세요."
                }
                return
            }

            DispatchQueue.main.async {
                processingPhase = "여러 각도 자동 정합(ICP) 중... 잠시만 기다려주세요"
            }

            var outputURLs: [URL] = []

            if let merged = MeshMerger.mergeSequentially(meshes: perFrameMeshes) {
                if let rawMergedURL = try? STLExporter.export(merged, fileName: "raw_merged_\(sessionTimestamp)") {
                    outputURLs.append(rawMergedURL)
                }
                if let profile {
                    let corrected = MeshCorrector.applyScaleCorrection(merged, scaleFactor: profile.scale.scaleFactor)
                    if let correctedMergedURL = try? STLExporter.export(corrected, fileName: "corrected_merged_\(sessionTimestamp)") {
                        outputURLs.append(correctedMergedURL)
                    }
                }
            }

            // 개별 프레임 STL도 함께 남겨서, 자동 정합 결과가 만족스럽지 않을 경우
            // CloudCompare 등에서 수동으로 다시 정합할 수 있도록 한다.
            outputURLs.append(contentsOf: perFrameURLs)

            DispatchQueue.main.async {
                isProcessing = false
                if outputURLs.isEmpty {
                    errorMessage = "정합에 실패했습니다. 다시 시도해주세요."
                } else {
                    onFinished(outputURLs)
                }
            }
        }
    }
}
