import SwiftUI
import ARKit
import AVFoundation

/// 회전 단계 순서 (Bellus3D 방식: 정면 -> 오른쪽 -> 정면 복귀 -> 왼쪽 -> 정면 복귀).
/// 각 단계가 진행되는 "동안 계속" 일정 간격으로 프레임을 자동 캡처한다.
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

/// ARKit(ARFaceTrackingConfiguration)의 검증된 pose 추적 + TrueDepth 원본 깊이 맵을
/// 함께 사용하는 다각도 연속 캡처 얼굴 스캔 화면.
/// 프레임 간 정합은 자체 ICP가 아니라 ARKit이 추적한 카메라 world transform을 그대로 신뢰한다.
struct FaceScanView: View {
    let calibrationProfile: CalibrationProfile?
    let onFinished: ([URL]) -> Void

    @StateObject private var captureController = ARDepthCaptureController()

    @State private var pendingDepthBuffer: CVPixelBuffer?
    @State private var pendingWorldTransform: simd_float4x4?
    @State private var pendingCalibData: AVCameraCalibrationData?
    @State private var pendingColorBuffer: CVPixelBuffer?
    @State private var distanceStatus: DistanceStatus = .unknown

    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var stageIndex = 0
    @State private var stageElapsed: TimeInterval = 0
    @State private var captureAccumulator: TimeInterval = 0

    private struct CapturedFrame {
        let depth: CVPixelBuffer
        let worldTransform: simd_float4x4
        let calib: AVCameraCalibrationData?
        let colorBuffer: CVPixelBuffer
    }
    @State private var capturedFrames: [CapturedFrame] = []
    @State private var processedCount = 0
    @State private var processingPhase = ""
    @State private var errorMessage: String?

    private let captureInterval: TimeInterval = 0.5
    private let tickTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var currentStage: ScanStage { ScanStage.allCases[stageIndex] }
    private var totalDuration: TimeInterval { ScanStage.allCases.reduce(0) { $0 + $1.duration } }
    private var elapsedTotal: TimeInterval {
        ScanStage.allCases.prefix(stageIndex).reduce(0) { $0 + $1.duration } + stageElapsed
    }

    private var canStart: Bool {
        pendingDepthBuffer != nil && distanceStatus == .good && captureController.trackingQuality.isUsable
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ARFaceSceneView(session: captureController.session)
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

            Label(captureController.trackingQuality.description,
                  systemImage: captureController.trackingQuality.isUsable ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(captureController.trackingQuality.isUsable ? .green : .orange)

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
                Text("버튼을 누르면 정면 → 오른쪽 → 정면 → 왼쪽 → 정면 순서로 안내가 나오고,\nARKit이 추적하는 카메라 위치를 기준으로 자동 정렬됩니다.")
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
                .disabled(!canStart)
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top)
        .onAppear {
            captureController.start()
            captureController.onFrame = { depth, transform, calib, colorBuffer in
                pendingDepthBuffer = depth
                pendingWorldTransform = transform
                pendingCalibData = calib
                pendingColorBuffer = colorBuffer
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

        if captureAccumulator >= captureInterval {
            captureAccumulator = 0
            // ARKit 추적이 정상이고 거리도 적정일 때만 캡처 (품질 낮은 프레임 자동 제외)
            // 중요: CVPixelBuffer는 재사용되는 풀에서 나오므로, 나중에 처리하기 위해
            // 저장해두려면 반드시 이 시점에 깊은 복사를 해야 한다. 참조만 저장하면
            // 나중에 처리할 때 이미 다른 프레임 데이터로 덮어써진 상태가 된다.
            if distanceStatus == .good,
               captureController.trackingQuality.isUsable,
               let depth = pendingDepthBuffer,
               let transform = pendingWorldTransform,
               let colorBuffer = pendingColorBuffer,
               let depthCopy = CVPixelBufferCopy.copy(depth),
               let colorCopy = CVPixelBufferCopy.copy(colorBuffer) {
                capturedFrames.append(CapturedFrame(
                    depth: depthCopy, worldTransform: transform, calib: pendingCalibData, colorBuffer: colorCopy
                ))
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

    private func colorBufferToImage(_ buffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func processCapturedFrames() {
        guard !capturedFrames.isEmpty else {
            errorMessage = "캡처된 프레임이 없습니다. 거리/추적 상태를 확인하고 다시 시도해주세요."
            return
        }

        isProcessing = true
        processedCount = 0
        processingPhase = "메시 생성 중..."
        let frames = capturedFrames
        let profile = calibrationProfile
        let sessionTimestamp = Int(Date().timeIntervalSince1970)

        DispatchQueue.global(qos: .userInitiated).async {
            var worldMeshes: [ScanMesh] = []
            var perFrameURLs: [URL] = []

            for (index, frame) in frames.enumerated() {
                let colorImage = colorBufferToImage(frame.colorBuffer)
                let faceBox = colorImage.flatMap { FaceRegionDetector.detectFaceBoundingBox(in: $0) }
                let colorPixelSize: CGSize? = colorImage?.cgImage.map {
                    CGSize(width: $0.width, height: $0.height)
                }

                // world 좌표계 메시 (ARKit pose 적용, 최종 병합용)
                if let worldMesh = DepthMeshBuilder.buildMesh(
                    depthBuffer: frame.depth,
                    calibrationData: frame.calib,
                    faceBoxInColorPixels: faceBox,
                    colorImagePixelSize: colorPixelSize,
                    worldTransform: frame.worldTransform
                ) {
                    worldMeshes.append(worldMesh)
                }

                // 카메라 로컬 메시 (개별 프레임 확인/백업용)
                if let localMesh = DepthMeshBuilder.buildMesh(
                    depthBuffer: frame.depth,
                    calibrationData: frame.calib,
                    faceBoxInColorPixels: faceBox,
                    colorImagePixelSize: colorPixelSize
                ) {
                    let tag = String(format: "%03d", index)
                    if let url = try? STLExporter.export(localMesh, fileName: "raw_frame\(tag)_\(sessionTimestamp)") {
                        perFrameURLs.append(url)
                    }
                }

                DispatchQueue.main.async {
                    processedCount = index + 1
                    processingPhase = "메시 생성 중... (\(index + 1)/\(frames.count))"
                }
            }

            guard !worldMeshes.isEmpty else {
                DispatchQueue.main.async {
                    isProcessing = false
                    errorMessage = "모든 프레임에서 메시 생성에 실패했습니다. 다시 시도해주세요."
                }
                return
            }

            DispatchQueue.main.async {
                processingPhase = "ARKit pose 기준으로 병합 중..."
            }

            var outputURLs: [URL] = []

            if let merged = MeshMerger.mergeWorldSpaceMeshes(worldMeshes) {
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

            outputURLs.append(contentsOf: perFrameURLs)

            DispatchQueue.main.async {
                isProcessing = false
                if outputURLs.isEmpty {
                    errorMessage = "병합에 실패했습니다. 다시 시도해주세요."
                } else {
                    onFinished(outputURLs)
                }
            }
        }
    }
}
