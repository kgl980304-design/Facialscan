import Foundation
import simd

/// 체커보드 교정에서 얻은 스케일 보정계수를 안면 메시에 적용.
/// (현재는 중심점 기준 균일 스케일 보정. 필요시 비선형 보정으로 확장 가능)
enum MeshCorrector {

    static func applyScaleCorrection(_ mesh: ScanMesh, scaleFactor: Double) -> ScanMesh {
        guard abs(scaleFactor - 1.0) > 1e-6, !mesh.vertices.isEmpty else { return mesh }

        // 정점들의 중심(centroid)을 기준으로 스케일 적용해야
        // 얼굴이 원점에서 멀리 떨어져 있어도 위치가 왜곡되지 않음
        var centroid = SIMD3<Float>(repeating: 0)
        for v in mesh.vertices { centroid += v }
        centroid /= Float(mesh.vertices.count)

        let scale = Float(scaleFactor)
        let corrected = mesh.vertices.map { v -> SIMD3<Float> in
            let d = v - centroid
            return centroid + d * scale
        }

        return ScanMesh(vertices: corrected, triangleIndices: mesh.triangleIndices)
    }
}
