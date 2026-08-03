import Foundation
import simd

/// ScanMesh를 바이너리 STL 파일로 저장.
enum STLExporter {

    enum ExportError: Error {
        case emptyMesh
        case fileWriteFailed
    }

    /// - Parameters:
    ///   - mesh: 정점(vertex)과 삼각형 인덱스(triangleIndices, 3개씩 묶여 하나의 삼각형)
    ///   - fileName: 확장자 제외 파일명
    /// - Returns: 저장된 파일 URL
    @discardableResult
    static func export(_ mesh: ScanMesh, fileName: String) throws -> URL {
        guard !mesh.vertices.isEmpty, !mesh.triangleIndices.isEmpty else {
            throw ExportError.emptyMesh
        }

        let triangleCount = mesh.triangleIndices.count / 3
        var data = Data()

        // 80바이트 헤더
        var header = [UInt8](repeating: 0, count: 80)
        let headerText = Array("FacialScanCalib STL export".utf8)
        header.replaceSubrange(0..<min(headerText.count, 80), with: headerText)
        data.append(contentsOf: header)

        // 삼각형 개수 (UInt32, little-endian)
        var count = UInt32(triangleCount).littleEndian
        data.append(Data(bytes: &count, count: 4))

        for t in 0..<triangleCount {
            let i0 = Int(mesh.triangleIndices[t * 3])
            let i1 = Int(mesh.triangleIndices[t * 3 + 1])
            let i2 = Int(mesh.triangleIndices[t * 3 + 2])

            guard i0 < mesh.vertices.count, i1 < mesh.vertices.count, i2 < mesh.vertices.count else { continue }

            let v0 = mesh.vertices[i0]
            let v1 = mesh.vertices[i1]
            let v2 = mesh.vertices[i2]

            let normal = triangleNormal(v0, v1, v2)

            appendFloat3(&data, normal)
            appendFloat3(&data, v0)
            appendFloat3(&data, v1)
            appendFloat3(&data, v2)

            // attribute byte count (사용 안 함)
            var attr: UInt16 = 0
            data.append(Data(bytes: &attr, count: 2))
        }

        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docsURL.appendingPathComponent("\(fileName).stl")

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ExportError.fileWriteFailed
        }

        return fileURL
    }

    private static func triangleNormal(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        return len > 0 ? n / len : SIMD3<Float>(0, 0, 1)
    }

    private static func appendFloat3(_ data: inout Data, _ v: SIMD3<Float>) {
        var x = v.x, y = v.y, z = v.z
        data.append(Data(bytes: &x, count: 4))
        data.append(Data(bytes: &y, count: 4))
        data.append(Data(bytes: &z, count: 4))
    }
}
