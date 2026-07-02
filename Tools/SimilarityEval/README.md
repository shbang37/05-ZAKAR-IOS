# SimilarityEval — 유사 사진 판별 채점 루틴

PhotoManager의 유사 판별 로직(pHash + Vision FeaturePrint 하이브리드)을 미러링한 macOS 스크립트.
임계값을 조정할 때 "체감" 대신 **숫자로 검증**하기 위한 도구다. 시뮬레이터·실기기 없이 터미널에서 바로 돈다.

## 사용법

```bash
cd Tools/SimilarityEval
swift eval.swift            # ./fixtures 평가
swift eval.swift /path/dir  # 다른 픽스처 경로
```

## 픽스처 채우기 (최초 1회)

실제 사진 라이브러리에서 대표 사례를 골라 export 해서 넣는다:

```
fixtures/
├── similar/          # 같은 폴더 안 모든 쌍이 "유사"로 판정되어야 함
│   ├── group01/      # 예: 아기 연사 3장
│   ├── group02/      # 예: 가족 단체사진 2장 (미세한 표정 차이)
│   └── ...
└── dissimilar/       # 같은 폴더 안 모든 쌍이 "비유사"로 판정되어야 함
    ├── trap01/       # 예: 같은 장소·같은 시간이지만 다른 장면 2장
    └── ...
```

- **similar**: 앱이 묶어줘야 하는 진짜 유사 사진 (연사, 미세 변화)
- **dissimilar**: 앱이 과거에 잘못 묶었던 "함정" 쌍이 가장 가치 있다 — 오탐을 발견할 때마다 여기에 추가하면 회귀 테스트가 된다
- 권장 규모: similar 10그룹 + dissimilar 10그룹이면 충분히 유의미
- 포맷: jpg / png / heic

## 출력 해석

- **유사 재현**: 유사여야 하는 쌍 중 실제로 유사 판정된 비율 (미탐 = 낮을수록 나쁨)
- **비유사 오탐**: 비유사여야 하는 쌍 중 잘못 유사 판정된 비율 (높을수록 나쁨)
- **거리 분포**: 모든 쌍의 pHash 해밍거리와 FeaturePrint 거리 — 두 집단이 갈라지는 지점이 좋은 임계값

## ⚠️ 로직 동기화 규칙

이 스크립트는 앱 코드를 import하지 않고 **복제**한다 (iOS 전용 API 의존성 때문).
`PhotoManager.SimilarityPreset` 임계값이나 `calculatePHash` 알고리즘을 바꾸면
`eval.swift`의 `presets` / `pHash()`도 반드시 함께 바꿔야 한다.
FeaturePrint는 양쪽 모두 리비전1 고정 — 앱에서 리비전을 바꾸면 여기도 바꿀 것.

## 픽스처 사진 git 관리

개인 사진이므로 저장소에 커밋하지 않는다 (fixtures/는 .gitignore 처리됨).
로컬에만 유지하고, 지워지면 다시 export 해서 채운다.
