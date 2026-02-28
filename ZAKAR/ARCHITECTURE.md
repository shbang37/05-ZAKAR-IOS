// ZAKAR Architecture

본 문서는 ZAKAR iOS 앱의 아키텍처와 주요 모듈 간 책임/흐름을 설명합니다.

## 개요
- 패턴: SwiftUI + ObservableObject(ViewModel) + Photos 프레임워크
- 데이터: PHAsset(시스템 사진 라이브러리) + LocalDB(Application Support에 JSON 저장)
- 네비게이션: NavigationStack(홈), NavigationView 일부 화면(설정 등)

## 주요 모듈

### 1) PhotoManager (ObservableObject)
- 책임
  - 사진 로드(fetchPhotos)
  - 유사 사진 분석(analyzeSimilaritiesIfNeeded → analyzeGroups)
  - 임시 앨범/앨범 추가/삭제 등 Photos 조작
- 핵심 상태
  - `allPhotos: [PHAsset]` 로드된 사진 목록
  - `groupedPhotos: [[PHAsset]]` 유사 그룹 목록
  - `isLoadingList`, `isAnalyzing`: UI 상태 표시
  - `didAnalyzeForCurrentList`: 현재 목록에 대해 분석 중복 방지
  - `shouldAnalyzeAfterLoad`: 사진 로드 완료 후 분석 예약(지연 분석 큐)
- 흐름
  1. fetchPhotos → 권한 확인 → loadAssets(백그라운드) → 메인 스레드 반영
  2. analyzeSimilaritiesIfNeeded → allPhotos 비었으면 예약 → 로드 완료 시 자동 분석
  3. analyzeGroups → 시간 인접 그룹화 → pHash 유사도 필터링

### 2) ContentView
- 역할
  - 상단 세그먼트(모든 사진/유사 사진) 전환
  - 유사 사진 탭 진입 시 분석 트리거/프로그레스 표시
  - CleanUpView/TrashView 시트 전환 및 임시보관함 연동
- 안정화 포인트
  - `initialTabParam` 저장 후 `onAppear`에서 `selectedTab` 재설정
  - 유사 탭(0)일 때 `photoManager.analyzeSimilaritiesIfNeeded()` 보장
  - 튜토리얼 1회 표시(UserDefaults)
  - 임시보관함 식별자 영속화(LocalDB)

### 3) HomeView
- 역할
  - 홈 요약 카드 + 주요 네비게이션(모든 사진/유사 사진)
  - NavigationStack 사용
  - 유사 사진 링크는 `.id(UUID())`로 항상 새 ContentView 생성
  - 카드 전체를 탭 가능하도록 `.contentShape(Rectangle())`

### 4) LocalDB
- 책임
  - 메타데이터(AppMetadata): 온보딩 완료, 최근 정리, 절감(추정), 아카이브 설정
  - 임시보관함(trash.json): PHAsset.localIdentifier 배열 저장/복원
- 저장 위치
  - Application Support/ZAKAR/*.json

### 5) CleanUpView
- 역할
  - 제스처 기반 빠른 선별(위=삭제 후보, 아래=즐겨찾기, 좌/우=이동)
  - 휴지통 버튼 → ContentView에 Notification으로 열기 신호
  - 앨범 추가/공유 프리셋 기반 파일명 규칙

### 6) GoogleDriveService (베타)
- 책임
  - OAuth(PKCE) 인증 플로우
  - 폴더 생성/경로 보장, 업로드(멀티파트)
- 주의
  - clientID/redirectScheme를 실 값으로 교체 필요
  - iOS 26의 윈도우 생성 API 변경 대응

## 데이터 흐름
1. 앱 시작(ZAKARApp) → PhotoManager 주입 → fetchPhotos → analyzeSimilaritiesIfNeeded(지연 예약 포함)
2. 홈(HomeView) → 유사 사진 링크 → ContentView(initialTab: 0)
3. ContentView onAppear → selectedTab 재설정 + 분석 보장 → SimilarityGroupRow 렌더링
4. CleanUpView → 휴지통/앨범/공유 → TrashView → LocalDB에 trash.json 반영

## 오류/경고 대응(요약)
- `ASWebAuthenticationSession` 콜백 weak self 제거, 종료 시 nil 설정
- iOS 26 UIWindow 생성: 가능하면 `UIWindow(windowScene:)` 사용

## 확장 포인트
- 유사도 엄격도 UI 제공(SimilarityPreset)
- 멀티 선택/배치 작업 UX
- 임시보관함 자동 비우기 정책
- 드라이브 정책/계정 가시화 및 iCloud 옵션
