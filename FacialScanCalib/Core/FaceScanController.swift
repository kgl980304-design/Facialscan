import ARKit
import Combine
import simd

/// ARKit TrueDepth Face Tracking으로 안면 메시를 캡처.
final class FaceScanController: NSObject, ObservableObject, ARSessionDelegate {

    @Published var isTracking = false
    @Published var lastVertexCount = 0
    @Published var statusMessage = "얼굴을 프레임 안에 위치시키세요."
    @Published var capturedMesh: ScanMesh?

    let session = ARSession()
    private var latestFaceAnchor: ARFaceAnchor?

    override init() {
        super.init()
        session.delegate = self
    }

    func start() {
        guard ARFaceTrackingConfiguration.isSupported else {
            statusMessage = "이 기기는 TrueDepth 얼굴 추적을 지원하지 않습니다."
            return
        }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = true
        config.maximumNumberOfTrackedFaces = 1
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
    }

    /// 현재 추적 중인 얼굴의 지오메트리를 스냅샷으로 캡처.
    /// 여러 프레임을 평균내고 싶다면 이 함수를 여러 번 호출해 accumulate하는 방식으로 확장 가능.
    func captureSnapshot() {
        guard let anchor = latestFaceAnchor else {
            statusMessage = "아직 얼굴이 인식되지 않았습니다."
            return
        }
        let geometry = anchor.geometry
        let transform = anchor.transform // 얼굴 앵커의 월드 좌표계 변환

        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(geometry.vertices.count)
        for v in geometry.vertices {
            let world = transform * SIMD4<Float>(v.x, v.y, v.z, 1.0)
            vertices.append(SIMD3<Float>(world.x, world.y, world.z))
        }

        var indices: [Int32] = []
        indices.reserveCapacity(geometry.triangleIndices.count)
        for i in geometry.triangleIndices {
            indices.append(Int32(i))
        }

        capturedMesh = ScanMesh(vertices: vertices, triangleIndices: indices)
        lastVertexCount = vertices.count
        statusMessage = "스캔 캡처 완료 (\(vertices.count)개 정점)"
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if let anchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first {
            latestFaceAnchor = anchor
            if !isTracking {
                isTracking = true
                statusMessage = "얼굴 추적 중..."
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        statusMessage = "ARSession 오류: \(error.localizedDescription)"
    }

    func sessionWasInterrupted(_ session: ARSession) {
        isTracking = false
        statusMessage = "세션이 일시 중단되었습니다."
    }
}
