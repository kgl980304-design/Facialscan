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

            Text("여러 각도의 STL을 하나로 합치려면 CloudCompare 등에서 ICP 정합을 진행하세요.\n(앱 내부에서는 자동으로 합성하지 않습니다.)")
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

        let pose: String
        if name.contains("center") { pose = "정면" }
        else if name.contains("left") { pose = "왼쪽" }
        else if name.contains("right") { pose = "오른쪽" }
        else { pose = "" }

        return "\(pose) (\(isCorrected ? "보정 후" : "보정 전"))"
    }

    private func colorFor(_ url: URL) -> Color {
        url.lastPathComponent.hasPrefix("corrected") ? .green : .orange
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
