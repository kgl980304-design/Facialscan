import Foundation
import CoreVideo
import SwiftUI

/// 촬영 거리 안내 상태 (Bellus3D FaceApp의 빨강/초록 타원과 동일한 컨셉)
enum DistanceStatus: Equatable {
    case unknown
    case tooClose
    case tooFar
    case good

    var color: Color {
        switch self {
        case .unknown: return .gray
        case .tooClose, .tooFar: return .red
        case .good: return .green
        }
    }

    var message: String {
        switch self {
        case .unknown: return "얼굴을 화면 중앙에 맞춰주세요."
        case .tooClose: return "너무 가깝습니다. 조금 뒤로 이동하세요."
        case .tooFar: return "너무 멉니다. 조금 더 가까이 이동하세요."
        case .good: return "좋습니다! 이 거리를 유지한 채 캡처하세요."
        }
    }
}

enum DepthDistanceEstimator {
    /// 화면 중앙 20% 영역의 평균 깊이를 측정해서 적정 거리 여부를 판단한다.
    static func estimate(
        depthBuffer: CVPixelBuffer,
        goodRangeMeters: ClosedRange<Float> = 0.25...0.45
    ) -> DistanceStatus {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        guard let base = CVPixelBufferGetBaseAddress(depthBuffer) else { return .unknown }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)

        let regionW = max(4, width / 5)
        let regionH = max(4, height / 5)
        let startX = (width - regionW) / 2
        let startY = (height - regionH) / 2

        var sum: Float = 0
        var count = 0

        for y in startY..<(startY + regionH) {
            let rowPtr = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in startX..<(startX + regionW) {
                let d = rowPtr[x]
                if d.isFinite, d > 0.05, d < 2.0 {
                    sum += d
                    count += 1
                }
            }
        }

        guard count > 20 else { return .unknown }
        let avg = sum / Float(count)

        if avg < goodRangeMeters.lowerBound { return .tooClose }
        if avg > goodRangeMeters.upperBound { return .tooFar }
        return .good
    }
}
