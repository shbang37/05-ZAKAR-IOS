# ZAKAR v2.0 TRD
> Technical Requirements Document

**작성일**: 2026년 05월  
**버전**: v2.0  
**작성자**: 방성호 (그레이스 플랫폼팀)  
**상태**: 초안

---

## 목차

1. [시스템 아키텍처](#1-시스템-아키텍처)
2. [기술 스택](#2-기술-스택)
3. [AWS 아키텍처 상세](#3-aws-아키텍처-상세)
4. [API 설계](#4-api-설계-api-gateway--lambda)
5. [Firebase Firestore 스키마 변경](#5-firebase-firestore-스키마-변경)
6. [Android 기술 요구사항](#6-android-기술-요구사항)
7. [보안 요구사항](#7-보안-요구사항)
8. [iOS 기존 코드 변경 범위](#8-ios-기존-코드-변경-범위)

---

## 1. 시스템 아키텍처

### 1.1 전체 구조도

```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│    iOS 앱           │  │   Android 앱         │  │  macOS Admin        │
│  (Swift / SwiftUI)  │  │ (Kotlin / Compose)  │  │  (SwiftUI)          │
├─────────────────────┤  ├─────────────────────┤  ├─────────────────────┤
│ • Photos Framework  │  │ • MediaStore API    │  │ • Firebase Admin    │
│ • pHash 분석        │  │ • pHash (Kotlin)    │  │ • 사용자 승인 관리  │
│ • Firebase Auth SDK │  │ • Firebase Auth SDK │  │ • 부서·권한 설정    │
│ • aws-sdk-swift     │  │ • AWS SDK Android   │  │ • 이력 조회         │
│ • Google Drive OAuth│  │ • Jetpack Compose   │  │                     │
└──────────┬──────────┘  └──────────┬──────────┘  └──────────┬──────────┘
           │                        │                          │
           └────────────────────────┴──────────────────────────┘
                                    │
                    ┌───────────────▼───────────────┐
                    │       공용 백엔드 레이어        │
                    ├───────────────────────────────┤
                    │ Firebase Auth (Google OAuth)   │
                    │   → JWT ID Token 발급          │
                    │                               │
                    │ AWS Cognito Identity Pool      │
                    │   → Firebase JWT → STS 임시    │
                    │     자격증명 교환              │
                    │                               │
                    │ AWS API Gateway + Lambda       │
                    │   → 비즈니스 로직 처리         │
                    │   → 권한 검증                 │
                    │                               │
                    │ AWS S3 (파일 저장)             │
                    │   → 부서별 폴더 구조           │
                    │                               │
                    │ AWS DynamoDB                   │
                    │   → 메타데이터 + 접근 이력     │
                    │                               │
                    │ Firebase Firestore             │
                    │   → 사용자 정보·승인·권한      │
                    └───────────────────────────────┘
```

### 1.2 인증 흐름

```
① 앱 → Firebase
   Google 계정으로 Firebase Auth 로그인 → ID Token 발급

② 앱 → Firestore
   isApproved + department + role + canDownload 필드 조회

③ 앱 → Lambda (API Gateway)
   Firebase ID Token 전송 → 부서·권한 검증

④ Lambda → Cognito
   AssumeRoleWithWebIdentity
   → 부서별 IAM Role의 임시 자격증명 발급 (TTL 1시간)

⑤ 앱 → S3
   임시 자격증명으로 Presigned URL 통해 파일 업로드/다운로드
```

---

## 2. 기술 스택

### iOS

| 기술 | 버전 | 용도 |
|------|------|------|
| Swift | 5.9+ | 앱 전체 개발 언어 |
| SwiftUI | iOS 17+ | UI 프레임워크 |
| Photos Framework | - | 사진 라이브러리 접근 |
| aws-sdk-swift | 1.x | S3, Cognito, API 호출 |
| Firebase iOS SDK | 11.x | Auth + Firestore |

### Android

| 기술 | 버전 | 용도 |
|------|------|------|
| Kotlin | 1.9+ | 앱 전체 개발 언어 |
| Jetpack Compose | 1.6+ | UI 프레임워크 |
| Material 3 | - | 디자인 시스템 |
| MediaStore API | Android 13+ | 사진 라이브러리 접근 |
| AWS SDK for Android | 2.x | S3, Cognito 연동 |
| Firebase Android SDK | 22.x | Auth + Firestore |
| Hilt | 2.x | 의존성 주입 (DI) |

### AWS 백엔드

| 서비스 | 용도 |
|--------|------|
| Amazon S3 | 파일 스토리지 (부서별 폴더) |
| AWS Cognito Identity Pool | Firebase JWT → 임시 자격증명 교환 |
| AWS API Gateway | REST API 엔드포인트 |
| AWS Lambda | 비즈니스 로직, 권한 검증, 이력 기록 |
| AWS DynamoDB | 메타데이터 + 접근 이력 저장 |
| AWS IAM | 부서별 역할 기반 접근 제어 |
| S3 Server Access Logging | 파일 접근 로그 수집 |

---

## 3. AWS 아키텍처 상세

### 3.1 S3 버킷 구조

```
버킷명: zakar-church-archive
리전:   ap-northeast-2 (서울)

zakar/
├── 송도청/
│   └── {year}/
│       └── {eventName}/
│           └── {filename}
├── 미들청/
│   └── {year}/{eventName}/{filename}
├── 이음청/
│   └── {year}/{eventName}/{filename}
├── 또래청/
│   └── {year}/{eventName}/{filename}
└── _shared/          ← 교회 공용
    └── {year}/{eventName}/{filename}
```

**S3 버킷 설정**

| 항목 | 설정값 |
|------|--------|
| 퍼블릭 액세스 | 전체 차단 |
| 서버 사이드 암호화 | SSE-S3 |
| 버전 관리 | 활성화 (삭제 실수 방지) |
| Server Access Logging | zakar-access-logs 버킷으로 전송 |
| 수명 주기 정책 | 90일 이후 Glacier 이동 (비용 절감) |

### 3.2 IAM 역할 설계

| IAM Role | 접근 경로 | 읽기 | 업로드 | 삭제 |
|----------|---------|------|--------|------|
| `zakar-role-songdo` | `zakar/송도청/*` | ✅ | 권한 설정에 따름 | ❌ |
| `zakar-role-middle` | `zakar/미들청/*` | ✅ | 권한 설정에 따름 | ❌ |
| `zakar-role-eum` | `zakar/이음청/*` | ✅ | 권한 설정에 따름 | ❌ |
| `zakar-role-ddrae` | `zakar/또래청/*` | ✅ | 권한 설정에 따름 | ❌ |
| `zakar-role-admin` | `zakar/*` | ✅ | ✅ | ✅ |

> **읽기 vs 다운로드 구분**  
> - Presigned URL 발급 시 `Content-Disposition: inline` → 브라우저/앱 내 보기만  
> - `Content-Disposition: attachment` → 다운로드 허용  
> - Lambda에서 `canDownload` 필드 확인 후 헤더 결정

### 3.3 DynamoDB 테이블 설계

#### 테이블 1: `ArchiveMetadata` (파일 메타데이터)

| 필드명 | 타입 | 키 | 설명 |
|--------|------|-----|------|
| `fileId` | String | **PK** | UUID |
| `department` | String | GSI-PK | 송도청\|미들청\|이음청\|또래청 |
| `s3Key` | String | - | S3 객체 경로 |
| `uploadedBy` | String | GSI | Firebase UID |
| `uploadedAt` | Timestamp | GSI-SK | 업로드 시각 |
| `eventName` | String | - | 행사명 |
| `fileType` | String | - | `photo`\|`video`\|`document` |
| `fileSize` | Number | - | 바이트 단위 |
| `originalName` | String | - | 원본 파일명 |

#### 테이블 2: `AccessLog` (접근 이력)

| 필드명 | 타입 | 키 | 설명 |
|--------|------|-----|------|
| `logId` | String | **PK** | UUID |
| `userId` | String | GSI-PK | Firebase UID |
| `accessedAt` | Timestamp | GSI-SK | 접근 시각 |
| `fileId` | String | GSI | 접근한 파일 ID |
| `actionType` | String | - | `VIEW`\|`DOWNLOAD`\|`UPLOAD` |
| `platform` | String | - | `iOS`\|`Android` |
| `ipAddress` | String | - | 접속 IP (Lambda에서 기록) |
| `department` | String | - | 접근 부서 |

---

## 4. API 설계 (API Gateway + Lambda)

**Base URL**: `https://{api-id}.execute-api.ap-northeast-2.amazonaws.com/prod`  
**공통 헤더**: `Authorization: Bearer {Firebase ID Token}`

| Method | Path | 설명 | Lambda |
|--------|------|------|--------|
| `POST` | `/auth/token` | Firebase 토큰 → AWS 임시 자격증명 교환 | `TokenExchangeFunction` |
| `GET` | `/files` | 부서 파일 목록 조회 | `ListFilesFunction` + AccessLog 기록 |
| `POST` | `/files/upload-url` | S3 Presigned Upload URL 발급 | `PresignedUploadFunction` |
| `GET` | `/files/{id}/view-url` | 읽기 전용 Presigned URL 발급 | `PresignedViewFunction` + AccessLog |
| `GET` | `/files/{id}/download-url` | 다운로드 Presigned URL 발급 (권한 체크) | `PresignedDownloadFunction` + AccessLog |
| `POST` | `/files/metadata` | 업로드 완료 후 메타데이터 저장 | `SaveMetadataFunction` |
| `GET` | `/logs` | 접근 이력 조회 (관리자 전용) | `AccessLogQueryFunction` |
| `DELETE` | `/files/{id}` | 파일 삭제 (간사·관리자) | `DeleteFileFunction` |

### 주요 Request / Response 예시

#### POST `/auth/token`
```json
// Request
{ "firebaseToken": "eyJhbGci..." }

// Response
{
  "accessKeyId": "ASIA...",
  "secretAccessKey": "...",
  "sessionToken": "...",
  "expiration": "2026-05-13T15:00:00Z",
  "department": "송도청",
  "role": "member",
  "canDownload": false
}
```

#### POST `/files/upload-url`
```json
// Request
{
  "department": "송도청",
  "eventName": "2026_부활절예배",
  "filename": "photo_001.jpg",
  "fileType": "photo",
  "fileSize": 5242880
}

// Response
{
  "uploadUrl": "https://zakar-church-archive.s3.amazonaws.com/...",
  "fileId": "uuid-...",
  "expiresIn": 900
}
```

---

## 5. Firebase Firestore 스키마 변경

### 5.1 `users` 컬렉션 변경

```
users/{userId}
├── email: String               ← 기존 유지
├── displayName: String         ← 기존 유지
├── photoURL: String?           ← 기존 유지
├── isApproved: Bool            ← 기존 유지
├── createdAt: Timestamp        ← 기존 유지
│
├── department: String?         ← 신규 추가 ("송도청"|"미들청"|"이음청"|"또래청")
├── role: String                ← 신규 추가 ("member"|"leader"|"admin")
├── canDownload: Bool           ← 신규 추가 (기본값: false)
├── canUpload: Bool             ← 신규 추가 (기본값: false)
└── platform: String?           ← 신규 추가 ("iOS"|"Android")
```

### 5.2 ZAKARAdmin 변경 사항

- 사용자 승인 시 `department`, `role`, `canDownload`, `canUpload` 함께 설정
- 이력 조회 탭 추가 (DynamoDB AccessLog 연동)
- CSV 내보내기 버튼 추가

---

## 6. Android 기술 요구사항

### 6.1 프로젝트 구조

```
zakar-android/
├── app/
│   ├── src/main/
│   │   ├── java/com/zakar/app/
│   │   │   ├── ui/
│   │   │   │   ├── home/         HomeViewModel + HomeScreen
│   │   │   │   ├── cleanup/      CleanUpViewModel + CleanUpScreen
│   │   │   │   ├── archive/      ArchiveViewModel + ArchiveScreen
│   │   │   │   ├── albums/       AlbumsViewModel + AlbumsScreen
│   │   │   │   └── profile/      ProfileScreen
│   │   │   ├── service/
│   │   │   │   ├── PhotoManager.kt   ← pHash + MediaStore
│   │   │   │   ├── AuthService.kt    ← Firebase Auth
│   │   │   │   └── AWSService.kt     ← S3 + Cognito
│   │   │   └── model/
│   │   │       └── (데이터 모델)
│   │   └── res/
│   └── build.gradle.kts
└── gradle/
```

### 6.2 Android pHash 구현

```kotlin
// iOS PhotoManager.swift의 calculatePHash를 Kotlin으로 포팅
object PHashCalculator {

    fun calculate(bitmap: Bitmap): Long {
        // 1. 32x32 그레이스케일 리사이즈
        val resized = Bitmap.createScaledBitmap(bitmap, 32, 32, true)
        val pixels = DoubleArray(1024) { i ->
            val pixel = resized.getPixel(i % 32, i / 32)
            (0.299 * Color.red(pixel) + 0.587 * Color.green(pixel) + 0.114 * Color.blue(pixel))
        }

        // 2. 2D DCT 적용 (8x8 영역)
        val dct = applyDCT(pixels)

        // 3. 평균값 기준 64비트 해시 생성
        val avg = dct.average()
        return dct.fold(0L) { hash, value ->
            (hash shl 1) or (if (value >= avg) 1L else 0L)
        }
    }

    fun hammingDistance(hash1: Long, hash2: Long): Int =
        java.lang.Long.bitCount(hash1 xor hash2)
}
```

> iOS와 동일한 임계값 적용: Light(14) / Balanced(18) / Strict(22)

### 6.3 핵심 의존성 (build.gradle.kts)

| 라이브러리 | 버전 | 용도 |
|-----------|------|------|
| `firebase-auth-ktx` | 22.x | Firebase 인증 |
| `firebase-firestore-ktx` | 24.x | Firestore 사용자 관리 |
| `aws-android-sdk-s3` | 2.x | S3 업로드 / 다운로드 |
| `aws-android-sdk-cognitoidentity` | 2.x | 임시 자격증명 |
| `credentials-play-services-auth` | 1.x | Google Sign-In |
| `coil-compose` | 2.x | 이미지 로딩 (iOS Kingfisher 대응) |
| `accompanist-permissions` | 0.x | 미디어 접근 권한 요청 |
| `hilt-android` | 2.x | 의존성 주입 |
| `kotlinx-coroutines-android` | 1.7+ | 비동기 처리 |

### 6.4 iOS ↔ Android 기능 매핑

| iOS | Android |
|-----|---------|
| `PhotoManager.swift` | `PhotoManager.kt` |
| `AuthService.swift` | `AuthService.kt` |
| `AWSService.swift` | `AWSService.kt` |
| `CleanUpView.swift` | `CleanUpScreen.kt` (Compose) |
| `HomeView.swift` | `HomeScreen.kt` (Compose) |
| `Photos.PHAsset` | `MediaStore.Images.Media` |
| `CoreImage` (pHash) | `android.graphics.Bitmap` (pHash) |
| `Keychain` | `EncryptedSharedPreferences` |
| `SwiftUI NavigationStack` | `Compose NavHost` |

---

## 7. 보안 요구사항

| 항목 | 구현 방법 |
|------|---------|
| **토큰 저장** | iOS: Keychain / Android: EncryptedSharedPreferences |
| **API 인증** | 모든 요청에 Firebase ID Token Bearer 헤더 포함, Lambda에서 검증 |
| **S3 접근** | 직접 URL 노출 없음 — Lambda 발급 Presigned URL 사용 (유효기간 15분) |
| **전송 암호화** | HTTPS / TLS 1.3 강제 (ATS on iOS, Network Security Config on Android) |
| **임시 자격증명** | STS 임시 키 TTL 1시간, 만료 전 자동 갱신 |
| **접근 로그** | S3 Server Access Log + DynamoDB AccessLog 이중 기록 |
| **권한 검증** | Lambda에서 Firestore `department` + `role` 재검증 (클라이언트 신뢰 금지) |
| **데이터 격리** | IAM 정책으로 부서별 S3 경로 강제 분리 |

---

## 8. iOS 기존 코드 변경 범위

| 파일 | 변경 유형 | 변경 내용 |
|------|---------|---------|
| `ArchiveView.swift` | 🔄 수정 | NAS 패널 → AWS 패널 교체, 부서 선택 UI 추가 |
| `AuthService.swift` | 🔄 소폭 수정 | `department`, `role`, `canDownload`, `canUpload` 필드 추가 |
| `AWSService.swift` | 🆕 신규 | `ZKDriveSyncing` 구현체, S3 업로드/다운로드, Cognito 인증 |
| `DriveSyncService.swift` | ✅ 유지 | `ZKDriveSyncing` 프로토콜 유지, AWSService에서 채택 |
| `GoogleDriveService.swift` | ✅ 유지 | 변경 없음 |
| `PhotoManager.swift` | ✅ 유지 | 변경 없음 |
| `CleanUpView.swift` | ✅ 유지 | 변경 없음 |
| `HomeView.swift` | ✅ 유지 | 변경 없음 |
| `ZAKARApp.swift` | ✅ 유지 | 변경 없음 |

> ⚠️ **핵심 원칙**: 기존 사진 정리 기능(pHash, 스와이프, 앨범 관리)은 코드 변경 없이 완전 유지

---

> **© 2026 ZAKAR. 은혜의교회 그레이스 플랫폼팀**  
> 최종 업데이트: 2026년 05월
