import SwiftUI
import UIKit

struct ResultView: View {
    let rawSTLURL: URL?
    let correctedSTLURL: URL?
    let onRestart: () -> Void

    @State private var shareItem: ShareItem?

    private struct ShareItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("STL 파일이 저장되었습니다")
                .font(.title3).bold()

            if let rawSTLURL {
                fileRow(title: "보정 전 (raw)", url: rawSTLURL, color: .orange)
            }
            if let correctedSTLURL {
                fileRow(title: "보정 후 (corrected)", url: correctedSTLURL, color: .green)
            } else {
                Text("교정 데이터가 없어 보정 후 STL은 생성되지 않았습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("두 파일을 CloudCompare / MeshLab 등에서 기준 모델과 ICP 정합 후 RMS 오차를 비교하세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("새 스캔 시작") { onRestart() }
                .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.top, 32)
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }
    }

    private func fileRow(title: String, url: URL, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(url.lastPathComponent)
                    .font(.caption)
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
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
