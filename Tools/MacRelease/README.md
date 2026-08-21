# ZAKAR Mac 배포

## 진행 상황 (2026-08-21 기준)

| 단계 | 상태 |
|---|---|
| macOS 앱 구현 (Phase 0~9) | ✅ 완료 |
| 개발자 본인 Mac 설치 | ✅ `/Applications/ZAKAR Mac.app` (Release 빌드) |
| 배포 스크립트 작성 | ✅ `package_mac.sh` (문법 검증만, 실행 미검증) |
| **Developer ID Application 인증서** | ❌ **미발급** — 현재 `Apple Development`·`Apple Distribution`만 보유. 외부 배포 불가 |
| 공증 자격증명(`zakar-notary`) 저장 | ❌ 미설정 |
| DMG 생성·공증 | ⏸ 위 두 항목 완료 후 가능 |
| 동역자 배포 | ⏸ 대기 |

**다음에 할 일**: 아래 "최초 1회 준비" 3단계를 마친 뒤 `package_mac.sh`를 처음 실행하고, 실패 지점이 있으면 스크립트를 보정한다.

배포 방식 결정 근거 — Developer ID + 공증 + DMG를 택함:
- 심사가 없어 즉시 배포 가능 (TestFlight/App Store는 심사 대기)
- 받는 쪽은 DMG 더블클릭 → 드래그 한 번으로 끝
- 서명 없이 zip 전달은 macOS 15부터 우클릭-열기 우회가 막혀 비권장
- 자동 업데이트가 필요해지면 그때 TestFlight(macOS)로 재검토

## 개발자용 — 배포 파일 만들기

```bash
bash Tools/MacRelease/package_mac.sh
```

결과: `Tools/MacRelease/build/ZAKAR-Mac-<버전>.dmg` — 이 파일 하나만 전달하면 됩니다.

최초 1회 준비 (스크립트가 없으면 알려줍니다):
1. developer.apple.com → Certificates → **Developer ID Application** 인증서 발급·설치
   - `Apple Development`·`Apple Distribution` 인증서로는 외부 배포 불가
2. appleid.apple.com → 로그인 및 보안 → **앱 암호** 생성
3. `xcrun notarytool store-credentials "zakar-notary" --apple-id <애플ID> --team-id 3WZ7DUJB2W --password <앱 암호>`

버전을 올리려면 Xcode에서 `ZAKAR Mac` 타깃 → General → Version / Build 수정 후 다시 실행.

---

## 동역자용 — 아래 내용을 그대로 전달하세요

### ZAKAR 설치 안내

**필요 사양**: macOS 14 (Sonoma) 이상

1. 받으신 `ZAKAR-Mac-1.0.dmg` 파일을 더블클릭합니다.
2. 창이 열리면 **ZAKAR Mac 아이콘을 옆의 Applications 폴더로 끌어다 놓으세요.**
3. Launchpad(또는 ⌘Space → "ZAKAR")에서 실행합니다.
4. 처음 실행하면 **사진 접근을 묻는 창**이 뜹니다 → **"전체 접근 허용"** 을 눌러 주세요.
   - 사진을 분석해 비슷한 사진을 묶어 주는 데 필요합니다.
   - 실수로 거부했다면: 시스템 설정 → 개인정보 보호 및 보안 → 사진 → ZAKAR Mac 켜기

### 사용법 요약

| 화면 | 하는 일 |
|---|---|
| **유사 그룹** | 비슷한 사진 묶음에서 제일 잘 나온 한 장(금색 테두리)만 남기고 정리. **⏎ 한 번**이면 그 그룹 끝 |
| **리뷰** | 사진을 한 장씩 넘기며 선별. `⌫` 버림 · `F` 즐겨찾기 · `←→` 이동 · `Space` 크게 보기 |
| **휴지통** | 버린 사진 보관함. **여기서 "비우기"를 눌러야 실제로 삭제**됩니다 |

- 잘못 눌렀으면 **⌘Z** 로 되돌릴 수 있습니다.
- 휴지통을 비우기 전까지는 사진이 지워지지 않으니 편하게 사용하세요.
