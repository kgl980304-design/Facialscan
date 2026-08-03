import SwiftUI

struct FaceScanView: View {
    let calibrationProfile: CalibrationProfile?
    let onFinished: (URL, URL?) -> Void

    @StateObject private var faceController = FaceScanController()
    @State private var errorMessage: String?
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 16) {
            ARFaceSceneView(session: faceController.session)
                .aspectRatio(3/4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(faceController.isTracking ? .green : .orange, lineWidth: 3)
                )
                .padding(.horizontal)

            Text(faceController.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let profile = calibrationProfile {
                Label(
                    String(format: "적용될 보정계수: %.4f", profile.scale.scaleFactor),
                    systemImage: "checkmark.seal"
                )
                .foregroundStyle(.green)
                .font(.footnote)
            } else {
                Label("교정 데이터 없음 (raw 스캔만 저장됩니다)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.footnote)
            }

            Button {
                captureAndExport()
            } label: {
                if isExporting {
                    ProgressView()
                } else {
                    Label("스캔 캡처 및 STL 추출", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!faceController.isTracking || isExporting)
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .onAppear { faceController.start() }
        .onDisappear { faceController.stop() }
    }

    private func captureAndExport() {
        faceController.captureSnapshot()
        guard let mesh = faceController.capturedMesh else {
            errorMessage = "메시 캡처에 실패했습니다."
            return
        }

        isExporting = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let timestamp = Int(Date().timeIntervalSince1970)
                let rawURL = try STLExporter.export(mesh, fileName: "raw_scan_\(timestamp)")

                var correctedURL: URL?
                if let profile = calibrationProfile {
                    let corrected = MeshCorrector.applyScaleCorrection(mesh, scaleFactor: profile.scale.scaleFactor)
                    correctedURL = try STLExporter.export(corrected, fileName: "corrected_scan_\(timestamp)")
                }

                DispatchQueue.main.async {
                    isExporting = false
                    onFinished(rawURL, correctedURL)
                }
            } catch {
                DispatchQueue.main.async {
                    isExporting = false
                    errorMessage = "STL 저장 실패: \(error.localizedDescription)"
                }
            }
        }
    }
}
