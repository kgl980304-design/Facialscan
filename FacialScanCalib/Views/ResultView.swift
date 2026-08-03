import SwiftUI
import UIKit

struct ResultView: View {
    let files: [URL]
    let onRestart: () -> Void

    @State private var shareItem: ShareItem?

    private struct ShareItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("각도별 STL 파일이 저장되었습니다")
                .font(.title3).bold()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(files, id: \.self) { url in
                        fileRow(url: url)
                    }
                }
                .padding(.horizontal)
            }

            Text("맨 위 ★ 표시된 파일이 앱이 자동으로 정합(ICP)한 최종 결과물입니다.\n결과가 만족스럽지 않으면 아래 개별 프레임 STL로 CloudCompare에서 직접 재정합하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("새 스캔 시작") { onRestart() }
                .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.top, 24)
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }
    }

    private func fileRow(url: URL) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(displayName(for: url)).bold()
                Text(url.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                shareItem = ShareItem(url: url)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .padding()
        .background(colorFor(url).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func displayName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let isCorrected = name.hasPrefix("corrected")
        let versionLabel = isCorrected ? "보정 후" : "보정 전"

        if name.contains("merged") {
            return "★ 자동 정합 최종본 (\(versionLabel))"
        }
        if let range = name.range(of: "frame") {
            let afterFrame = name[range.upperBound...]
            let digits = afterFrame.prefix(while: { $0.isNumber })
            if !digits.isEmpty {
                return "개별 프레임 \(digits) (\(versionLabel))"
            }
        }
        return versionLabel
    }

    private func colorFor(_ url: URL) -> Color {
        let name = url.lastPathComponent
        if name.contains("merged") { return .blue }
        return name.hasPrefix("corrected") ? .green : .orange
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
