# ZAKAR 프론트엔드/백엔드 구성 문서

본 문서는 ZAKAR iOS 앱의 프론트엔드(화면/UI/상태)와 백엔드(데이터 소스/저장/외부 연동) 구조를 한 눈에 이해할 수 있도록 정리한 문서입니다.

- 대상 독자: 개발자/운영자/실무 사용자를 위한 기술 개요
- 플랫폼: iOS (SwiftUI + Photos + Local 저장 + 선택적 Google Drive/Synology NAS 연동)

---

## 1. 전체 개요

ZAKAR는 별도의 자체 서버(전용 백엔드) 없이, 기기 내 사진 라이브러리(Photos 프레임워크), 로컬 저장(LocalDB), 선택적 클라우드 연동(Google Drive API)을 조합해 동작합니다.

- 오프라인 친화: 대부분의 기능이 기기 내에서 동작
- 개인정보 중심: 사진 데이터는 Photos 라이브러리에서 직접 로드/분석
- 선택적 백업: Google Drive에 업로드(연동 시)

데이터 흐름(요약):
1) 앱 시작 → PhotoManager가 사진 로드(fetchPhotos)
2) 홈 → 유사 사진/모든 사진 화면으로 이동
3) 유사 사진 탭에서 분석 수행 → 그룹 목록 표시
4) 정리(제스처), 임시보관함 관리(영속), 앨범 추가/공유
5) (선택) 드라이브 동기화/업로드

---

## 2. 프론트엔드(Frontend)

### 2.1 기술 스택
- SwiftUI (iOS 16+에서 NavigationStack 사용)
- ObservableObject/State/Binding로 상태 관리
- 접근성(VoiceOver 라벨, 큰 터치 타깃) 및 다크 테마 고려

### 2.2 주요 화면/컴포넌트

- ZAKARApp.swift
  - 앱 엔트리 포인트
  - `@StateObject var photoManager = PhotoManager()` 생성 및 `.environmentObject(photoManager)` 주입
  - 초기 로드: `photoManager.fetchPhotos()` → 지연 분석 트리거

- MainTabView.swift
  - 홈(HomeView) / 앨범(AlbumsView) / 업로드(DriveSettingsView) 탭 구성
  - 첫 실행 온보딩: `OnboardingView`를 `fullScreenCover`로 표시

- HomeView.swift
  - 헤더: 로고/앱 타이틀/서브타이틀
  - 요약 카드: `HomeSummaryCard`(정리 대상 그룹 수, 최근 정리, 절감 추정)
  - 주요 네비게이션: “모든 사진” / “유사 사진” 카드
  - 안정화 포인트:
    - `NavigationStack` 사용
    - 유사 사진 링크는 `.id(UUID())`로 항상 새 `ContentView(initialTab: 0)` 생성 → 상태 초기화 보장
    - 카드 전체 탭 히트 영역: `.contentShape(Rectangle())`

- ContentView.swift
  - 상단 세그먼트: “모든 사진”(그리드) / “유사 사진”(그룹)
  - 생성자 파라미터 `initialTab`을 별도로 저장(`initialTabParam`) 후 `onAppear`에서 `selectedTab` 재설정 → 재진입 시 안정
  - 유사 탭(0) 진입 시 `photoManager.analyzeSimilaritiesIfNeeded()` 보장
  - 튜토리얼 1회 표시(UserDefaults)
  - 임시보관함(휴지통)과 바인딩 연결 + LocalDB 영속화 연동

- CleanUpView.swift
  - 제스처 기반 선별 UX: 위(삭제 후보), 아래(즐겨찾기), 좌/우(이동)
  - 상단 헤더: 현재 인덱스/날짜, 즐겨찾기, 공유, 휴지통 버튼
  - 하단: 앨범 추가/최근 앨범 퀵 액션
  - 휴지통 버튼 숫자 줄바꿈 방지(줄 수 축소/자간 조정 + 고정 폭 제거)

- Components.swift
  - 재사용 컴포넌트: `SimilarityGroupRow`, `TrashBucketButton`, `AssetThumbnail`, `TrashView`
  - `TrashBucketButton`은 숫자 증가 시에도 한 줄 유지하도록 조정

- OnboardingView.swift
  - 앱 소개/핵심 기능, 사진 권한 요청, 튜토리얼 보기
  - 접근성 라벨/큰 터치 타깃 고려

### 2.3 네비게이션/상태 안정화 전략
- NavigationStack 도입으로 푸시/팝 안정성 향상
- 유사 사진 링크에 `.id(UUID())` 사용 → 항상 새 ContentView 생성
- ContentView가 `initialTabParam`을 `onAppear`에서 다시 반영
- PhotoManager의 지연 분석 큐(`shouldAnalyzeAfterLoad`)로 로딩 타이밍 경합 해소

### 2.4 접근성/테마
- 다크 테마 대비에 맞춘 카드/테두리/그림자
- 로고는 원형 클리핑 + 은은한 스트로크, 템플릿 렌더링 방지
- VoiceOver 라벨 제공

---

## 3. 백엔드(Backend)

ZAKAR는 자체 서버 없이 다음 3요소로 백엔드를 구성합니다.

### 3.1 Photos 프레임워크 (시스템 사진 라이브러리)
- 파일: `PhotoManager.swift`
- 역할:
  - 사진 로드: `fetchPhotos(year:month:)` → 권한 확인 → 백그라운드 fetch → 메인 반영
  - 유사 사진 분석: `analyzeSimilaritiesIfNeeded()` → `analyzeGroups(assets:)`
    - 시간 인접 그룹화(촬영 시각 근접)
    - pHash + Hamming Distance로 시각적 유사도 필터링
  - 사진 삭제/즐겨찾기/앨범 추가 등 Photos API 조작
- 안정화:
  - `shouldAnalyzeAfterLoad` 플래그로 로드 완료 후 자동 분석 보장
  - `isLoadingList`/`isAnalyzing`/`didAnalyzeForCurrentList`로 UI 상태 일관성 유지

### 3.2 LocalDB (앱 내부 JSON 저장)
- 파일: `LocalDB.swift`
- 저장 위치: Application Support/ZAKAR/
- 저장 항목:
  - `metadata.json` → `AppMetadata`(온보딩 완료, 최근 정리, 절감 추정, 아카이브 설정)
  - `trash.json` → 임시보관함의 `PHAsset.localIdentifier` 배열(앱 재시작 후 복원)
- 제공 메서드:
  - `isOnboardingCompleted()` / `setOnboardingCompleted(_:)`
  - `loadTrashIdentifiers()` / `saveTrashIdentifiers(_:)`

### 3.3 Google Drive / Synology NAS 연동 (선택)
- 파일: `GoogleDriveService.swift`
- 기능:
  - OAuth2(PKCE) 로그인(ASWebAuthenticationSession)
  - 폴더 경로 보장(없으면 생성) 및 멀티파트 업로드
  - 키체인 저장: 액세스/리프레시 토큰, 만료 시각
- 설정 필요:
  - `clientID`, `redirectScheme` 실제 값으로 교체
  - URL Types에 redirectScheme 등록
- 주의:
  - iOS 26의 UIWindow 생성 API 변경에 대응 (가능 시 `UIWindow(windowScene:)`)

---

## 4. 데이터 흐름 (상세)

1) 앱 시작(ZAKARApp)
- PhotoManager 주입 → `fetchPhotos()` 호출 → 필요 시 지연 분석 예약

2) 홈(HomeView)
- 요약 카드 표시(그룹 수/최근 정리/절감 추정)
- “유사 사진” 카드 탭 → `ContentView(initialTab: 0)`로 이동

3) ContentView
- `onAppear`에서 `selectedTab` 재설정
- 유사 탭이면 `analyzeSimilaritiesIfNeeded()` 호출
- 사진 로드 미완료 시 → 지연 분석 큐로 예약 → 로드 완료 시 자동 분석

4) 정리/공유/앨범
- CleanUpView에서 제스처로 선별 → 임시보관함/즐겨찾기/이동
- TrashView에서 선택/전체 복구/삭제
- LocalDB로 임시보관함 상태 영속

5) (선택) 드라이브 업로드
- DriveSettingsView에서 연결/해제/수동 동기화
- 업로드 시 파일명 규칙 적용(앨범명_날짜_원래이름.확장자)

---

## 5. 에러/보안/성능

- 권한 이슈: 권한 거부 시 로딩 중지 및 온보딩/가이드 제공
- 네트워크: Drive API 실패 시 에러 로깅(추후 사용자 알림 강화 가능)
- 메모리/성능: pHash 계산은 축소 이미지/그레이스케일 + DCT 사용, 캐시(`hashCache`)로 중복 계산 최소화
- 보안: 키체인에 토큰/만료 시각 저장, 만료 시 자동 갱신

---

## 6. 설정/운영 가이드

- 첫 실행 온보딩이 보이지 않으면 앱 삭제 후 재설치
- Info.plist에 사진 권한 설명(Privacy - Photo Library Usage Description) 확인
- Google Drive 연동 시:
  - Google Cloud Console에서 iOS OAuth 클라이언트 생성
  - `clientID`, `redirectScheme` 교체
  - URL Types에 `redirectScheme` 등록 (예: com.googleusercontent.apps.XXXX)

---

## 7. 향후 확장

- 유사도 엄격도 UI 제공(SimilarityPreset: light/balanced/strict)
- 멀티 선택/배치 작업(그리드에서 일괄 삭제/이동/공유)
- 임시보관함 자동 비우기(예: 7일)
- Drive 정책/계정 가시화(연결 계정, 자동/수동, Wi-Fi 전용)
- iCloud Drive 옵션 추가
- 홈 요약 카드 실데이터 업데이트(최근 정리/절감 추정 자동 갱신)

---

## 부록: 참고 파일 목록

- 프론트엔드
  - ZAKARApp.swift, MainTabView.swift, HomeView.swift, ContentView.swift
  - Components.swift, CleanUpView.swift, AlbumsView.swift, OnboardingView.swift
  - SummaryWidgets.swift(HomeSummaryCard)

- 백엔드
  - PhotoManager.swift (Photos + 유사도 분석)
  - LocalDB.swift (앱 내부 저장)
  - GoogleDriveService.swift (OAuth + 업로드)

필요 시, 시퀀스 다이어그램/플로우 차트 형태의 추가 문서도 제공할 수 있습니다.
