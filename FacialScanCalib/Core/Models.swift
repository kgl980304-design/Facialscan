import Foundation
import simd

/// 체커보드 패턴 스펙 (내부 코너 개수 기준)
struct CheckerboardPattern {
    /// 가로/세로 내부 코너 개수 (예: 10x7 사각형이면 9x6 코너)
    var cornersX: Int = 9
    var cornersY: Int = 6
    /// 정사각형 한 변의 실제 길이 (mm)
    var squareSizeMM: Double = 20.0
}

/// OpenCV calibrateCamera 결과
struct CameraCalibrationResult: Codable, Equatable {
    /// 3x3 카메라 행렬, row-major: [fx, 0, cx, 0, fy, cy, 0, 0, 1]
    let cameraMatrix: [Double]
    /// [k1, k2, p1, p2, k3]
    let distCoeffs: [Double]
    /// 재투영 오차 (px 단위, 작을수록 좋음)
    let reprojectionError: Double
    let timestamp: Date

    var fx: Double { cameraMatrix[0] }
    var fy: Double { cameraMatrix[4] }
    var cx: Double { cameraMatrix[2] }
    var cy: Double { cameraMatrix[5] }
}

/// 체커보드 깊이 실측을 통한 스케일 보정 결과
struct ScaleCalibrationResult: Codable, Equatable {
    /// 실측(깊이 데이터 기반) 평균 사각형 크기 (mm)
    let measuredSquareSizeMM: Double
    /// 알려진 실제 사각형 크기 (mm)
    let knownSquareSizeMM: Double
    /// 샘플 개수 (사용된 인접 코너 쌍 개수)
    let sampleCount: Int

    /// 보정 계수 = known / measured
    /// 예: 측정값이 실제보다 크게 나오면 계수는 1보다 작아져 축소 보정
    var scaleFactor: Double {
        guard measuredSquareSizeMM > 0 else { return 1.0 }
        return knownSquareSizeMM / measuredSquareSizeMM
    }
}

/// 최종 보정 프로파일 (앱 내에서 저장/재사용)
struct CalibrationProfile: Codable, Equatable {
    let camera: CameraCalibrationResult
    let scale: ScaleCalibrationResult
    let deviceModel: String
    let timestamp: Date
}

/// 페이셜 스캔 결과 메시 (STL 변환 전 중간 표현)
struct ScanMesh {
    var vertices: [SIMD3<Float>]
    var triangleIndices: [Int32]
}
