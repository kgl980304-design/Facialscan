import SwiftUI

enum WorkflowStep {
    case home
    case calibration
    case faceScan
    case result
}

/// 워크플로우: 환자 내원 -> 앱 실행 -> 체커보드 교정 -> 페이셜 스캔 -> STL 추출
struct ContentView: View {
    @State private var step: WorkflowStep = .home
    @State private var calibrationProfile: CalibrationProfile? = CalibrationStore.load()
    @State private var rawSTLURL: URL?
    @State private var correctedSTLURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .home:
                    HomeView(
                        hasSavedCalibration: calibrationProfile != nil,
                        onStartCalibration: { step = .calibration },
                        onSkipToScan: { step = .faceScan }
                    )
                case .calibration:
                    CalibrationView(onFinished: { profile in
                        calibrationProfile = profile
                        step = .faceScan
                    })
                case .faceScan:
                    FaceScanView(
                        calibrationProfile: calibrationProfile,
                        onFinished: { rawURL, correctedURL in
                            rawSTLURL = rawURL
                            correctedSTLURL = correctedURL
                            step = .result
                        }
                    )
                case .result:
                    ResultView(
                        rawSTLURL: rawSTLURL,
                        correctedSTLURL: correctedSTLURL,
                        onRestart: { step = .home }
                    )
                }
            }
            .navigationTitle(title(for: step))
        }
    }

    private func title(for step: WorkflowStep) -> String {
        switch step {
        case .home: return "환자 내원"
        case .calibration: return "체커보드 교정"
        case .faceScan: return "페이셜 스캔"
        case .result: return "결과 (STL 비교)"
        }
    }
}
