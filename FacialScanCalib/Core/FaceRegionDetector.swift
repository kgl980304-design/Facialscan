import Vision
import UIKit

/// Vision 프레임워크로 컬러 이미지에서 얼굴 영역(바운딩 박스)만 검출한다.
/// 배경/손/어깨 등이 메시에 섞여 들어오는 문제를 해결하기 위해,
/// DepthMeshBuilder가 이 영역 밖의 깊이 픽셀은 아예 무시하도록 한다.
///
/// 주의: UIImage의 imageOrientation 태그(.right 등)를 신뢰하지 않고,
/// 원본 CGImage를 orientation: .up으로 명시해서 처리한다. 이렇게 해야
/// 깊이 맵(CVPixelBuffer, 회전 태그 없는 원본 좌표계)과 좌표계가 확실히 일치한다.
enum FaceRegionDetector {

    /// - Returns: 얼굴 바운딩 박스 (원본/비회전 픽셀 좌표계, 코/턱/귀가 안 잘리도록 여유 마진 포함). 검출 실패 시 nil.
    static func detectFaceBoundingBox(in image: UIImage, marginRatio: CGFloat = 0.35) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectFaceRectanglesRequest()
        // 원본 CGImage 픽셀 좌표계를 그대로 쓰기 위해 orientation을 .up으로 고정
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let face = (request.results as? [VNFaceObservation])?.first else { return nil }

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let box = face.boundingBox // 정규화 좌표 (0~1), 원점 좌하단

        let x = box.minX * imgW
        let y = (1 - box.maxY) * imgH // 좌상단 원점으로 변환
        let w = box.width * imgW
        let h = box.height * imgH

        let marginX = w * marginRatio
        let marginY = h * marginRatio

        return CGRect(
            x: max(0, x - marginX),
            y: max(0, y - marginY),
            width: min(imgW - max(0, x - marginX), w + marginX * 2),
            height: min(imgH - max(0, y - marginY), h + marginY * 2)
        )
    }
}
