import Foundation
import simd

/// 여러 각도에서 캡처한 프레임 메시들을 하나로 합친다.
///
/// 이전 버전은 자체 point-to-point ICP로 프레임 간 정합을 직접 계산했으나,
/// 검증되지 않은 자체 알고리즘이라 큰 회전에서 정합이 발산하는 문제가 있었다.
/// 대신 ARKit(ARFaceTrackingConfiguration)이 이미 강건하게 추적한 카메라 world
/// transform을 DepthMeshBuilder 단계에서 각 정점에 미리 적용해두면, 모든 프레임이
/// 이미 같은 좌표계에 있으므로 여기서는 단순히 이어붙이기만 하면 된다.
/// (Polycam 등 실제 3D 스캔 앱들도 자체 SfM/ICP 대신 ARKit pose를 신뢰해서 사용한다)
enum MeshMerger {

    /// ARKit world transform이 이미 적용된 프레임 메시들을 단순 병합한다.
    static func mergeWorldSpaceMeshes(_ meshes: [ScanMesh]) -> ScanMesh? {
        guard !meshes.isEmpty else { return nil }

        var vertices: [SIMD3<Float>] = []
        var indices: [Int32] = []

        for mesh in meshes {
            let offset = Int32(vertices.count)
            vertices.append(contentsOf: mesh.vertices)
            indices.append(contentsOf: mesh.triangleIndices.map { $0 + offset })
        }

        return ScanMesh(vertices: vertices, triangleIndices: indices)
    }
}
