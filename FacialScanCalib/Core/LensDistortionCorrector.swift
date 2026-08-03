import Foundation
import AVFoundation
import CoreGraphics

/// 체커보드를 인쇄/촬영하지 않아도 되는 대안 보정법.
///
/// iPhone은 기기 개별 생산 시 렌즈 왜곡을 공장에서 미리 측정해서
/// `AVCameraCalibrationData.inverseLensDistortionLookupTable`에 담아 제공한다.
/// 우리가 체커보드로 30초 만에 대충 추정하는 왜곡계수보다, 이 팩토리 측정값이
/// 오히려 더 정밀할 수 있다 (개별 기기 단위로, 정밀 장비로 측정된 값이므로).
///
/// 참고: Apple 공식 문서/샘플 코드에 기술된 lookup table 보정 공식을 따른다.
enum LensDistortionCorrector {

    /// 왜곡된 픽셀 좌표를 보정된(이상적인 핀홀 모델) 좌표로 변환한다.
    /// - Returns: 보정된 좌표. lookup table이 없으면 입력 좌표를 그대로 반환한다.
    static func correct(
        point: CGPoint,
        calibrationData: AVCameraCalibrationData,
        imageSize: CGSize
    ) -> CGPoint {
        guard let lookupTable = calibrationData.inverseLensDistortionLookupTable else {
            return point
        }

        let opticalCenter = calibrationData.lensDistortionCenter

        let deltaOcxMax = Float(max(opticalCenter.x, imageSize.width - opticalCenter.x))
        let deltaOcyMax = Float(max(opticalCenter.y, imageSize.height - opticalCenter.y))
        let rMax = sqrt(deltaOcxMax * deltaOcxMax + deltaOcyMax * deltaOcyMax)

        let vx = Float(point.x - opticalCenter.x)
        let vy = Float(point.y - opticalCenter.y)
        let rPoint = sqrt(vx * vx + vy * vy)

        guard rPoint > 0, rMax > 0 else { return point }

        let magnifications = lookupTable.withUnsafeBytes { raw -> [Float] in
            Array(raw.bindMemory(to: Float32.self))
        }
        guard !magnifications.isEmpty else { return point }

        let ratio = min(max(rPoint / rMax, 0), 1)
        let index = min(Int(Float(magnifications.count - 1) * ratio), magnifications.count - 1)
        let magnification = magnifications[index]

        let newVx = vx + magnification * vx
        let newVy = vy + magnification * vy

        return CGPoint(x: opticalCenter.x + CGFloat(newVx), y: opticalCenter.y + CGFloat(newVy))
    }
}
