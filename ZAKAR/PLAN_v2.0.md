# ZAKAR v2.0 기획안
> 개발 계획 및 일정

**작성일**: 2026년 05월  
**버전**: v2.0  
**작성자**: 방성호 (그레이스 플랫폼팀)  
**상태**: 초안

---

## 목차

1. [프로젝트 배경](#1-프로젝트-배경)
2. [프로젝트 범위](#2-프로젝트-범위)
3. [단계별 구현 계획](#3-단계별-구현-계획)
4. [전체 타임라인](#4-전체-타임라인)
5. [리스크 관리](#5-리스크-관리)
6. [AWS 비용 예측](#6-aws-비용-예측-월-기준)
7. [배포 체크리스트](#7-배포-체크리스트)

---

## 1. 프로젝트 배경

### 현재 vs 목표

| 구분 | 현재 (v1.x) 한계 | 목표 (v2.0) 개선 |
|------|----------------|----------------|
| 플랫폼 | iOS 전용 → Android 사용자 이탈 | iOS + Android 크로스플랫폼 |
| 아카이브 | NAS Mock → 실제 파일 저장 없음 | AWS S3 실제 파일 저장 |
| 권한 관리 | 부서별 권한 관리 없음 | 부서별 IAM 권한 분리 |
| 이력 추적 | 접근 이력 추적 불가 | DynamoDB 접근 이력 추적 |
| 스토리지 | Google Drive 개인 계정 의존 | 교회 공용 아카이브 서버 |

---

## 2. 프로젝트 범위

| 구분 | 내용 |
|------|------|
| **포함** | iOS v2.0 업데이트 / Android 앱 신규 개발 / AWS 인프라 구축 / ZAKARAdmin 기능 확장 |
| **제외** | 웹앱 개발 / 실시간 Push 알림 / 결제·구독 / 안면 인식 |
| **선행 조건** | AWS 계정 준비 / Firebase 프로젝트 공유 설정 / Android Studio 개발 환경 구성 |

---

## 3. 단계별 구현 계획

---

### Phase 1 — AWS 인프라 구축 `Week 1~2`

> AWS 콘솔 작업 중심. 코드 없이 인프라 전체 세팅 완료

| # | 작업 항목 | 산출물 |
|---|---------|--------|
| 1 | AWS 계정 설정 및 IAM 관리자 계정 생성 | AWS Console 접근 확인 |
| 2 | S3 버킷 생성 (`zakar-church-archive`, `ap-northeast-2`) | 버킷 URL + 정책 설정 |
| 3 | 부서별 폴더 구조 생성 (송도청 / 미들청 / 이음청 / 또래청) | 폴더 구조 확인 |
| 4 | IAM Role 5개 생성 (부서별 4개 + 관리자 1개) | IAM Policy JSON |
| 5 | Cognito Identity Pool 생성 + Firebase 연동 설정 | Identity Pool ID |
| 6 | DynamoDB 테이블 생성 (`ArchiveMetadata`, `AccessLog`) | 테이블 ARN |
| 7 | Lambda 함수 개발 (TokenExchange, PresignedURL, AccessLog 등) | Lambda 함수 7개 |
| 8 | API Gateway REST API 구성 + 인증 설정 | API Endpoint URL |
| 9 | S3 Server Access Logging + CloudTrail 활성화 | 로그 버킷 확인 |
| 10 | Postman / curl 전체 API 엔드포인트 테스트 | 테스트 리포트 |

**완료 기준**: 모든 API 정상 응답 + S3 업로드/다운로드 권한 검증 완료

---

### Phase 2 — iOS v2.0 업데이트 `Week 3~4`

> 기존 iOS 앱에 AWS 연동 추가. 기존 기능 100% 유지

| # | 작업 항목 | 변경 파일 | 산출물 |
|---|---------|---------|--------|
| 1 | `aws-sdk-swift` SPM 패키지 추가 | Package.swift | 빌드 성공 |
| 2 | `AWSService.swift` 구현 (`ZKDriveSyncing` 채택) | AWSService.swift (신규) | 유닛 테스트 통과 |
| 3 | `AuthService`에 department / role / 권한 필드 추가 | AuthService.swift | 로그인 후 권한 조회 |
| 4 | `ArchiveView` NAS 패널 → AWS 패널 교체 | ArchiveView.swift | AWS 업로드 UI 확인 |
| 5 | 부서 선택 + 행사명 입력 UI 구현 | ArchiveView.swift | UI 스크린샷 |
| 6 | 업로드 진행률 + 멀티파트 업로드 구현 | AWSService.swift | 100MB 파일 업로드 성공 |
| 7 | 파일 목록 조회 화면 구현 | ArchiveView.swift | 목록 표시 확인 |
| 8 | 기존 사진 정리 기능 회귀 테스트 | 전체 | 기존 기능 이상 없음 ✅ |
| 9 | TestFlight 배포 (v2.0 beta) | Xcode Archive | TestFlight 링크 |

**완료 기준**: TestFlight 베타 배포 완료 + 기존 기능 회귀 테스트 통과

---

### Phase 3 — Android 앱 개발 `Week 5~10`

> 신규 Android 앱 개발. iOS와 동일한 UX/기능 목표

#### Week 5 — 프로젝트 기반 구축

| 작업 | 산출물 |
|------|--------|
| Android Studio 프로젝트 생성, Gradle 의존성 설정 | 프로젝트 빌드 성공 |
| Firebase Auth Android SDK 연동 (Google 로그인) | 로그인 화면 작동 |
| 기본 화면 뼈대 (MainTabView, 하단 네비게이션) | 탭 이동 확인 |

#### Week 6 — 사진 기능 핵심 구현

| 작업 | 산출물 |
|------|--------|
| MediaStore API로 사진 라이브러리 접근 구현 | 사진 Grid 표시 |
| pHash 알고리즘 Kotlin 구현 (DCT + Hamming Distance) | iOS와 동일 결과 검증 ✅ |

#### Week 7 — 사진 정리 UI 구현

| 작업 | 산출물 |
|------|--------|
| 유사 사진 그룹화 화면 (ContentView Android 버전) | 그룹 목록 표시 |
| 스와이프 제스처 정리 UI (CleanUpView Android 버전) | 위 / 아래 / 좌우 스와이프 |

#### Week 8 — 아카이브 + 부가 기능

| 작업 | 산출물 |
|------|--------|
| AWS S3 업로드 화면 (ArchiveView Android 버전) | 업로드 성공 확인 |
| 홈 화면 + 앨범 관리 화면 | iOS와 동일 UX |

#### Week 9 — 마무리 + 통합 테스트

| 작업 | 산출물 |
|------|--------|
| 프로필 화면 + 설정 + 로그아웃 | 계정 관리 정상 |
| 전체 기능 통합 테스트 (iOS ↔ Android 동기화) | 테스트 케이스 통과 |

#### Week 10 — Play Store 배포 준비

| 작업 | 산출물 |
|------|--------|
| Google Play Store 배포 준비 (서명, 스크린샷, 설명) | Play Console 업로드 |
| 내부 테스트 트랙 배포 + 10명 테스터 검증 | 테스터 피드백 수집 |

**완료 기준**: pHash 결과 iOS 동일성 검증 + Play Console 내부 테스트 배포

---

### Phase 4 — ZAKARAdmin 확장 + 최종 배포 `Week 11~12`

| # | 작업 항목 | 산출물 |
|---|---------|--------|
| 1 | ZAKARAdmin에 부서·권한 설정 UI 추가 | department / role / canDownload / canUpload 설정 |
| 2 | 접근 이력 조회 화면 (날짜 / 사용자 / 파일 필터) | ZAKARAdmin 이력 탭 |
| 3 | 이력 CSV 내보내기 기능 | CSV 파일 저장 |
| 4 | iOS v2.0 App Store 업데이트 제출 | App Store 심사 제출 |
| 5 | Android v1.0 Google Play Store 제출 | Play Store 심사 제출 |
| 6 | 은혜의교회 온보딩 가이드 작성 (Android용 추가) | 온보딩 PDF / 영상 |

**완료 기준**: iOS App Store + Android Play Store 심사 제출 완료

---

## 4. 전체 타임라인

```
          Week  1  2  3  4  5  6  7  8  9 10 11 12
          ─────────────────────────────────────────
Phase 1   AWS   ██ ██
Phase 2   iOS         ██ ██
Phase 3   Android           ██ ██ ██ ██ ██ ██
Phase 4   배포                                 ██ ██
          ─────────────────────────────────────────
```

| 단계 | 기간 | 목표 완료 |
|------|------|---------|
| Phase 1 (AWS 인프라) | W1~2 (2주) | 2026년 6월 초 |
| Phase 2 (iOS v2.0) | W3~4 (2주) | 2026년 6월 중 |
| Phase 3 (Android) | W5~10 (6주) | 2026년 7월 말 |
| Phase 4 (배포) | W11~12 (2주) | 2026년 8월 중 |
| **전체** | **12주** | **2026년 8월** |

---

## 5. 리스크 관리

| 리스크 | 발생 가능성 | 영향도 | 대응 방안 |
|--------|-----------|--------|---------|
| AWS 비용 초과 | 중 | 높음 | S3 수명주기 정책 설정, CloudWatch 비용 알림 ($10 초과 시 알림) |
| Firebase ↔ Cognito 토큰 연동 오류 | 중 | 높음 | Phase 1에서 충분한 테스트, 백업 인증 플로우 준비 |
| Android pHash 결과 iOS와 불일치 | 중 | 중간 | 동일 테스트 이미지셋으로 iOS / Android 결과 비교 검증 |
| Google Play Store 심사 지연 | 중 | 중간 | 심사 2~3주 전 제출, 내부 테스트로 병행 |
| 1인 개발 일정 지연 | 높음 | 중간 | Phase 2(iOS) 먼저 배포 후 Android 단계적 진행 |
| AWS 리전 레이턴시 | 낮음 | 낮음 | ap-southeast-2(시드니) → ap-northeast-2(서울)로 변경 |

---

## 6. AWS 비용 예측 (월 기준)

> 기준: 300명 사용자, 월 업로드 1,000건, 저장 100GB

| 서비스 | 사용량 기준 | 예상 비용 | 비고 |
|--------|-----------|---------|------|
| S3 저장 (100GB) | 사진·영상·문서 | ~$2.30/월 | 300명 × 평균 300MB |
| S3 요청 | 업로드·조회 | ~$0.50/월 | 월 5,000건 기준 |
| Lambda | API 호출 | **$0** | 월 100만 건까지 Free Tier |
| API Gateway | REST API 호출 | ~$0.35/월 | 월 10만 건 기준 |
| DynamoDB | 읽기·쓰기 | **$0** | 25GB까지 Free Tier |
| Cognito | 사용자 풀 | **$0** | MAU 50,000까지 Free Tier |
| **월 합계** | | **~$3~5/월** | **약 4,000~7,000원** |

> 📌 저장 용량이 증가하면 비용 증가  
> - 500GB 기준: 약 $12/월  
> - 1TB 기준: 약 $23/월

---

## 7. 배포 체크리스트

### ✅ iOS v2.0 App Store

- [ ] `AWSService.swift` 단위 테스트 통과
- [ ] 업로드 / 다운로드 권한별 동작 확인
- [ ] 기존 pHash · 스와이프 · 앨범 기능 회귀 테스트
- [ ] TestFlight 베타 (담당자 10명) 검증 완료
- [ ] App Store 스크린샷 갱신 (AWS 아카이브 화면 포함)
- [ ] 개인정보처리방침 URL 유지 확인
- [ ] iOS Deployment Target 확인 (17.0)
- [ ] App Store 제출

### ✅ Android v1.0 Google Play Store

- [ ] pHash 결과 iOS와 동일성 검증
- [ ] Google 로그인 → 승인 대기 → 앱 진입 플로우 확인
- [ ] S3 업로드 전 타입 테스트 (사진 / 영상 / 문서)
- [ ] Android 13 / 14 실기기 테스트
- [ ] 내부 테스트 트랙 → 10명 테스터 검증
- [ ] 개인정보처리방침 URL 등록 (iOS와 동일 URL 공유 가능)
- [ ] Play Store 스크린샷 업로드 (1080 × 1920px 최소 4장)
- [ ] Google Play Store 제출

### ✅ AWS 인프라

- [ ] S3 버킷 퍼블릭 액세스 완전 차단 확인
- [ ] IAM Role 부서별 접근 격리 테스트
- [ ] CloudWatch 비용 알림 설정 ($10 초과 시)
- [ ] Server Access Logging 활성화 확인
- [ ] API Gateway 스로틀링 설정 (초당 100req 제한)
- [ ] Lambda 에러율 모니터링 알림 설정

---

## 8. 참고 문서

| 문서 | 파일명 |
|------|--------|
| 제품 요구사항 | `PRD_v2.0.md` |
| 기술 요구사항 | `TRD_v2.0.md` |
| 프로젝트 메모리 | `ZAKAR_PROJECT_MEMORY.md` |
| 전체 설계도 | `PROJECT_OVERVIEW.md` |
| 아키텍처 | `ARCHITECTURE.md` |

---

> **© 2026 ZAKAR. 은혜의교회 그레이스 플랫폼팀**  
> 최종 업데이트: 2026년 05월
