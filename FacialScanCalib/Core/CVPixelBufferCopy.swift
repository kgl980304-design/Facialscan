import CoreVideo
import Foundation

/// AVFoundation/ARKit이 콜백으로 주는 CVPixelBuffer는 내부적으로 재사용되는
/// 버퍼 풀에서 나온다. 나중에(다른 시점에) 다시 읽으려면 반드시 깊은 복사를 해둬야 한다.
/// 복사하지 않고 참조만 들고 있으면, 다음 프레임이 들어올 때 같은 메모리가
/// 덮어써져서 "여러 장을 캡처했는데 다 똑같은 내용"인 것처럼 보이는 버그가 생긴다.
enum CVPixelBufferCopy {
    static func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let format = CVPixelBufferGetPixelFormatType(source)

        var destination: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &destination)
        guard status == kCVReturnSuccess, let dest = destination else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(dest, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(dest, [])
        }

        let planeCount = CVPixelBufferGetPlaneCount(source)
        if planeCount == 0 {
            if let srcBase = CVPixelBufferGetBaseAddress(source), let dstBase = CVPixelBufferGetBaseAddress(dest) {
                let size = min(CVPixelBufferGetDataSize(source), CVPixelBufferGetDataSize(dest))
                memcpy(dstBase, srcBase, size)
            }
        } else {
            for plane in 0..<planeCount {
                guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let dst = CVPixelBufferGetBaseAddressOfPlane(dest, plane) else { continue }
                let planeHeight = CVPixelBufferGetHeightOfPlane(source, plane)
                let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let dstBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(dest, plane)
                if srcBytesPerRow == dstBytesPerRow {
                    memcpy(dst, src, planeHeight * srcBytesPerRow)
                } else {
                    let copyBytes = min(srcBytesPerRow, dstBytesPerRow)
                    for row in 0..<planeHeight {
                        memcpy(dst.advanced(by: row * dstBytesPerRow), src.advanced(by: row * srcBytesPerRow), copyBytes)
                    }
                }
            }
        }

        return dest
    }
}
