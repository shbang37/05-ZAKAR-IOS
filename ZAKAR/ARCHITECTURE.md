# ZAKAR Architecture

본 문서는 ZAKAR iOS 앱의 아키텍처와 주요 모듈 간 책임/흐름을 설명합니다.

## 개요
- 패턴: SwiftUI + ObservableObject + Photos 프레임워크
- 인증: Firebase Auth + Firestore (승인 기반 폐쇄형)
- 데이터: PHAsset + LocalDB(JSON) + Firebase Cloud Storage(예정) + Synology NAS(예정)
- 네비게이션: NavigationStack(홈 기준) — ContentView는 자체 NavigationView 없음

## 백엔드 구성

### 인증/사용자 관리 (Firebase)
- Firebase Auth: 이메일/비밀번호
- Firestore `users/{uid}`: `status = pending | approved | rejected`
- 회원가입 → pending → Admin 승인 → approved → 앱 사용 가능
- 실시간 리스닝: `addSnapshotListener`로 승인 즉시 화면 전환
- ZAKARAdmin(macOS): Firebase REST API (Identity Toolkit + Firestore REST)
- **설치 필요**: `firebase-ios-sdk` 패키지 (FirebaseAuth + FirebaseFirestore)

### 파일 저장소
| 유형 | 저장소 | 상태 |
|---|---|---|
| 문서·사진 | Firebase Cloud Storage | 예정 |
| 영상(대용량) | Synology NAS (WebDAV) | Mock 구현됨, WebDAV 교체 대기 |
| 개인 백업 | Google Drive | 구현 완료 |
| 로컬 임시 | LocalDB (JSON) | 구현 완료 |

파일 저장소는 `ZKDriveSyncing` 프로토콜로 추상화되어 교체 가능.

## 주요 모듈

### 1) PhotoManager (ObservableObject)
- 책임: 사진 로드, 유사 분석, 삭제, 휴지통 공유 상태
- 핵심 상태
  - `allPhotos: [PHAsset]`, `groupedPhotos: [[PHAsset]]`, `trashAssets: [PHAsset]`
  - `isLoadingList`, `isAnalyzing`, `didAnalyzeForCurrentList`, `shouldAnalyzeAfterLoad`
- fetchPhotos 규칙
  - `force: Bool = false` 파라미터 — 삭제/외부 변경 후엔 반드시 `force: true`
  - 동일 필터 + 사진 있음 + 로딩 중 아님 → 스킵 (force=true면 우회)
- pHash 분석 파이프라인 (전체 async)
  ```
  analyzeSimilaritiesIfNeeded()
    └─ Task { await analyzeGroupsProgressive(assets) }
         └─ 7초 시간 그룹 → await flushTimeGroupIfReady(&group)
              └─ await filterByVisualSimilarity(group)
                   └─ withTaskGroup (병렬 해시)
                        └─ await getOrGenerateHash(asset)
                             └─ withCheckedContinuation {
                                  PHImageManager.requestImage(32×32, fastFormat)
                                  콜백 → cont.resume(hash)
                                }
  ```
  - `isSynchronous=true` 사용 금지 (cooperative thread pool 교착 위험)
  - hash=0(로드 실패)은 캐시 저장 안 함
  - `hashCacheLock: NSLock`으로 캐시 보호
  - Hamming distance ≤ 18 → 유사 (balanced 기준)

### 2) AuthService (ObservableObject)
- Firebase Auth + Firestore 기반 인증/승인
- `AuthState`: `loading / unauthenticated / pendingApproval / rejected / approved`
- `#if canImport(FirebaseAuth)` 가드로 패키지 미추가 시에도 빌드 가능
- `listenForApprovalChangeFirebase`: Firestore snapshot으로 실시간 승인 감지

### 3) ContentView
- 상단 세그먼트(모든 사진/유사 사진) 전환
- 자체 NavigationView 없음 — 부모 NavigationStack 사용
- `initialTabParam` → `onAppear`에서 `selectedTab` 재설정
- TrashView `onDeleteSuccess` → `fetchPhotos(force: true)` 필수

### 4) HomeView
- NavigationStack 최상위
- `.onAppear`은 NavigationStack **내부** ZStack에 배치 (navigate-back 시 재실행 보장)
- NavigationLink 목적지에 `.id(UUID())` 사용 금지

### 5) LocalDB
- `trash.json`: PHAsset.localIdentifier 배열 (앱 재시작 후 복원)
- `metadata.json`: 온보딩, 최근 정리, 절감 추정
- 저장 위치: Application Support/ZAKAR/

### 6) Components
- `AssetThumbnail`: `requestID: PHImageRequestID` 저장 → `.onDisappear`에서 `cancelImageRequest`
- `TrashView`: `selectedIDs: Set<String>` (localIdentifier 기반), 버튼 액션 내부에서 targets 재계산
- PHAsset 비교는 항상 `asset.localIdentifier` 문자열로

### 7) CleanUpView
- DragIntent enum: 30pt 데드존 후 방향 확정
- 휴지통: `trashProgress(0→1)` 기반 2차 베지어 포물선
- `exportCurrentPhotoForSharing`: withCheckedContinuation으로 URL 반환 후 MainActor에서 @State 업데이트

### 8) GoogleDriveService
- OAuth2 PKCE + ASWebAuthenticationSession
- 멀티파트 업로드, 키체인 토큰 저장
- clientID/redirectScheme 실값 교체 필요

## 데이터 흐름

```
앱 시작(ZAKARApp)
  → AuthService.checkCurrentSession()
      → approved: PhotoManager 주입 → fetchPhotos → 분석 예약
      → pendingApproval: 승인 대기 화면 + 실시간 리스닝
      → unauthenticated: 로그인 화면

홈(HomeView)
  → NavigationLink → ContentView(initialTab)
      → 유사탭: analyzeSimilaritiesIfNeeded()
      → 모든사진탭: photoGrid

CleanUpView
  → 제스처 → 휴지통/즐겨찾기/이동
  → NotificationCenter("OpenTrash") → TrashView sheet

TrashView
  → deleteAssets → fetchPhotos(force: true) + loadTrash()
```

## 안전 규칙 요약
- PHAsset 비교: `localIdentifier` 문자열 (포인터 동일성 금지)
- TrashView 콜백: `onDeleteSuccess` → `fetchPhotos(force: true)`
- PHImageManager + Swift concurrency: `withCheckedContinuation` (isSynchronous=true 금지)
- ForEach 배열: `let snapshot = array; ForEach(Array(snapshot.enumerated()), id: \.offset)`
- @Published 쓰기: 반드시 MainActor 컨텍스트

## 확장 포인트
- Firebase Cloud Storage 연동 (문서·사진 공유 아카이브)
- Synology NAS WebDAV 실구현 (NASMockService → 실서비스 교체)
- 유사도 엄격도 UI (SimilarityPreset: light/balanced/strict)
- 멀티 선택/배치 작업 UX
- 임시보관함 자동 비우기 정책

