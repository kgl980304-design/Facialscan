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

            Text("고가 장비 없이 아이폰 TrueDepth 카메라로 안면을 스캔하고,\n체커보드 교정으로 정확도를 보정합니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if hasSavedCalibration {
                Label("저장된 교정 데이터가 있습니다", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }

            VStack(spacing: 12) {
                Button {
                    onStartCalibration()
                } label: {
                    Label("체커보드 교정 실행", systemImage: "grid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onSkipToScan()
                } label: {
                    Label(
                        hasSavedCalibration ? "저장된 교정으로 바로 스캔" : "교정 없이 스캔 (비교 실험용)",
                        systemImage: "arrow.forward.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 48)
    }
}
