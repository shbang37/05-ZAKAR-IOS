# ZAKAR 프로젝트 설계도

> 신규 개발자를 위한 전체 프로젝트 구조 가이드

**최종 업데이트**: 2026년 3월 8일
**버전**: 1.2 (iOS App Store 제출 완료)
**플랫폼**: iOS 17.0+, macOS 14.0+ (Admin)

---

## 📋 목차

1. [프로젝트 개요](#1-프로젝트-개요)
2. [시스템 아키텍처](#2-시스템-아키텍처)
3. [프로젝트 구조](#3-프로젝트-구조)
4. [핵심 기능](#4-핵심-기능)
5. [데이터 흐름](#5-데이터-흐름)
6. [주요 모듈 상세](#6-주요-모듈-상세)
7. [Firebase 백엔드](#7-firebase-백엔드)
8. [개발 환경 설정](#8-개발-환경-설정)
9. [배포 가이드](#9-배포-가이드)
10. [트러블슈팅](#10-트러블슈팅)

---

## 1. 프로젝트 개요

### 1.1 ZAKAR란?

ZAKAR는 **교회 공동체의 사진과 자료를 아카이빙하고 관리하는 iOS 앱**입니다.

**핵심 가치:**
- 🤖 **AI 기반 유사 사진 감지**: pHash + Hamming Distance 알고리즘
- ⚡ **빠른 사진 정리**: 직관적인 스와이프 제스처
- ☁️ **클라우드 백업**: Google Drive 연동
- 📱 **프리미엄 UX**: Liquid Glass 디자인 (보라-골드 그라디언트)
- 🔐 **관리자 승인 시스템**: Firebase 기반 사용자 권한 관리

### 1.2 주요 사용 시나리오

```
교회 행사 촬영 → 앱에서 유사 사진 자동 감지 → 스와이프로 빠른 정리
→ 앨범 생성 → Google Drive 업로드 → 공동체 공유
```

### 1.3 프로젝트 구성

- **ZAKAR (iOS App)**: 사용자용 앱
- **ZAKARAdmin (macOS App)**: 관리자용 사용자 승인 도구
- **Firebase Backend**: 사용자 인증 및 승인 관리

---

## 2. 시스템 아키텍처

### 2.1 전체 구조도

```
┌─────────────────────────────────────────────────────────┐
│                    ZAKAR iOS App                        │
├─────────────────────────────────────────────────────────┤
│  SwiftUI UI Layer                                       │
│  ├─ HomeView (홈 화면)                                  │
│  ├─ ContentView (사진 목록)                             │
│  ├─ CleanUpView (정리 모드)                             │
│  ├─ AlbumsView (앨범 관리)                              │
│  └─ ProfileView (프로필/설정)                           │
├─────────────────────────────────────────────────────────┤
│  Business Logic Layer                                   │
│  ├─ PhotoManager (사진 관리)                            │
│  ├─ AuthService (Firebase 인증)                         │
│  ├─ GoogleDriveService (클라우드 업로드)                │
│  └─ LocalDB (로컬 데이터)                               │
├─────────────────────────────────────────────────────────┤
│  Data Layer                                             │
│  ├─ Photos Framework (시스템 사진)                      │
│  ├─ Firebase (사용자 인증/승인)                         │
│  ├─ Google Drive API (클라우드 스토리지)                │
│  └─ Local Storage (메타데이터/캐시)                     │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                  ZAKARAdmin macOS App                   │
├─────────────────────────────────────────────────────────┤
│  SwiftUI UI                                             │
│  ├─ AdminUserListView (사용자 목록)                     │
│  └─ AdminUserDetailView (승인 관리)                     │
├─────────────────────────────────────────────────────────┤
│  Business Logic                                         │
│  └─ AdminAuthService (Firebase Admin)                   │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                   Firebase Backend                      │
├─────────────────────────────────────────────────────────┤
│  Authentication (Google Sign-In)                        │
│  Firestore Database                                     │
│  └─ users/{userId}                                      │
│     ├─ email                                            │
│     ├─ displayName                                      │
│     ├─ photoURL                                         │
│     ├─ isApproved (승인 여부)                           │
│     └─ createdAt                                        │
└─────────────────────────────────────────────────────────┘
```

### 2.2 기술 스택

**iOS App (ZAKAR)**
- **언어**: Swift 5.9+
- **UI 프레임워크**: SwiftUI
- **아키텍처**: MVVM + ObservableObject
- **사진 처리**: Photos Framework, CoreImage
- **인증**: Firebase Authentication (Google OAuth 2.0)
- **데이터베이스**: Firebase Firestore
- **클라우드**: Google Drive API
- **로컬 저장**: Application Support (JSON)

**macOS App (ZAKARAdmin)**
- **언어**: Swift 5.9+
- **UI 프레임워크**: SwiftUI
- **인증**: Firebase Admin

**백엔드**
- **Firebase Authentication**: Google 로그인
- **Firebase Firestore**: 사용자 승인 데이터
- **Google Drive API**: 파일 업로드

---

## 3. 프로젝트 구조

### 3.1 디렉토리 구조

```
ZAKAR/
├── ZAKAR/                          # iOS App 메인
│   ├── ZAKARApp.swift             # 앱 엔트리 포인트
│   ├── Assets.xcassets/           # 앱 아이콘, 이미지
│   ├── Info.plist                 # 앱 설정
│   │
│   ├── Views/                     # UI 화면
│   │   ├── MainTabView.swift     # 메인 탭바
│   │   ├── HomeView.swift        # 홈 화면
│   │   ├── ContentView.swift     # 사진 목록
│   │   ├── CleanUpView.swift     # 정리 모드
│   │   ├── AlbumsView.swift      # 앨범 관리
│   │   ├── ProfileView.swift     # 프로필
│   │   ├── LoginView.swift       # 로그인
│   │   ├── OnboardingView.swift  # 온보딩
│   │   └── PendingApprovalView.swift # 승인 대기
│   │
│   ├── Services/                  # 비즈니스 로직
│   │   ├── PhotoManager.swift    # 사진 관리 핵심
│   │   ├── AuthService.swift     # Firebase 인증
│   │   ├── GoogleDriveService.swift # Google Drive
│   │   ├── DriveSyncService.swift   # 동기화
│   │   └── LocalDB.swift         # 로컬 저장
│   │
│   ├── Components/                # 재사용 컴포넌트
│   │   ├── Components.swift      # 공통 UI
│   │   ├── SummaryWidgets.swift  # 요약 위젯
│   │   ├── AppTheme.swift        # 테마 정의
│   │   ├── AlbumPickerView.swift
│   │   ├── PhotoSelectionView.swift
│   │   ├── DocumentPickerView.swift
│   │   └── VideoPickerView.swift
│   │
│   ├── Models/                    # 데이터 모델 (묵시적)
│   │   └── (PhotoManager 내 정의)
│   │
│   ├── Documentation/             # 문서
│   │   ├── README.md
│   │   ├── ARCHITECTURE.md
│   │   ├── FRONTEND_BACKEND.md
│   │   └── PROJECT_OVERVIEW.md   # 이 문서
│   │
│   └── Config/                    # 설정 파일
│       ├── GoogleService-Info.plist # Firebase
│       └── client_*.plist        # Google OAuth
│
├── ZAKARAdmin/                    # macOS Admin App
│   ├── ZAKARAdminApp.swift       # 엔트리 포인트
│   ├── AdminRootView.swift       # 메인 화면
│   ├── AdminUserListView.swift   # 사용자 목록
│   ├── AdminUserDetailView.swift # 상세/승인
│   ├── AdminAuthService.swift    # Firebase 연동
│   ├── AdminSettingsView.swift   # 설정
│   ├── Assets.xcassets/          # 앱 아이콘
│   └── ZAKARAdmin.entitlements   # 권한 설정
│
└── ZAKAR.xcodeproj/               # Xcode 프로젝트
```

### 3.2 핵심 파일 설명

| 파일 | 역할 | 중요도 |
|------|------|--------|
| `ZAKARApp.swift` | 앱 시작점, PhotoManager 주입 | ⭐⭐⭐⭐⭐ |
| `PhotoManager.swift` | 사진 로드/분석/관리 핵심 로직 | ⭐⭐⭐⭐⭐ |
| `AuthService.swift` | Firebase 인증 및 승인 체크 | ⭐⭐⭐⭐⭐ |
| `HomeView.swift` | 홈 화면 UI, NavigationStack | ⭐⭐⭐⭐ |
| `ContentView.swift` | 사진 목록, 유사 사진 분석 트리거 | ⭐⭐⭐⭐ |
| `CleanUpView.swift` | 제스처 기반 정리 UX | ⭐⭐⭐⭐ |
| `GoogleDriveService.swift` | Google Drive 업로드 | ⭐⭐⭐ |
| `LocalDB.swift` | 메타데이터/임시보관함 저장 | ⭐⭐⭐ |
| `Components.swift` | 재사용 UI 컴포넌트 | ⭐⭐⭐ |

---

## 4. 핵심 기능

### 4.1 AI 기반 유사 사진 감지

**알고리즘**: pHash (Perceptual Hash) + Hamming Distance

```swift
// PhotoManager.swift
func analyzeGroups(assets: [PHAsset]) {
    // 1. 시간 인접 그룹화 (촬영 시각 기준)
    let timeGroups = groupByTime(assets)

    // 2. 각 그룹 내에서 pHash 계산
    for group in timeGroups {
        let hashes = group.map { calculatePHash($0) }

        // 3. Hamming Distance로 유사도 측정
        let similar = findSimilar(hashes, threshold: 10)

        groupedPhotos.append(similar)
    }
}

func calculatePHash(_ asset: PHAsset) -> UInt64 {
    // 이미지 축소 → 그레이스케일 → DCT → 해시 생성
}
```

**특징:**
- 시각적 유사도 + 시간 인접도 결합
- 캐시를 통한 중복 계산 방지
- 백그라운드 스레드에서 처리

### 4.2 제스처 기반 빠른 정리

```swift
// CleanUpView.swift
DragGesture()
    .onEnded { value in
        if value.translation.height < -100 {
            // 위로 스와이프: 삭제 후보
            addToTrash(photo)
        } else if value.translation.height > 100 {
            // 아래로 스와이프: 즐겨찾기
            toggleFavorite(photo)
        } else if abs(value.translation.width) > 100 {
            // 좌우 스와이프: 다음/이전
            moveToNext()
        }
    }
```

### 4.3 Firebase 인증 및 승인 시스템

**흐름:**

```
1. 사용자 Google 로그인
   ↓
2. Firebase Authentication에 등록
   ↓
3. Firestore에 사용자 정보 저장 (isApproved: false)
   ↓
4. 관리자가 ZAKARAdmin에서 승인
   ↓
5. isApproved: true 업데이트
   ↓
6. 앱 내 모든 기능 활성화
```

**코드 예시:**

```swift
// AuthService.swift
func checkApprovalStatus() async throws -> Bool {
    guard let userId = Auth.auth().currentUser?.uid else {
        return false
    }

    let doc = try await db.collection("users").document(userId).getDocument()
    return doc.data()?["isApproved"] as? Bool ?? false
}
```

### 4.4 Google Drive 업로드

```swift
// GoogleDriveService.swift
func uploadFile(asset: PHAsset, toFolder: String) async throws {
    // 1. OAuth 인증 확인
    guard let token = getAccessToken() else {
        try await authenticate()
    }

    // 2. 폴더 경로 보장
    let folderId = try await ensureFolderPath(toFolder)

    // 3. 이미지 데이터 추출
    let data = try await loadImageData(asset)

    // 4. 멀티파트 업로드
    try await uploadMultipart(data, to: folderId)
}
```

---

## 5. 데이터 흐름

### 5.1 앱 시작 플로우

```
ZAKARApp 시작
    ↓
PhotoManager 생성 및 주입
    ↓
fetchPhotos() 호출
    ↓
Photos 권한 확인
    ↓
백그라운드에서 사진 로드
    ↓
메인 스레드에 반영 (allPhotos 업데이트)
    ↓
HomeView 표시
```

### 5.2 유사 사진 분석 플로우

```
HomeView → "유사 사진" 카드 탭
    ↓
ContentView(initialTab: 0) 생성
    ↓
onAppear에서 selectedTab = 0 설정
    ↓
analyzeSimilaritiesIfNeeded() 호출
    ↓
사진 로드 완료 여부 확인
    ├─ 완료: 즉시 analyzeGroups() 실행
    └─ 미완료: shouldAnalyzeAfterLoad = true 설정
                → 로드 완료 시 자동 분석
    ↓
groupedPhotos 업데이트
    ↓
UI에 유사 그룹 표시
```

### 5.3 사진 정리 플로우

```
ContentView → 그룹 선택 → CleanUpView
    ↓
사용자 제스처 (위/아래/좌/우)
    ↓
    ├─ 위: temporaryTrash에 추가 → LocalDB 저장
    ├─ 아래: toggleFavorite() → Photos Framework
    ├─ 좌/우: 다음/이전 사진
    └─ 휴지통 버튼: TrashView 표시
    ↓
TrashView에서 선택 복구/삭제
    ↓
실제 Photos 라이브러리 삭제
    ↓
temporaryTrash에서 제거 → LocalDB 업데이트
```

### 5.4 Google Drive 업로드 플로우

```
ProfileView → "Google Drive 연결"
    ↓
OAuth 인증 (ASWebAuthenticationSession)
    ↓
Access Token 받기 → Keychain 저장
    ↓
"사진 업로드" 버튼
    ↓
선택한 앨범 사진 로드
    ↓
각 사진에 대해:
    ├─ 폴더 경로 확인/생성
    ├─ 이미지 데이터 추출
    └─ Multipart 업로드
    ↓
완료 알림
```

---

## 6. 주요 모듈 상세

### 6.1 PhotoManager

**역할**: 사진 로드, 유사 분석, 앨범 관리의 핵심 관리자

**주요 프로퍼티:**
```swift
@Published var allPhotos: [PHAsset] = []
@Published var groupedPhotos: [[PHAsset]] = []
@Published var isLoadingList: Bool = false
@Published var isAnalyzing: Bool = false

private var didAnalyzeForCurrentList: Bool = false
private var shouldAnalyzeAfterLoad: Bool = false
private var hashCache: [String: UInt64] = [:]
```

**주요 메서드:**

| 메서드 | 설명 |
|--------|------|
| `fetchPhotos(year:month:)` | Photos 라이브러리에서 사진 로드 |
| `analyzeSimilaritiesIfNeeded()` | 유사 사진 분석 트리거 |
| `analyzeGroups(assets:)` | pHash + Hamming Distance 분석 |
| `toggleFavorite(asset:)` | 즐겨찾기 토글 |
| `deleteAssets(_:)` | 사진 삭제 |
| `addToAlbum(assets:albumTitle:)` | 앨범에 사진 추가 |

**최적화 포인트:**
- `hashCache`로 pHash 중복 계산 방지
- 백그라운드 스레드에서 분석, 메인 스레드에 결과 반영
- `didAnalyzeForCurrentList` 플래그로 재분석 방지

### 6.2 AuthService

**역할**: Firebase 인증 및 사용자 승인 상태 관리

**주요 프로퍼티:**
```swift
@Published var currentUser: User?
@Published var isApproved: Bool = false
@Published var isLoading: Bool = false
```

**주요 메서드:**

| 메서드 | 설명 |
|--------|------|
| `signInWithGoogle()` | Google OAuth 로그인 |
| `signOut()` | 로그아웃 |
| `checkApprovalStatus()` | Firestore에서 승인 여부 확인 |
| `createUserDocument(user:)` | 신규 사용자 Firestore 문서 생성 |

**Firestore 구조:**
```
users/{userId}
├─ email: String
├─ displayName: String
├─ photoURL: String?
├─ isApproved: Bool (기본값: false)
└─ createdAt: Timestamp
```

### 6.3 GoogleDriveService

**역할**: Google Drive OAuth 인증 및 파일 업로드

**주요 메서드:**

| 메서드 | 설명 |
|--------|------|
| `authenticate()` | OAuth 2.0 PKCE 인증 |
| `ensureFolderPath(path:)` | 폴더 경로 확인/생성 |
| `uploadFile(asset:toFolder:)` | 파일 업로드 |
| `listFiles(folderId:)` | 폴더 내 파일 목록 |

**Keychain 저장 항목:**
- Access Token
- Refresh Token
- Token Expiry Date

### 6.4 LocalDB

**역할**: 앱 내부 JSON 저장 (메타데이터, 임시보관함)

**저장 위치:**
```
~/Library/Application Support/ZAKAR/
├─ metadata.json
└─ trash.json
```

**데이터 모델:**
```swift
struct AppMetadata: Codable {
    var onboardingCompleted: Bool
    var lastCleanupDate: Date?
    var estimatedSavings: Int
    var archiveSettings: ArchiveSettings?
}
```

---

## 7. Firebase 백엔드

### 7.1 Firebase 프로젝트 구조

**프로젝트 ID**: `zakar-ios` (예시)

**서비스:**
- Authentication (Google 제공업체 활성화)
- Firestore Database
- Storage (선택사항)

### 7.2 Firestore 규칙

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      // 자신의 문서만 읽기 가능
      allow read: if request.auth.uid == userId;

      // 생성은 인증된 사용자만
      allow create: if request.auth.uid != null;

      // isApproved 필드는 관리자만 수정 가능
      allow update: if request.auth.uid == userId
                    && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['isApproved']);
    }
  }
}
```

### 7.3 Authentication 설정

1. **Google 제공업체 활성화**
2. **iOS OAuth 클라이언트 생성** (Google Cloud Console)
3. **URL Scheme 등록**
   ```
   com.googleusercontent.apps.{CLIENT_ID}
   ```

---

## 8. 개발 환경 설정

### 8.1 필수 요구사항

- **Xcode**: 15.0 이상 (권장: 16.0)
- **macOS**: Sonoma 이상
- **iOS Deployment Target**: 17.0
- **Swift**: 5.9+

### 8.2 초기 설정 단계

**1. 저장소 클론**
```bash
git clone https://github.com/your-org/ZAKAR.git
cd ZAKAR
```

**2. Firebase 설정**
```bash
# GoogleService-Info.plist를 Firebase Console에서 다운로드
# ZAKAR/ZAKAR/ 디렉토리에 배치
```

**3. Google OAuth 설정**
```bash
# Google Cloud Console에서 iOS OAuth 클라이언트 생성
# client_*.plist 다운로드 및 프로젝트에 추가
```

**4. URL Scheme 등록**
```
Xcode → ZAKAR Target → Info → URL Types
└─ URL Schemes: com.googleusercontent.apps.{YOUR_CLIENT_ID}
```

**5. 프로젝트 빌드**
```bash
# Xcode에서 ⌘ + B
```

### 8.3 테스트 계정

**베타 테스터 계정:**
- Email: `betatester@gmail.com`
- Password: `betatester123!`
- 승인 상태: ✅ Approved

### 8.4 주요 Configuration

**Info.plist 필수 항목:**
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>사진을 분석하고 정리하기 위해 사진 라이브러리 접근이 필요합니다.</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>정리한 사진을 저장하기 위해 권한이 필요합니다.</string>

<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.{CLIENT_ID}</string>
        </array>
    </dict>
</array>
```

---

## 9. 배포 가이드

### 9.1 TestFlight 배포

**현재 상태:** ✅ 버전 1.2 (Build 3) 배포 완료

**단계:**
1. Archive 생성 (`Product → Archive`)
2. Organizer → Distribute App → App Store Connect
3. Upload 선택
4. TestFlight 처리 대기 (5-10분)
5. 테스터 초대

### 9.2 App Store 제출

**현재 상태:** ✅ 심사 제출 완료 (2026-03-07)

**제출 체크리스트:**
- [x] 앱 설명 작성 (특수문자 제거)
- [x] 스크린샷 업로드 (1284 × 2778px × 7장)
- [x] 지원 URL (https://shbang37.github.io/zakar--support/)
- [x] 개인정보 처리방침 URL (https://shbang37.github.io/zakar--support/privacy.html)
- [x] 데모 계정 정보
- [x] 연령 등급 (4+)
- [x] 가격 ($0.00 무료)
- [x] 빌드 선택 (1.2)

### 9.3 ZAKARAdmin 배포 (macOS)

**방법:** Developer ID 서명 + 직접 배포

**단계:**
1. Archive 생성
2. Custom → Direct Distribution → Export
3. Developer ID로 서명
4. .app 파일을 관리자들에게 배포

**설치 안내:**
```
1. ZAKARAdmin.app을 Applications 폴더로 이동
2. 최초 실행 시 "확인되지 않은 개발자" 경고 발생
3. 시스템 설정 → 개인정보 보호 및 보안 → "확인 없이 열기" 클릭
4. Google 계정으로 로그인
5. 사용자 승인 관리
```

---

## 10. 트러블슈팅

### 10.1 자주 발생하는 문제

**Q1. 유사 사진 분석이 실행되지 않아요**

**A:**
```swift
// PhotoManager.swift 확인
// shouldAnalyzeAfterLoad 플래그 확인
// ContentView의 onAppear에서 analyzeSimilaritiesIfNeeded() 호출 확인
```

**Q2. Google Drive 업로드가 실패해요**

**A:**
- OAuth 인증 토큰 만료 확인
- Google Cloud Console에서 API 활성화 확인
- URL Scheme 등록 확인

**Q3. Firebase 로그인 후 승인 대기 화면만 나와요**

**A:**
- ZAKARAdmin에서 해당 사용자 승인 필요
- Firestore의 `users/{userId}/isApproved` 필드 확인

**Q4. 임시보관함이 앱 재시작 후 사라져요**

**A:**
- LocalDB의 `trash.json` 저장 확인
- `saveTrashIdentifiers()` 호출 확인

### 10.2 디버깅 팁

**로그 활성화:**
```swift
// PhotoManager.swift
print("[PhotoManager] Loaded \(allPhotos.count) photos")
print("[PhotoManager] Grouped into \(groupedPhotos.count) groups")
```

**Firebase 디버깅:**
```swift
// AuthService.swift
print("[Auth] Current user: \(Auth.auth().currentUser?.email ?? "nil")")
print("[Auth] Approval status: \(isApproved)")
```

### 10.3 성능 최적화

**pHash 캐시 확인:**
```swift
// PhotoManager.swift
print("[Performance] Cache size: \(hashCache.count)")
```

**메모리 프로파일링:**
```
Xcode → Product → Profile → Leaks / Allocations
```

---

## 11. 향후 로드맵

### 11.1 계획된 기능

- [ ] 멀티 선택 모드 (배치 작업)
- [ ] 유사도 엄격도 조절 UI
- [ ] 임시보관함 자동 비우기 (7일 후)
- [ ] iCloud Drive 연동
- [ ] NAS 업로드 지원
- [ ] 앨범별 자동 업로드 설정
- [ ] 동영상 유사도 분석

### 11.2 개선 사항

- [ ] 홈 요약 카드 실데이터 반영
- [ ] 업로드 진행률 표시
- [ ] 오프라인 모드 개선
- [ ] VoiceOver 접근성 강화

---

## 12. 참고 자료

### 12.1 관련 문서

- [README.md](./README.md) - 프로젝트 소개
- [ARCHITECTURE.md](./ARCHITECTURE.md) - 아키텍처 상세
- [FRONTEND_BACKEND.md](./FRONTEND_BACKEND.md) - 프론트엔드/백엔드 구조

### 12.2 외부 리소스

- [Photos Framework Guide](https://developer.apple.com/documentation/photokit)
- [Firebase iOS SDK](https://firebase.google.com/docs/ios/setup)
- [Google Drive API](https://developers.google.com/drive/api/guides/about-sdk)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)

### 12.3 연락처

- **개발자**: Seongho Bang
- **이메일**: shbang37@gmail.com
- **지원 페이지**: https://shbang37.github.io/zakar--support/

---

**© 2026 ZAKAR. All rights reserved.**
