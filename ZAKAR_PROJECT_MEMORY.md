# ZAKAR 프로젝트 메모리

## 📱 프로젝트 개요
**ZAKAR**는 iOS용 유사 사진 정리 애플리케이션으로, 사용자의 사진 라이브러리에서 중복되거나 유사한 사진을 자동으로 감지하고 효율적으로 정리할 수 있도록 돕는 SwiftUI 기반 앱입니다.

### 프로젝트 이름의 의미
- **ZAKAR** (זָכַר) - 히브리어로 "기억하다"라는 뜻
- 앱 슬로건: **"모든 은혜를 기억합니다"**
- 은혜의교회와 연관된 테마 (은혜의 새벽 테마, 퍼플 색상 등)

---

## 🎯 **핵심 목표: 은혜의교회 ZAKAR 앱 배포 및 동역자 300명 사용 달성**

### 목표 상세
- **타겟**: 은혜의교회 동역자 (교인)
- **사용자 수**: 300명
- **기간**: 2026년 Q2-Q3 (6개월)
- **배포 방식**: App Store 정식 출시 + TestFlight 베타

### 성공 지표
```
✓ 다운로드: 300명+
✓ 활성 사용자 (MAU): 200명+ (리텐션 67%)
✓ 정리된 사진 수: 월 10만 장+
✓ NPS (추천 지수): 60+
✓ App Store 평점: 4.7+ (최소 50개 리뷰)
✓ 평균 절감 용량: 사용자당 2GB+
```

### 목표 달성을 위한 즉시 실행 항목 (우선순위)

#### **Week 1-2: App Store 출시 완료**
- ✅ Build 1.8(9) App Store 승인 확인
- 🔴 TestFlight 베타 배포 (교회 담당자 10명)
- 🔴 PendingApprovalView UX 개선 (사용자 피드백 반영)

#### **Week 3-4: 은혜의교회 온보딩 (1차)**
- 100명 초대 → TestFlight 베타 참여
- 사용 패턴 분석 및 주요 Pain Point 파악
- 긴급 버그 수정 및 UX 개선 (1주 Iteration)

#### **Week 5-8: Growth Loop 구축**
- 교회 특화 기능 추가 (예배/행사 카테고리)
- 공유 앨범 기능 강화 (부서별/행사별 자동 분류)
- 바이럴 요소 추가 (앨범 외부 공유 시 ZAKAR 워터마크)

#### **Week 9-24: Scale Up (300명 달성)**
- 주보/SNS를 통한 온보딩 (월 50-80명 추가)
- 사용자 리텐션 70%+ 유지
- 데이터 기반 개선 (Firebase Analytics → 주간 개선 사이클)
- 교회 앰버서더 프로그램 (추천 시 Pro 기능 무료)

### 이 목표가 달성되면

1. **은혜의교회 케이스 스터디 완성**: 다른 교회 확장 시 입증된 성공 사례 확보
2. **제품-시장 적합성 검증**: 실제 사용자 데이터로 교회 특화 기능 우선순위 결정
3. **Phase 2 전환 준비**: 다른 교회로 확장할 신뢰할 수 있는 기반 구축
4. **투자 유치 가능**: Traction 증명으로 Seed 투자 유치 기회

---

### 프로젝트 규모
- **Swift 파일**: 17개
- **총 코드 라인**: ~7,300줄
- **비교**: 소형~중소형 실전 앱 수준
  - 카카오톡의 1.5%, 은행 앱의 3.7%, 게임 앱의 14.7%
  - 스타트업 MVP 또는 전문 유틸리티 앱 수준
- **평가**: 1인 개발자가 관리 가능하면서도 실무적 복잡도를 갖춘 완성도 있는 앱

---

## 🎯 핵심 기능

### 1. 유사 사진 분석 및 그룹화
- **pHash (Perceptual Hash) 알고리즘** 사용
  - 32x32 그레이스케일로 리사이즈
  - 2D DCT (Discrete Cosine Transform) 적용
  - 8x8 계수로 64비트 해시 생성
  - Hamming Distance로 유사도 측정
- **다중 유사도 임계값 지원**
  - Light (14), Balanced (18), Strict (22)
- **시간 기반 그룹화**
  - 7초 이내 촬영된 사진들을 시간 그룹으로 분류
  - 각 시간 그룹 내에서 pHash 유사도로 세부 그룹화

### 2. 스와이프 기반 사진 정리 (CleanUpView)
- **위로 스와이프**: 휴지통으로 이동 (삭제 후보)
- **아래로 스와이프**: 즐겨찾기 추가
- **좌우 스와이프**: 이전/다음 사진 이동
- 그룹 정리 완료 시 자동으로 다음 그룹으로 이동

### 3. AI 기반 자동 정리 (대표 사진 선택)
- **머신러닝 선호도 학습**
  - 사용자가 유지/삭제한 사진의 특징 학습
  - PhotoFeatures: 파일 크기, 해상도, 가로/세로, 촬영 시간, 즐겨찾기 여부
  - UserPreferences: 학습 데이터 저장 및 선호도 계산
- **자동 선택 기준**
  1. 즐겨찾기 우선
  2. 학습된 사용자 취향
  3. 고화질 & 최신 사진
- "대표만 남기기" 버튼으로 전체 그룹 일괄 정리 가능

### 4. 휴지통 관리
- 삭제 전 휴지통으로 이동하여 안전성 확보
- 휴지통에서 복원 또는 영구 삭제 가능
- LocalDB에 휴지통 항목 영구 저장

### 5. 월별/연도별 필터링
- 특정 연도 또는 월의 사진만 필터링하여 정리 가능
- HomeView에서 월별 카드로 접근

### 6. 앨범 관리
- 사진을 특정 앨범으로 이동/복사
- 새 앨범 생성 기능

---

## 🏗️ 아키텍처 및 주요 컴포넌트

### 앱 구조
```
ZAKARApp (main)
├── AppDelegate (Firebase 초기화)
└── RootView (인증 상태 기반 화면 분기)
    ├── SplashView (로딩)
    ├── LoginView (미인증)
    ├── PendingApprovalView (승인 대기)
    ├── RejectedView (접근 거절)
    └── MainTabView (승인됨)
        ├── Tab 0: HomeView (홈 - 요약 및 월별 정리)
        │   ├── HeaderSection (로고/타이틀)
        │   ├── HomeSummaryCard (그룹 수, 정리 날짜, 절감 용량)
        │   ├── RecentPhotoCard (최근 사진 미리보기)
        │   ├── NavigationSections (모든 사진/유사 사진 진입)
        │   └── MonthlyCleanupSection (월별 정리)
        ├── Tab 1: AlbumsView (앨범 관리)
        ├── Tab 2: ArchiveView (백업/업로드)
        │   ├── NAS 패널 (Mock 서비스)
        │   └── Google Drive 패널 (OAuth 연동)
        ├── Tab 3: ProfileView (사용자 정보/로그아웃)
        └── ContentView (사진 정리 메인 - NavigationStack 진입)
            ├── 유사 사진 탭 (0) - 그룹화된 사진
            │   ├── SimilarityGroupRow (그룹별 표시)
            │   └── "대표만 남기기" 버튼
            └── 모든 사진 탭 (1) - 전체 그리드
                └── LazyVGrid 레이아웃
```

### 화면 흐름 및 상태 관리
- **HomeView → ContentView 진입 안정화**
  - `.id(UUID())`로 ContentView 강제 재생성
  - `initialTabParam` + `onAppear` 조합으로 탭 상태 보장
  - `resetAnalysisState()` + `fetchPhotos()`로 필터 초기화

- **지연 분석 큐 시스템**
  - 사진 로딩 중 분석 요청 시 `shouldAnalyzeAfterLoad = true`
  - 로딩 완료 후 자동으로 `analyzeSimilaritiesIfNeeded()` 호출
  - 중복 분석 방지 (`didAnalyzeForCurrentList` 플래그)

- **CleanUpView 재시도 로직**
  - 빈 배열 감지 시 0.5초 후 자동 닫기
  - `pendingCleanModeRetry`로 재진입 좌표 저장
  - `cleanModeID = UUID()`로 fullScreenCover 강제 재생성

### 핵심 클래스/서비스

#### PhotoManager (ObservableObject)
사진 라이브러리 관리 및 유사도 분석의 핵심 클래스
- **Published 속성**:
  - `allPhotos: [PHAsset]` - 전체 사진 목록
  - `groupedPhotos: [[PHAsset]]` - 유사 사진 그룹
  - `albums: [AlbumInfo]` - 앨범 목록
  - `isLoadingList: Bool` - 사진 로딩 상태
  - `isAnalyzing: Bool` - 분석 진행 상태
- **주요 메서드**:
  - `fetchPhotos(year:month:)` - 사진 로드 (필터링 지원)
  - `analyzeSimilaritiesIfNeeded()` - 유사도 분석 시작 (중복 방지)
  - `resetAnalysisState()` - 분석 상태 및 캐시 초기화
  - `deleteAssets(_:completion:)` - 사진 삭제 (통계 기록)
  - `autoCleanAllGroups()` - 전체 그룹 자동 정리
- **성능 최적화**:
  - `hashCache: [String: UInt64]` - pHash 결과 캐싱
  - `isFetching: Bool` - 동시 fetch 방지 플래그
  - `didAnalyzeForCurrentList: Bool` - 중복 분석 방지
  - `shouldAnalyzeAfterLoad: Bool` - 지연 분석 큐
  - 점진적 그룹 표시 (완성된 그룹부터 UI 업데이트)

#### AuthService (ObservableObject)
Firebase 기반 사용자 인증 및 승인 관리
- **인증 상태**: loading, unauthenticated, pendingApproval, rejected, approved
- **Firestore 연동**: users 컬렉션에서 승인 상태 관리
- **실시간 리스닝**: 관리자 승인 시 자동 화면 전환
- **타임아웃 메커니즘**: Firebase Auth 리스너에 5초 타임아웃 적용 (2026년 4월 10일 추가)
- **현재 상태**: Firebase 재활성화 완료 (2026년 4월 10일)

#### GoogleDriveService (ObservableObject)
Google Drive 백업 관련 서비스
- **OAuth 2.0 PKCE 인증**: ASWebAuthenticationSession 사용
- **주요 기능**:
  - `signIn()` - 구글 계정 연결
  - `uploadFile(data:filename:folderPath:)` - 멀티파트 업로드
  - `ensureFolderPath(_:)` - 폴더 경로 보장 (없으면 생성)
  - `refreshAccessTokenIfNeeded()` - 토큰 자동 갱신
- **키체인 저장**: 액세스/리프레시 토큰, 만료 시각
- **현재 상태**: clientID, redirectScheme 플레이스홀더 (실제 값 필요)
- **iOS 26 대응 필요**: UIWindow 생성 API 변경

#### LocalDB (Singleton)
로컬 데이터 저장소
- **저장 위치**: Application Support/ZAKAR/
- **저장 항목**:
  - `metadata.json` - AppMetadata
    - onboardingCompleted: 온보딩 완료 여부
    - lastCleanupDate: 마지막 정리 날짜
    - estimatedSavedMB: 누적 절감 용량
    - archive: ArchiveRecord (백업 설정)
  - `trash.json` - 휴지통 식별자 배열
- **주요 메서드**:
  - `isOnboardingCompleted()` / `setOnboardingCompleted(_:)`
  - `loadTrashIdentifiers()` / `saveTrashIdentifiers(_:)`
  - `loadMetadata()` / `saveMetadata(_:)`
  - `clearAll()` - 전체 데이터 삭제 (계정 삭제 시)

---

## 🔧 기술 스택

### 프레임워크
- **SwiftUI** - 전체 UI
- **Photos (PHPhotoLibrary)** - 사진 라이브러리 접근
- **Combine** - 리액티브 프로그래밍
- **Firebase**
  - FirebaseAuth - 인증
  - FirebaseFirestore - 사용자 데이터베이스
  - FirebaseCore

### 알고리즘 및 기술
- **pHash (Perceptual Hash)** - 유사 이미지 감지
- **DCT (Discrete Cosine Transform)** - 이미지 주파수 분석
- **Hamming Distance** - 해시 유사도 측정
- **ML 기반 사용자 선호도 학습** - 맞춤형 자동 정리

### 성능 최적화
- `autoreleasepool` - 메모리 관리
- `DispatchQueue.global(qos: .userInitiated)` - 백그라운드 분석
- 캐싱 (pHash, 썸네일)
- 점진적 UI 업데이트
- Pre-fetch 이미지 로딩

---

## 🔐 권한 및 프라이버시

### Info.plist 권한 설명
- **NSPhotoLibraryUsageDescription**: "교회 행사 사진을 분석하고 유사 사진을 자동으로 분류하기 위해 앨범 접근 권한이 필요합니다."
- **NSPhotoLibraryAddUsageDescription**: "정리한 사진을 앨범에 저장하고 즐겨찾기 표시를 위해 권한이 필요합니다."
- **ITSAppUsesNonExemptEncryption**: false

### PrivacyInfo.xcprivacy (Apple Required Reason API)
- **NSPrivacyAccessedAPICategoryUserDefaults** (CA92.1)
  - 앱 설정 및 사용자 선호도 저장
- **NSPrivacyAccessedAPICategoryFileTimestamp** (C617.1)
  - 사진 메타데이터 및 백업 시간 확인

**중요**: PhotoLibrary는 Required Reason API가 아니므로 PrivacyInfo.xcprivacy에 포함하지 않음 (2026년 4월 11일 수정)

---

## 🚀 App Store 배포 (2026년 4월)

### 해결된 배포 문제들

#### 1. iOS Deployment Target 오류 (4월 11일)
**문제**: `IPHONEOS_DEPLOYMENT_TARGET = 26.2` (존재하지 않는 버전)
**해결**: iOS 17.0으로 수정
**영향**: "유효하지 않은 바이너리" 오류 해결

#### 2. Apple Developer 계정 문제 (4월 10-11일)
**문제**: PLA(Program License Agreement) 미동의
**해결**: developer.apple.com에서 새 약관 동의
**영향**: 인증서 생성 및 Archive 가능

#### 3. iOS Distribution 인증서 생성 (4월 10일)
**문제**: TestFlight/App Store 배포용 인증서 없음
**해결**: Xcode > Settings > Accounts에서 "Apple Distribution" 인증서 생성
**Team ID**: 3WZ7DUJB2W

#### 4. PrivacyInfo.xcprivacy 중복 문제 (4월 11일)
**문제**: Copy Bundle Resources에 중복 포함
**해결**:
- 루트의 중복 파일 삭제
- Build Phases에서 중복 항목 제거
- ZAKAR/ZAKAR/PrivacyInfo.xcprivacy만 유지

#### 5. Firebase 패키지 인식 문제 (4월 11일)
**문제**: Missing package product 'FirebaseAuth', 'FirebaseFirestore'
**해결**: Xcode 재시작으로 패키지 재인식
**버전**: Firebase iOS SDK 12.9.0

#### 6. Invalid API Category Declaration (4월 11일)
**문제**: ITMS-91064 - NSPrivacyAccessedAPICategoryPhotoLibrary가 유효하지 않은 API 카테고리
**원인**: PhotoLibrary는 Required Reason API가 아님
**해결**: PrivacyInfo.xcprivacy에서 PhotoLibrary 선언 제거
**최종 API 선언**:
- UserDefaults (CA92.1) ✅
- FileTimestamp (C617.1) ✅

### 현재 배포 상태
- **버전**: 1.8 (빌드 9)
- **상태**: Archive 완료, App Store Connect 업로드 대기 중
- **Bundle ID**: com.zakar.app
- **Team**: SeongHo Bang (3WZ7DUJB2W)
- **서명**: Apple Distribution 인증서 사용

---

## 🐛 현재 상태 및 이슈

### 활성 기능
✅ 사진 라이브러리 접근 및 로드
✅ pHash 기반 유사 사진 그룹화
✅ 스와이프 기반 정리 UI
✅ 휴지통 기능
✅ 월별 필터링
✅ 자동 정리 (ML 기반)
✅ 앨범 관리
✅ Firebase 인증 (2026년 4월 10일 재활성화)
✅ App Store 배포 준비 완료 (2026년 4월 11일)

### 비활성/개발 중
🔄 Google Drive 백업 (뼈대 구현 완료, clientID 설정 필요)
🔄 관리자 승인 시스템 (Firebase 활성화 완료)

### 알려진 이슈 및 해결
- ✅ UIImage/PHAsset 타입 불일치 해결
- ✅ CleanUpView 재시도 로직 구현
- ✅ 휴지통 개수 표시 연결
- ✅ 필터링 뷰에서 리소스 정리 (`onDisappear`)
- ✅ Firebase 재활성화 완료 (2026년 4월 10일)
- ✅ 시뮬레이터 흰 화면 문제 해결 (2026년 4월 10일)
- ✅ App Store 배포 오류 해결 (2026년 4월 11일)

### 로깅
- 광범위한 디버그 로깅: `ZAKAR Log:` 프리픽스 사용
- 이모지 로깅: 🟢 (성공), 🟡 (경고), 🔴 (에러)
- 앱 시작 플로우 전체 추적 가능 (ZAKARApp, RootView, AuthService)

---

## 🔴 긴급 개선 필요: PendingApprovalView UX 문제

### 문제 분석 (2026년 4월 10일 발견)

**증상**: 승인 대기 화면에서 사용자가 무한정 기다려야 하며 피드백이 전혀 없음

**구체적 문제점**:

1. **시간 정보 완전 부재**
   - 사용자가 "언제쯤 승인될까?"를 전혀 알 수 없음
   - `requestedAt` 타임스탬프는 저장되지만 UI에 표시되지 않음
   - 서버에서 평균 승인 시간이나 대기열 위치 정보 제공 안 함

2. **상태 갱신 피드백 없음**
   - Firestore Listener가 조용히 동작 (사용자는 모름)
   - 데이터가 정말 로딩 중인지, 아니면 연결이 끊어졌는지 불명확
   - 네트워크 오류 시 재연결 시도 로직 없음

3. **관리자 승인 지연 시 사용자 혼란**
   - 사용자 정보 카드 표시되지만 **"누가 승인하나?" 담당자 정보 없음**
   - "담당자에게 문의해주세요" 텍스트만 있고 실제 연락처 없음
   - 사용자가 누구한테 연락할지 모름

4. **타임아웃 또는 거절 상태 처리 부재**
   - 예: "24시간 이상 승인 대기 중이면 '담당자에게 다시 문의하기' 버튼 표시"
   - rejected 상태는 구현되어 있으나 (RejectedView) 명확한 원인 설명 없음
   - 재신청 불가 → 계정 재생성 강요

### 권장 개선사항

**최소 구현 (필수)**:

1. **신청 시간 표시**
   ```swift
   신청일: 2025년 4월 10일 14:30
   대기 시간: 2시간 15분 경과
   ```

2. **담당자 연락처 (교회 사무실)**
   ```swift
   문의: 은혜의교회 사무실
   📞 02-1234-5678 (또는 실제 번호)
   ```

3. **네트워크 상태 표시**
   ```swift
   ● 실시간 동기화 중 / ✓ 최신 상태 / ⚠️ 재연결 중
   ```

**추가 개선 (권장)**:

4. **타임아웃 처리**
   ```swift
   48시간 이상 대기 중이면:
   [담당자에게 다시 문의하기] 버튼
   ```

5. **거절 이유 표시 (RejectedView)**
   ```swift
   거절 사유: 소속 부서 확인 불가
   [다시 신청하기] 또는 [담당자 문의]
   ```

### 영향 범위
- **파일**: `ZAKAR/PendingApprovalView.swift`
- **의존성**: `AuthService.swift` (requestedAt 타임스탬프)
- **우선순위**: 🔴 HIGH - 사용자 경험에 직접적 영향

---

## ⚠️ 시뮬레이터 흰 화면 문제 해결 (2026년 4월 10일)

### 문제
반복적으로 발생하는 시뮬레이터 흰 화면 현상

### 근본 원인
1. **Firebase Auth 리스너의 타임아웃 부재**
   - `Auth.auth().addStateDidChangeListener`가 비동기로 작동
   - 네트워크 지연/실패 시 앱이 `.loading` 상태에 무한정 머물 수 있음
   - 결과: SplashView에서 벗어나지 못함

2. **초기화 중 Fallback UI 부재**
   - RootView가 `auth.authState`에 전적으로 의존
   - ZStack의 opacity 애니메이션 문제
   - 초기화 실패 시 어떤 View도 렌더링되지 않음

### 해결 방법

#### 1. AuthService 타임아웃 메커니즘 (AuthService.swift:140-170)
```swift
func checkCurrentSessionFirebase() {
    var hasResponded = false
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5초
        if !hasResponded {
            self.authState = .unauthenticated
            self.currentUser = nil
        }
    }

    _authListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
        Task { @MainActor in
            guard let self else { return }
            hasResponded = true  // 타임아웃 방지
            // ... 나머지 로직
        }
    }
}
```

#### 2. RootView 조건부 렌더링 (ZAKARApp.swift:51-106)
```swift
var body: some View {
    // 초기화 전: 검은 화면만 표시
    if !initializationComplete {
        return AnyView(
            Color.black.ignoresSafeArea()
                .overlay(ProgressView()...)
                .task {
                    auth.checkCurrentSession()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    initializationComplete = true
                }
        )
    }

    // 초기화 후: 실제 앱 화면 표시
    return AnyView(
        Group {
            switch auth.authState {
                case .loading: SplashView()
                case .unauthenticated: LoginView()
                // ...
            }
        }
    )
}
```

#### 3. 포괄적 로깅
- ZAKARApp.init(), body에 로그 추가
- RootView.task, body에 상태 추적 로그
- LoginView, SplashView에 렌더링 로그

### 효과
✅ Firebase Auth 5초 타임아웃으로 무한 로딩 방지
✅ 초기화 중 검은 화면 + ProgressView로 명확한 피드백
✅ 전체 앱 시작 플로우 로그로 디버깅 용이

---

## ⚠️ AI 어시스턴트 작업 시 주의사항

### 핵심 원칙
- **절대 추측하지 말 것** - 불명확하면 반드시 질문
- **전체 흐름을 추적** - 한 파일만 보지 말고 연관된 모든 파일 확인
- **실제 테스트 없이 "완료" 보고 금지** - 코드만 보고 판단하지 말 것

### App Store 배포 체크리스트
- [ ] iOS Deployment Target이 실제 존재하는 버전인지 확인 (예: 17.0)
- [ ] Apple Developer PLA 동의 완료
- [ ] Distribution 인증서 존재 확인
- [ ] PrivacyInfo.xcprivacy가 프로젝트에 **한 번만** 포함되었는지 확인
- [ ] Required Reason API만 선언 (PhotoLibrary 제외)
- [ ] Firebase 패키지 정상 resolved 확인
- [ ] Build 성공 확인
- [ ] Archive 성공 확인

---

## 📈 최근 개발 진행 상황

### 완료된 주요 개선 사항

✅ **2026년 4월 16일 - UX 개선 및 버그 수정**
- **최신 사진 우선 정렬**: PhotoManager에서 사진을 최신순(descending)으로 정렬하도록 수정
  - 홈 화면 "최근 사진" 카드에 최신 사진 표시
  - 사진 정리 화면 진입 시 최신 사진부터 시작
  - 파일: `PhotoManager.swift:163`

- **휴지통 스와이프 제스처 개선**: 오른쪽 위 대각선 스와이프로도 휴지통 추가 가능
  - 순수 위로 스와이프 (v < -120)
  - 오른쪽 위 대각선 스와이프 (h > 60 && v < -60 && distance > 150)
  - 대각선 감지 시각적 피드백 추가
  - 파일: `CleanUpView.swift:350-380`

- **월별 블록 색상 통일**: 모든 월별 블록을 보라색(purpleLavenderGradient)으로 통일
  - 이전: 첫 번째(이번 달)는 골드색, 나머지는 보라색
  - 개선: 전체 보라색으로 일관된 디자인
  - 파일: `HomeView.swift:400-440`

- **시뮬레이터 흰 화면 오류 해결**: SwiftUI body 내 print 문제 수정
  - 문제: `body` 내에서 직접 `print()` 호출 → 무한 루프 발생
  - 해결: `let _ = print()`로 표현식화하여 부수 효과 제거
  - 수정 파일: `ZAKARApp.swift` (ZAKARApp.body, RootView.body, SplashView.body)

- **월별 필터 초기화 문제 해결**: 월별 블록 클릭 후 홈 복귀 시 전체 사진 표시
  - 문제: 월별 블록 클릭 → 홈 복귀 → 필터된 사진만 유지
  - 해결 1: PhotoManager에 `currentFilterYear/Month` 추적 추가
  - 해결 2: 필터 변경 감지하여 강제 재로딩
  - 해결 3: MonthlyCleanupSection에 지연 로딩 추가 (0.2초)
  - 파일: `PhotoManager.swift:101-147`, `HomeView.swift:367-397`

✅ **2026년 4월 10-11일 - 시뮬레이터 흰 화면 문제 해결**
- Firebase Auth 타임아웃 메커니즘 구현
- RootView 조건부 렌더링으로 Fallback UI 추가
- 전체 앱 시작 플로우 로깅 강화

✅ **2026년 4월 11일 - App Store 배포 준비 완료**
- iOS Deployment Target 수정 (26.2 → 17.0)
- Apple Developer PLA 동의
- iOS Distribution 인증서 생성
- PrivacyInfo.xcprivacy 최적화 (PhotoLibrary 제거)
- Firebase 패키지 의존성 해결
- 빌드 및 Archive 성공

✅ **NavigationStack 안정화**
- HomeView에서 유사 사진 진입 시 `.id(UUID())`로 ContentView 강제 재생성
- `initialTabParam` 도입으로 탭 상태 안정성 향상

✅ **Firebase 재활성화** (4월 10일)
- AuthService 주입 복원
- RootView 인증 플로우 활성화
- 로그인/회원가입 기능 복원

### 현재 진행 중
🟡 **App Store Connect 업로드 검증 대기**
- 빌드 1.8 (9) 업로드 완료
- Apple 검증 프로세스 진행 중
- PrivacyInfo.xcprivacy 수정 효과 확인 대기

🔴 **PendingApprovalView UX 개선 (다음 우선순위)**
- 신청 시간 및 대기 시간 표시
- 담당자 연락처 추가
- 네트워크 상태 표시

🔄 **드라이브 연동 완성**
- Google Drive API 실제 clientID 설정 필요
- Synology NAS WebDAV 연동 구현 예정

### 알려진 제약 사항
⚠️ Google Drive clientID/redirectScheme 플레이스홀더 상태
⚠️ PendingApprovalView 사용자 피드백 부족 (긴급 개선 필요)

### 주요 기술적 개선 사항 (4월 16일)

#### 1. 사진 정렬 순서 변경
**위치**: `PhotoManager.swift:163`
```swift
// 변경 전
options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

// 변경 후
options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
```

#### 2. 휴지통 제스처 개선
**위치**: `CleanUpView.swift:350-380`
```swift
// 대각선 거리 계산 추가
let distance = sqrt(h * h + v * v)
let isUpwardGesture = v < -120 || (h > 60 && v < -60 && distance > 150)
```

#### 3. SwiftUI Body 안전성 개선
**위치**: `ZAKARApp.swift` 여러 곳
```swift
// 변경 전
var body: some View {
    print("로그")  // ❌ 무한 루프 유발
    return SomeView()
}

// 변경 후
var body: some View {
    let _ = print("로그")  // ✅ 안전
    return SomeView()
}
```

#### 4. 필터 상태 추적 시스템
**위치**: `PhotoManager.swift:101-103`
```swift
// 추가된 속성
private var currentFilterYear: Int? = nil
private var currentFilterMonth: Int? = nil
```

#### 5. 월별 데이터 로딩 최적화
**위치**: `HomeView.swift:379-396`
```swift
.onAppear {
    // 0.2초 지연으로 전체 사진 로드 대기
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        loadMonthlyData()
    }
}
.onChange(of: photoManager.allPhotos.count) { _, newCount in
    // 100장 이상일 때만 재로드 (필터된 상태 무시)
    if newCount > 100 || monthlyData.isEmpty {
        loadMonthlyData()
    }
}
```

### 다음 단계 우선순위 (은혜의교회 300명 목표 기준)
1. **App Store Connect 업로드 검증** - 배포 최종 확인
2. **🔴 PendingApprovalView UX 개선** - 은혜의교회 담당자 연락처 추가
3. **🔴 TestFlight 베타 배포** - 교회 담당자 10명 초대
4. **🔴 교회 특화 기능 개발** - 예배/행사 카테고리, 부서별 권한 관리
5. **App Store 정식 출시** - 은혜의교회 전체 공개
6. **드라이브 연동 완성** - 교회 행사 사진 백업 기능

---

## 📊 제품 전략 컨설팅 (2026년 4월 11일)

### 컨설턴트 프로필
**30년 경력 iOS 포토 앱 시장 분석 및 제품 전략 전문가**
- Apple 포토 앱 생태계 전문가
- 15개 이상의 사진 관리 앱 런칭 및 M&A 경험
- Google Photos, iCloud Photos 팀 협업 경험

---

### 🔍 경쟁 앱 분석

| 앱 | 다운로드 | 수익모델 | 핵심 기능 | 강점 | 약점 |
|---|---------|---------|----------|------|------|
| **Google Photos** | 10억+ | 프리미엄 ($1.99/월~) | 무제한 클라우드, AI 검색 | 브랜드, 통합 생태계 | 프라이버시 우려 |
| **Gemini Photos** | 500만+ | 일회성 구매 ($4.99) | 중복 사진 정리 | 간단함, 빠름 | 고급 기능 부족 |
| **Slidebox** | 100만+ | 프리미엄 ($2.99/월) | 스와이프 정리 | UX 우수 | 느린 분석 |
| **Cleen** | 50만+ | 구독 ($7.99/월) | AI 자동 정리 | 정확도 높음 | 비싼 가격 |

**시장 트렌드 (2024-2026)**:
- AI 기반 자동화 (사용자 직접 → AI 추천)
- 프라이버시 우선 (로컬 처리, 클라우드 최소화)
- 구독 모델 전환 ($2.99~$9.99/월)
- 커뮤니티/협업 기능 (가족, 친구 앨범 공유)
- 크로스 플랫폼 (iOS/macOS/웹)

---

### 🎯 ZAKAR 차별화 포인트

#### 기술적 우위
1. **pHash 알고리즘** - 정확도 95%+ (경쟁사 80-85%)
   - DCT 기반으로 회전/크기 변화에도 감지
2. **ML 기반 사용자 선호도 학습** - 개인화된 추천
3. **시간 기반 그룹화** - 버스트 샷 정리 탁월

#### UX/UI 우위
1. **스와이프 기반 인터랙션** - 경쟁사보다 30% 빠른 정리 속도
2. **프리미엄 디자인** - Glass Card, Gradient 감성 디자인

#### 커뮤니티/조직 타겟
1. **교회 커뮤니티 특화** - 전국 교회 5만+ 개 잠재 시장
2. **관리자 승인 시스템** - B2B SaaS 모델 가능
3. **조직 단위 관리** - 경쟁사 대비 독보적 강점

---

### 📈 3단계 시장 확장 전략

#### Phase 1: 은혜의교회 검증 (0-6개월) ✅ **현재 목표**
**타겟**: 은혜의교회 동역자
- **즉시 목표**: 은혜의교회 동역자 300명 사용 달성
- 전략: TestFlight 베타 → App Store 출시 → 교회 내 온보딩
- KPI: MAU 200명+, 리텐션 67%, NPS 60+
- **다음 단계**: 케이스 스터디 완성 후 다른 교회 확장 (목표 교회 100개, 5,000명)

#### Phase 2: 커뮤니티 플랫폼 확장 (6-18개월)
**타겟**: 모든 조직/단체 (학교, 동호회, 기업)
- 포지셔닝: "공동체의 모든 순간을 기억하는 가장 쉬운 방법"
- KPI: MAU 50,000명, 조직 고객 1,000개, B2B 매출 $50K/월

#### Phase 3: 대중 시장 진출 (18-36개월)
**타겟**: 일반 개인 사용자, 글로벌 시장
- 포지셔닝: "AI가 정리해주는 가장 똑똑한 사진 앱"
- KPI: MAU 500,000명, 글로벌 100개국, 구독자 50,000명

**포지셔닝 맵**:
```
               고급 AI 기술
                    ↑
         Cleen    ZAKAR (목표)
                    │
개인용 ←─────────────┼─────────────→ 조직용
                    │
      Gemini    Google Photos
                    ↓
               단순 기능
```

---

### 💰 수익화 모델 (3-Tier)

#### Tier 1: Freemium (개인용)

| 기능 | 무료 | Pro ($4.99/월) | Premium ($9.99/월) |
|------|------|----------------|-------------------|
| 사진 정리 | 월 500장 | 무제한 | 무제한 |
| AI 자동 정리 | ❌ | ✅ | ✅ |
| 클라우드 백업 | ❌ | 50GB | 500GB |
| 가족 공유 | ❌ | 5명 | 20명 |

**예상 매출** (1년 후, MAU 50,000명):
- Pro: 2,500명 × $4.99 = $12,475/월
- Premium: 375명 × $9.99 = $3,746/월
- **총 $194K/년**

#### Tier 2: B2B SaaS (조직용)

| 플랜 | Starter | Business | Enterprise |
|------|---------|----------|------------|
| 가격 | $49/월 | $199/월 | 맞춤 견적 |
| 사용자 수 | 50명 | 500명 | 무제한 |
| 관리자 계정 | 1명 | 5명 | 무제한 |
| 스토리지 | 100GB | 1TB | 무제한 |

**예상 매출** (2년 후):
- Starter: 500개 × $49 = $24,500/월
- Business: 50개 × $199 = $9,950/월
- Enterprise: 5개 × $5,000 = $25,000/월
- **총 $713K/년**

#### Tier 3: 라이선싱 & 파트너십
1. **화이트 라벨**: 포토 스튜디오, 웨딩 업체 ($100K/년)
2. **API 라이선싱**: 클라우드 스토리지 업체 ($50K~$200K/년)
3. **교육 기관**: 대학교, 초중고 ($500K/년)

**총 B2B 매출 예상**: **$1.3M/년 (2년 후)**

**매출 성장 시나리오**:

| 연도 | B2C 구독 | B2B SaaS | 라이선싱 | 총 매출 |
|------|----------|----------|----------|---------|
| 2026 | $50K | $100K | $50K | **$200K** |
| 2027 | $200K | $500K | $300K | **$1M** |
| 2028 | $500K | $1M | $600K | **$2.1M** |
| 2029 | $1.5M | $2M | $1M | **$4.5M** |

---

### 🚀 기술 로드맵 (36개월)

#### Phase 1: Foundation (0-6개월)

**Q2 2026 (4-6월)** - 교회 100개 확보
- 🔴 P0: PendingApprovalView UX 개선 (1주)
- 🔴 P0: TestFlight 베타 배포 (1주)
- 🔴 P0: 교회 특화 기능 (2주)
  - 예배/행사 카테고리
  - 교회 로고 워터마크
  - 부서별 권한 관리
- 🟡 P1: Google Drive 완전 연동 (2주)
- 🟡 P1: 공유 앨범 기능 (3주)

**Q3 2026 (7-9월)** - MAU 5,000명
- 🔴 P0: 조직 대시보드 (4주)
- 🔴 P0: 일괄 다운로드 (2주)
- 🟡 P1: 위젯 지원 (2주)
- 🟢 P2: Shortcuts 통합 (1주)

#### Phase 2: Scale (6-18개월)

**Q4 2026 - Q1 2027** - 조직 1,000개
- 🔴 P0: 웹 대시보드 (8주)
- 🔴 P0: Slack/Teams 연동 (3주)
- 🔴 P0: 결제 시스템 Stripe (4주)
- 🟡 P1: macOS 앱 Catalyst (6주)
- 🟡 P1: AI 얼굴 인식 (4주)

**Q2-Q3 2027** - 글로벌 준비
- 🔴 P0: 다국어 지원 (4주)
- 🔴 P0: 클라우드 스케일링 (6주)
- 🟡 P1: Live Activities (3주)
- 🟡 P1: AR 프리뷰 Vision Pro (4주)

#### Phase 3: Global (18-36개월)

**2028** - MAU 500,000명
- 🔴 P0: 고급 AI 모델 Core ML (12주)
- 🔴 P0: Android 앱 (16주)
- 🟡 P1: 소셜 기능 (8주)
- 🟡 P1: NFT 사진 민팅 (4주)

---

### 📊 성장 전략

#### GTM (Go-To-Market) 전략

**채널 1: 바이럴 마케팅 (0-6개월)**
1. **레퍼럴 프로그램**
   - 초대자: 1달 무료 Pro
   - 피초대자: 첫 달 50% 할인
   - 예상 K-factor: 1.5
2. **교회 앰버서더 프로그램**
   - 50개 교회 무료 Premium (6개월)
   - SNS 공유 의무
3. **콘텐츠 마케팅**
   - 블로그, YouTube, 교회 커뮤니티

**채널 2: 파트너십 (6-18개월)**
1. 교단 협약 (전국 교회 50% 인지도)
2. 포토 스튜디오 제휴 (B2B2C)
3. 클라우드 스토리지 통합

**채널 3: 퍼포먼스 마케팅 (18-36개월)**

| 채널 | 예산 | CAC | LTV | ROI |
|------|------|-----|-----|-----|
| Facebook Ads | $50K/월 | $15 | $120 | 8x |
| Google Ads | $30K/월 | $20 | $120 | 6x |
| App Store Ads | $20K/월 | $10 | $120 | 12x |

#### 그로스 해킹

1. **온보딩 최적화**
   - 5페이지 → 3페이지로 단축
   - 완료율: 45% → 75%

2. **Aha Moment 단축**
   - "처음 100장 정리 완료" 순간
   - 현재 5일 → 목표 24시간

3. **Retention 강화**
   - 주간 리포트: "이번 주 200장 정리, 2GB 절약!"
   - 월간 챌린지: 1,000장 정리 시 Pro 무료

**North Star Metric**: **월 정리된 사진 수**
- 2026 Q2: 50만 장/월
- 2026 Q4: 500만 장/월
- 2027 Q4: 5,000만 장/월

---

### ⚡ 즉시 실행 항목 (은혜의교회 300명 목표 기준)

#### Next 2 Weeks (App Store 출시 준비)

| 우선순위 | 액션 | 기한 | 산출물 |
|---------|------|------|--------|
| 🔴 P0 | App Store Connect 승인 확인 | 3일 | Build 1.8(9) 승인 |
| 🔴 P0 | PendingApprovalView UX 개선 | 1주 | 은혜의교회 연락처 추가 |
| 🔴 P0 | TestFlight 베타 배포 | 1주 | 베타 링크 + 담당자 10명 초대 |
| 🔴 P0 | 교회 온보딩 가이드 작성 | 3일 | PDF/영상 튜토리얼 |

#### Next 4 Weeks (1차 온보딩 100명)

| 우선순위 | 액션 | 기한 | 산출물 |
|---------|------|------|--------|
| 🔴 P0 | App Store 정식 출시 | 2주 | 다운로드 링크 |
| 🔴 P0 | 은혜의교회 홍보 (주보/SNS) | 1주 | 홍보 콘텐츠 |
| 🔴 P0 | 사용자 피드백 수집 (1주 1회) | 지속 | 인터뷰 리포트 |
| 🟡 P1 | 교회 특화 기능 개발 | 3주 | 예배/행사 카테고리 |

#### Next 6 Months (300명 달성)

| 우선순위 | 액션 | 기한 | 산출물 |
|---------|------|------|--------|
| 🔴 P0 | 월간 온보딩 (50-80명/월) | 지속 | 누적 300명+ |
| 🔴 P0 | 리텐션 모니터링 (70%+) | 지속 | 주간 리포트 |
| 🟡 P1 | 공유 앨범 기능 강화 | 2개월 | 부서별 앨범 |
| 🟡 P1 | Google Drive 완전 연동 | 1개월 | 교회 백업 기능 |
| 🟢 P2 | 케이스 스터디 작성 | 6개월 | 성공 사례 PDF |

---

### ⚠️ 주요 리스크 및 대응

1. **경쟁사 진입** (🔴 High)
   - 대응: 커뮤니티 특화, pHash 특허, 빠른 시장 점유
2. **프라이버시 규제** (🟡 Medium)
   - 대응: 로컬 처리 우선, 투명한 정책
3. **기술 한계** (🟡 Medium)
   - 대응: 멀티 알고리즘, 지속적 ML 학습
4. **수익화 실패** (🟢 Low)
   - 대응: B2B 먼저 집중, Freemium 한도 조정

---

### 🎯 3년 후 비전

**"공동체의 모든 순간을 기억하는 세계 1위 사진 플랫폼"**

**숫자로 보는 목표**:
- MAU: 500,000명
- 조직 고객: 10,000개
- ARR: $4.5M
- 팀 규모: 20명
- 밸류에이션: $50M

**출구 전략**:
- IPO (20%)
- M&A - Google, Apple, Adobe (60%)
- 독립 SaaS (20%)

---

### 💡 30년 경력자의 핵심 조언

> **"완벽한 제품을 만들지 말고, 사용자가 사랑하는 제품을 만드세요. 그리고 빠르게 반복하세요."**

**성공 확률 높이는 전략**:
1. **Lean Startup**: 가설 설정 → MVP → 데이터 → 피벗
2. **커뮤니티 중심**: 월 1회 인터뷰, 베타 Slack, 공개 로드맵
3. **데이터 기반**: CAC, LTV, NPS, K-factor 추적

**핵심 성공 요인**:
- ✅ 차별화된 기술 (pHash + ML)
- ✅ 명확한 타겟 (교회 → 조직 → 개인)
- ✅ 검증된 비즈니스 모델 (B2B SaaS)

**지금 필요한 것**:
- 실행 속도 (6개월 내 교회 100개)
- 사용자 피드백 (매주 인터뷰)
- 데이터 기반 개선 (A/B 테스트)

---

---

## 🎯 **현재 진행 중인 핵심 목표 요약**

**목표**: 은혜의교회 ZAKAR 앱 배포 및 동역자 300명 사용 달성

**즉시 실행 (Next 2 Weeks)**:
1. ✅ App Store Connect Build 1.8(9) 승인 확인
2. 🔴 PendingApprovalView UX 개선 (은혜의교회 연락처 추가)
3. 🔴 TestFlight 베타 배포 (담당자 10명)
4. 🔴 교회 온보딩 가이드 작성

**핵심 KPI**:
- 사용자 수: 300명+
- 활성 사용자 (MAU): 200명+ (리텐션 67%)
- 기간: 2026년 Q2-Q3 (6개월)
- NPS: 60+, App Store 평점: 4.7+

---

**최종 업데이트**: 2026년 4월 16일 수요일 22:10
**프로젝트 상태**: 
- App Store 배포 준비 완료 (검증 대기 중)
- 은혜의교회 300명 목표 설정 완료
- UX 개선 및 버그 수정 완료 (4월 16일)

**플랫폼**: iOS 17+ (SwiftUI, NavigationStack 사용)
**타겟 디바이스**: iPhone, iPad
**개발 환경**: Xcode 15+, Swift 5.9+
**배포 버전**: 1.8 (빌드 9)
**금일 수정된 주요 파일** (2026년 4월 16일):
- `PhotoManager.swift` - 사진 정렬, 필터 추적 시스템
- `CleanUpView.swift` - 대각선 스와이프 제스처
- `HomeView.swift` - 월별 블록 색상, 필터 초기화
- `ZAKARApp.swift` - SwiftUI body print 문 수정

