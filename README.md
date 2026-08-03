# FacialScanCalib

아이폰 TrueDepth 카메라로 안면(Facial) 3D 스캔을 수행하고,
체커보드(Checkerboard) 카메라 교정을 통해 정확도를 보정한 뒤
STL 파일로 추출하는 iOS 앱입니다.

## 워크플로우
1. **환자 내원** → 앱 실행 (HomeView)
2. **체커보드 교정 실행** (CalibrationView)
   - TrueDepth 컬러+깊이 프레임을 동시에 캡처
   - OpenCV로 체커보드 코너 검출 (`findChessboardCorners` + `cornerSubPix`)
   - `calibrateCamera`로 카메라 내부 파라미터(초점거리 fx/fy, 주점 cx/cy, 왜곡계수) 산출
   - 검출된 코너의 깊이값을 이용해 실측 사각형 크기 vs 실제 크기(mm)를 비교 → **스케일 보정계수** 산출
3. **페이셜 스캔 실행** (FaceScanView)
   - ARKit `ARFaceTrackingConfiguration`으로 `ARFaceGeometry` 캡처
   - 위에서 구한 보정계수를 정점(vertex)에 적용
4. **STL 파일 추출** (ResultView)
   - 보정 전(raw) / 보정 후(corrected) STL을 각각 저장 → 실험 비교용

## 프로젝트 구성
```
FacialScanCalib/
├── project.yml                          # XcodeGen 스펙 (.xcodeproj를 코드로 생성)
├── Podfile                              # OpenCV2 의존성
├── Gemfile                              # fastlane, cocoapods
├── .github/workflows/
│   ├── ios-build.yml                    # 클라우드 macOS 빌드 + TestFlight 업로드 (매번 실행)
│   └── bootstrap-cert.yml               # Distribution 인증서 1회 생성용 (최초 1회만 실행)
├── fastlane/
│   ├── Appfile
│   └── Fastfile
└── FacialScanCalib/
    ├── App/
    │   ├── FacialScanCalibApp.swift
    │   └── ContentView.swift
    ├── Views/
    │   ├── HomeView.swift
    │   ├── CalibrationView.swift
    │   ├── FaceScanView.swift
    │   └── ResultView.swift
    ├── Core/
    │   ├── Models.swift
    │   ├── TrueDepthCaptureController.swift
    │   ├── CalibrationManager.swift
    │   ├── FaceScanController.swift
    │   ├── MeshCorrector.swift
    │   └── STLExporter.swift
    └── OpenCVBridge/
        ├── OpenCVWrapper.h
        ├── OpenCVWrapper.mm
        └── FacialScanCalib-Bridging-Header.h
```

---

## 🖥️ 맥북 없이 빌드하기 (GitHub Actions)

이 저장소는 GitHub의 클라우드 macOS 러너가 대신 빌드해서 TestFlight에 올려줍니다.
로컬에서 Xcode를 실행할 필요가 없습니다.

### 준비물 (전부 브라우저에서 가능)
1. **Apple Developer Program 가입** ($99/년) — developer.apple.com
2. **GitHub 계정** (무료)
3. **App Store Connect API 키 발급**
   - App Store Connect → Users and Access → Integrations → App Store Connect API
   - "+"로 키 생성 (Admin 권한) → `.p8` 파일 다운로드 (한 번만 다운로드 가능), Key ID / Issuer ID 기록
4. **App Store Connect에 앱 등록**
   - My Apps → "+" → 번들 ID `com.facialscancalib.app` 로 새 앱 생성
   (다른 번들 ID를 쓰고 싶으면 `project.yml`, `fastlane/Fastfile`, `fastlane/Appfile`에서 전부 동일하게 바꿔야 함)

### GitHub 저장소 설정
1. 이 폴더 전체를 새 GitHub 저장소로 push (GitHub Desktop 사용 시: 폴더 열기 → Publish repository)
2. 저장소 → Settings → Secrets and variables → Actions → **New repository secret**으로 아래 등록

   | Secret 이름 | 값 | 비고 |
   |---|---|---|
   | `TEAM_ID` | Apple Developer 계정의 Team ID | developer.apple.com → Membership |
   | `ASC_KEY_ID` | API 키의 Key ID | 파일명 `AuthKey_<이 값>.p8` |
   | `ASC_ISSUER_ID` | Issuer ID | Integrations 페이지 상단 |
   | `ASC_KEY_CONTENT` | `.p8` 파일 내용을 base64로 인코딩한 값 | 아래 "API 키 base64 만들기" 참고 |
   | `DIST_CERT_P12_BASE64` | (아래 3단계에서 생성) | 최초 1회 부트스트랩 후 등록 |
   | `DIST_CERT_PASSWORD` | (아래 3단계에서 생성) | 최초 1회 부트스트랩 후 등록 |

### API 키 base64 만들기 (PowerShell)
```powershell
$path = "C:\경로\AuthKey_XXXXXXXXXX.p8"
$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
$base64 | Out-File -Encoding ascii "asc_key_base64.txt" -NoNewline
Write-Host "길이: $($base64.Length)"
```
생성된 `asc_key_base64.txt` 내용 전체를 `ASC_KEY_CONTENT`에 붙여넣습니다.

### 최초 1회만: Distribution 인증서 부트스트랩

Apple은 계정당 Distribution 인증서 개수를 제한합니다. CI가 매번 새 인증서를
만들면 금방 한도를 초과하므로, **인증서를 딱 한 번만 만들어서 재사용**합니다.

1. Actions 탭 → **"Bootstrap Distribution Certificate (1회성)"** → Run workflow
   → `cert_password` 칸에 아무 비밀번호나 입력 (꼭 메모)
2. 실행 완료 후 결과 페이지 하단 **Artifacts**에서 `distribution-cert.zip` 다운로드 →
   압축 풀면 `distribution.p12`
3. PowerShell로 base64 변환:
   ```powershell
   $path = "다운로드한_distribution.p12_경로"
   $base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
   $base64 | Out-File -Encoding ascii "dist_cert_base64.txt" -NoNewline
   ```
4. Secret 등록:
   - `DIST_CERT_P12_BASE64` : 방금 만든 base64 값
   - `DIST_CERT_PASSWORD` : 1번에서 입력했던 그 비밀번호

이 작업은 **최초 1회만** 하면 되고, 이후 빌드는 이 인증서를 계속 재사용합니다.

### 본 빌드 실행
1. Actions 탭 → **"iOS Build & TestFlight"** → Run workflow
   (또는 main 브랜치에 push하면 자동 실행)
2. 5~15분 후 App Store Connect → TestFlight에 새 빌드 등장
3. 아이폰에서 **TestFlight 앱** 설치 → 초대 수락 → 앱 설치

### 참고
- ARKit TrueDepth 기능은 시뮬레이터에서 동작하지 않으므로, 반드시 **실제 iPhone**(X 이상, TrueDepth 카메라 탑재)에서 테스트해야 합니다.
- Debug 빌드는 Automatic 서명, Release(CI가 실제로 빌드하는 대상)는 Manual + Distribution 인증서로 서명하도록 분리되어 있습니다.
- 실패 시 Actions 로그(`build-logs` 아티팩트)를 확인하세요.

---

## (참고) 맥이 생기면 로컬에서 직접 빌드하는 방법

1. Homebrew로 XcodeGen 설치: `brew install xcodegen`
2. 프로젝트 루트에서 순서대로 실행:
   ```bash
   xcodegen generate
   pod install
   open FacialScanCalib.xcworkspace
   ```
3. Signing & Capabilities에서 본인 Apple ID/Team 선택 후 실기기(TrueDepth 탑재, iPhone X 이상)에서 Run

## 체커보드 준비물
- 내부 코너 기준 9x6 패턴 (가로 10칸 x 세로 7칸 사각형) 권장
- 정사각형 한 변 = 20mm (코드 내 `squareSizeMM` 값과 반드시 일치시킬 것)
- A4 용지에 인쇄 후 평평한 판(아크릴/폼보드)에 부착 권장 (휘어지면 오차 증가)

## 실험 방법 (보정 전후 STL 비교)
1. 캘리브레이션 없이(기본 ARKit 내부 파라미터만으로) 스캔 → `raw_scan.stl`
2. 체커보드 교정 실행 후 동일 환자/모형 스캔 → `corrected_scan.stl`
3. CloudCompare, MeshLab 등에서 두 STL을 기준 모델(예: 산업용 스캐너로 얻은 ground truth)과
   ICP 정합 후 RMS 오차 비교
4. `ResultView`에서 두 파일 모두 공유(Share Sheet)로 내보낼 수 있습니다.
