import Foundation
import simd

/// 여러 각도에서 캡처한 프레임 메시들을 순차적으로 ICP 정합하여 하나로 합친다.
///
/// 중요: 매 프레임을 "지금까지 합쳐진 전체 점군"에 바로 정합하면, 회전이 누적될수록
/// (예: 마지막 프레임은 시작 대비 최대 90도 회전) identity를 초기값으로 쓰는 ICP가
/// 전혀 엉뚱한 곳으로 수렴해버린다. 대신 항상 "바로 직전 프레임 1장"과만 정합해서
/// (연속 촬영이라 프레임 간 회전 차이가 작으므로 identity 초기값으로도 잘 수렴함)
/// 그 결과를 계속 누적(chain)하는 방식을 쓴다.
enum MeshMerger {
    static func mergeSequentially(meshes: [ScanMesh]) -> ScanMesh? {
        guard let first = meshes.first else { return nil }

        var mergedVertices = first.vertices
        var mergedIndices = first.triangleIndices

        // 직전 프레임의 "원본(변환 전)" 정점과, 그 프레임을 기준 좌표계로 옮기는 누적 변환
        var previousRawVertices = first.vertices
        var cumulativeTransform = ICPAligner.Transform.identity

        for mesh in meshes.dropFirst() {
            // 직전 프레임 "자기 좌표계" 기준으로 정합하므로 회전 차이가 작아 identity로 충분
            let relativeTransform = ICPAligner.align(
                source: mesh.vertices,
                target: previousRawVertices
            )
            // relativeTransform: 이번 프레임 -> 직전 프레임 좌표계
            // 여기에 직전 프레임의 누적 변환을 이어 붙이면 -> 기준(첫 프레임) 좌표계로 이동
            let globalTransform = relativeTransform.then(cumulativeTransform)

            let transformedVertices = mesh.vertices.map { globalTransform.apply($0) }
            let offset = Int32(mergedVertices.count)
            mergedVertices.append(contentsOf: transformedVertices)
            mergedIndices.append(contentsOf: mesh.triangleIndices.map { $0 + offset })

            previousRawVertices = mesh.vertices
            cumulativeTransform = globalTransform
        }

        return ScanMesh(vertices: mergedVertices, triangleIndices: mergedIndices)
    }
}
