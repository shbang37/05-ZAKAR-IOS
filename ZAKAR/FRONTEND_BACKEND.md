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

### 3.1 인증/사용자 관리 (Firebase — 구현 완료, 패키지 추가 필요)
- 파일: `AuthService.swift`
- 대상: 교회 동역자 전용 폐쇄형 앱 (승인된 사용자만 사용 가능)
- Firebase Auth: 이메일/비밀번호
- Firestore `users/{uid}`: `status = pending | approved | rejected`
- AuthState: `loading → unauthenticated / pendingApproval / rejected / approved`
- 실시간 리스닝: 관리자 승인 즉시 앱 화면 전환 (`addSnapshotListener`)
- ZAKARAdmin(macOS): Firebase Identity Toolkit REST + Firestore REST API
- 설치: Xcode > File > Add Package Dependencies → `firebase-ios-sdk` (FirebaseAuth + FirebaseFirestore)
- `GoogleService-Info.plist` 이미 포함됨

### 3.2 Photos 프레임워크 (시스템 사진 라이브러리)
- 파일: `PhotoManager.swift`
- 역할:
  - 사진 로드: `fetchPhotos(year:month:force:)` → 권한 확인 → 백그라운드 fetch
  - 유사 사진 분석: 전체 async 파이프라인 (withCheckedContinuation + withTaskGroup)
    - 7초 시간 그룹화 → pHash(DCT 32×32) + Hamming Distance(≤18) 시각 유사도 필터
  - 삭제/즐겨찾기/앨범 추가 등 Photos API 조작
- 주의: `isSynchronous=true` + Swift concurrency 교착 → `withCheckedContinuation` 사용
- 삭제 후 목록 갱신: 반드시 `fetchPhotos(force: true)`

### 3.3 LocalDB (앱 내부 JSON 저장)
- 파일: `LocalDB.swift`
- 저장 위치: Application Support/ZAKAR/
- `metadata.json`: 온보딩 완료, 최근 정리, 절감 추정, 아카이브 설정
- `trash.json`: PHAsset.localIdentifier 배열 (앱 재시작 후 복원)

### 3.4 파일 저장소 (구현 현황 및 계획)
| 유형 | 저장소 | 상태 |
|---|---|---|
| 문서·사진 공유 아카이브 | Firebase Cloud Storage | 계획 중 |
| 영상(대용량) | Synology NAS (WebDAV) | NASMockService 구현됨, 실연결 대기 |
| 개인 백업 | Google Drive | 구현 완료 (`GoogleDriveService.swift`) |

- 추상화: `ZKDriveSyncing` 프로토콜로 저장소 교체 가능
- Firebase Cloud Storage 보안 규칙: `status == “approved”` 사용자만 읽기/쓰기 가능

### 3.5 Google Drive (개인 백업)
- 파일: `GoogleDriveService.swift`
- OAuth2 PKCE + ASWebAuthenticationSession
- 멀티파트 업로드, 키체인 토큰 저장
- 설정: `clientID`, `redirectScheme` 실값 교체 + URL Types 등록

---

## 4. 데이터 흐름 (상세)

1) 앱 시작(ZAKARApp)
- AuthService.checkCurrentSession() → 상태 확인
- approved: PhotoManager 주입 → fetchPhotos() → 지연 분석 예약
- pendingApproval: 승인 대기 화면 + 실시간 리스닝 (관리자 승인 시 즉시 전환)
- unauthenticated: 로그인 화면

2) 홈(HomeView)
- NavigationStack 최상위, .onAppear은 내부 ZStack에 배치
- “유사 사진” 카드 탭 → ContentView(initialTab: 0) NavigationLink

3) ContentView
- onAppear → selectedTab 재설정 + analyzeSimilaritiesIfNeeded()
- TrashView onDeleteSuccess → fetchPhotos(force: true)

4) 정리/공유/앨범
- CleanUpView 제스처 → 휴지통/즐겨찾기/이동
- NotificationCenter(“OpenTrash”) → TrashView sheet
- TrashView 삭제 → deleteAssets → fetchPhotos(force: true) + loadTrash()
- LocalDB trash.json 영속

5) 파일 업로드 (선택)
- ArchiveView: NASMockService → 실 NAS WebDAV로 교체 예정
- DriveSettingsView: Google Drive 연결/수동 동기화

---

## 5. 에러/보안/성능

- 권한: 거부 시 로딩 중지, 온보딩 가이드 제공
- pHash 성능: 32×32 그레이스케일 DCT, NSLock 캐시 보호, withTaskGroup 병렬화
- PHAsset 비교: 항상 `localIdentifier` 문자열 사용 (포인터 동일성 금지)
- Firebase 보안: Firestore Rules + Cloud Storage Rules로 approved 사용자만 접근
- 토큰: 키체인 저장, 만료 시 자동 갱신

---

## 6. 설정/운영 가이드

- Firebase 패키지 추가: Xcode > File > Add Package Dependencies
  → `https://github.com/firebase/firebase-ios-sdk` (FirebaseAuth + FirebaseFirestore)
- Info.plist: `Privacy - Photo Library Usage Description` 확인
- Google Drive 연동:
  - Google Cloud Console iOS OAuth 클라이언트 생성
  - `clientID`, `redirectScheme` 교체
  - URL Types에 `redirectScheme` 등록

---

## 7. 향후 확장

- Firebase Cloud Storage 연동 (문서·사진 공유 아카이브, 승인 사용자 전용)
- Synology NAS WebDAV 실구현 (NASMockService 교체)
- 유사도 엄격도 UI (SimilarityPreset: light/balanced/strict)
- 멀티 선택/배치 작업 UX
- 임시보관함 자동 비우기 정책
- Push 알림 (FCM) — 승인 완료 알림 등

---

## 부록: 참고 파일 목록

- 프론트엔드
  - ZAKARApp.swift, MainTabView.swift, HomeView.swift, ContentView.swift
  - Components.swift, CleanUpView.swift, AlbumsView.swift, OnboardingView.swift
  - ArchiveView.swift, LoginView.swift, PendingApprovalView.swift

- 백엔드
  - PhotoManager.swift (Photos + 유사도 분석)
  - AuthService.swift (Firebase Auth + Firestore 승인)
  - LocalDB.swift (앱 내부 저장)
  - GoogleDriveService.swift (OAuth + 업로드)
  - DriveSyncService.swift (ZKDriveSyncing 프로토콜)

- Admin (macOS)
  - ZAKARAdmin/AdminAuthService.swift
  - ZAKARAdmin/AdminUserListView.swift
  - ZAKARAdmin/AdminUserDetailView.swift
