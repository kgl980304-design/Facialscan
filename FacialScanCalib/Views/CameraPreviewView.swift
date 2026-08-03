import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let controller: TrueDepthCaptureController

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer = controller.makePreviewLayer()
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                guard let layer = previewLayer else { return }
                layer.frame = bounds
                self.layer.addSublayer(layer)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
