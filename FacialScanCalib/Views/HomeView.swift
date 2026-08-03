import SwiftUI

struct HomeView: View {
    let hasSavedCalibration: Bool
    let onStartCalibration: () -> Void
    let onSkipToScan: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "faceid")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("페이셜 스캐너 대체 앱")
                .font(.title2).bold()

            Text("TrueDepth 깊이 데이터를 그대로 3D 메시로 변환합니다.\n체커보드 교정을 하면 정확도가 보정된 STL도 함께 저장됩니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if hasSavedCalibration {
                Label("저장된 교정 데이터가 있습니다", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.footnote)
            }

            VStack(spacing: 12) {
                Button {
                    onSkipToScan()
                } label: {
                    Label("스캔 수행", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onStartCalibration()
                } label: {
                    Label("캘리브레이션", systemImage: "grid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                Label("스캔 수행: 교정 없이 바로 촬영 → STL 추출", systemImage: "1.circle")
                Label("캘리브레이션: 체커보드 자동 촬영 → 이어서 바로 얼굴 스캔 → 보정된 STL 추출", systemImage: "2.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 40)
    }
}
