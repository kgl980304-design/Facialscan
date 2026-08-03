import Foundation
import simd

/// 여러 각도에서 캡처한 프레임 메시들을 순차적으로 ICP 정합하여 하나의 메시로 합친다.
/// 첫 프레임을 기준 좌표계로 삼고, 이후 프레임들은 지금까지 합쳐진 점군에 맞춰 정렬한다.
enum MeshMerger {
    static func mergeSequentially(meshes: [ScanMesh]) -> ScanMesh? {
        guard let first = meshes.first else { return nil }

        var mergedVertices = first.vertices
        var mergedIndices = first.triangleIndices

        for mesh in meshes.dropFirst() {
            let transform = ICPAligner.align(source: mesh.vertices, target: mergedVertices)
            let transformedVertices = mesh.vertices.map { transform.apply($0) }

            let offset = Int32(mergedVertices.count)
            mergedVertices.append(contentsOf: transformedVertices)
            mergedIndices.append(contentsOf: mesh.triangleIndices.map { $0 + offset })
        }

        return ScanMesh(vertices: mergedVertices, triangleIndices: mergedIndices)
    }
}
