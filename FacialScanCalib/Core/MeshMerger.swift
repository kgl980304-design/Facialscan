import Foundation
import simd

/// 여러 각도에서 캡처한 프레임 메시들을 순차적으로 ICP 정합하여 하나로 합친다.
///
/// 중요: 매 프레임을 "지금까지 합쳐진 전체 점군"에 바로 정합하면, 회전이 누적될수록
/// (예: 마지막 프레임은 시작 대비 최대 90도 회전) identity를 초기값으로 쓰는 ICP가
/// 전혀 엉뚱한 곳으로 수렴해버린다. 대신 항상 "바로 직전 프레임 1장"과만 정합해서
/// (연속 촬영이라 프레임 간 회전 차이가 작으므로 identity 초기값으로도 잘 수렴함)
/// 그 결과를 계속 누적(chain)하는 방식을 쓴다.
///
/// 추가: 정합 신뢰도(inlier 비율)가 임계값보다 낮으면 "정합 실패"로 보고
/// 그 프레임은 병합에서 아예 제외한다 (잘못된 정합이 최종 결과를 망치는 것 방지).
enum MeshMerger {

    struct MergeReport {
        let mesh: ScanMesh
        /// 정합 신뢰도가 낮아 병합에서 제외된 프레임 인덱스들 (0 = 첫 프레임 기준, dropFirst 이후 순번)
        let droppedFrameIndices: [Int]
    }

    static func mergeSequentially(
        meshes: [ScanMesh],
        minInlierRatio: Float = 0.35
    ) -> MergeReport? {
        guard let first = meshes.first else { return nil }

        var mergedVertices = first.vertices
        var mergedIndices = first.triangleIndices

        var previousRawVertices = first.vertices
        var cumulativeTransform = ICPAligner.Transform.identity
        var droppedIndices: [Int] = []

        for (offset, mesh) in meshes.dropFirst().enumerated() {
            let result = ICPAligner.align(source: mesh.vertices, target: previousRawVertices)

            guard result.inlierRatio >= minInlierRatio else {
                // 정합 신뢰도가 너무 낮음 -> 이 프레임은 병합에서 제외 (품질 저하 방지)
                droppedIndices.append(offset + 1)
                // 다음 프레임은 이 프레임을 기준으로 삼지 않고, 마지막으로 성공한 프레임 기준을 유지
                continue
            }

            let globalTransform = result.transform.then(cumulativeTransform)
            let transformedVertices = mesh.vertices.map { globalTransform.apply($0) }

            let offsetIdx = Int32(mergedVertices.count)
            mergedVertices.append(contentsOf: transformedVertices)
            mergedIndices.append(contentsOf: mesh.triangleIndices.map { $0 + offsetIdx })

            previousRawVertices = mesh.vertices
            cumulativeTransform = globalTransform
        }

        let mesh = ScanMesh(vertices: mergedVertices, triangleIndices: mergedIndices)
        return MergeReport(mesh: mesh, droppedFrameIndices: droppedIndices)
    }
}
