# Retto — 2026-11-10 로컬 동일본 (14종 스킨)

[현재 로컬과 동일한 앱 ZIP 다운로드](https://github.com/rehyundesign/retto/releases/download/v0.11.1-local.20261110/Retto-local-14skins-20261110.zip)

Apple Silicon Mac · macOS 13 이상 · ZIP 약 1.51 GB.

이 ZIP은 2026-11-10에 설치되어 있던 Retto.app을 그대로 압축했습니다. ZIP을 다시 풀어 실행 파일·리소스·서명을 포함한 31,495개 파일의 SHA-256과 파일 권한이 원본과 동일한지 확인했습니다. 별도 사용자 설정, 키체인 토큰, Slack 메시지 기록은 포함하지 않습니다.

- 리락쿠마 2종을 포함해 로컬의 14종 스킨을 모두 공개합니다. 사용자가 이번 배포에 명시적으로 승인했습니다.
- 천사날개의 넓어진 눈 간격·몸 비율, 점프 윙크, 하늘색 눈의 완료 모션을 포함합니다.
- 캐릭터 크기는 설치 앱의 설정과 동일합니다. 완료 모션 bodyScale 1.10, ground 484를 보존했습니다.
- 기존 설치 앱의 Info.plist도 그대로 보존하여 앱 내부 버전은 0.10.0으로 표시됩니다. 이 릴리스의 태그는 스냅샷 식별자입니다.
- 소스 빌드 버전은 0.11.1입니다. 새 빌드의 메타데이터·서명은 달라질 수 있으며, 설치 앱과 파일까지 동일한 배포물은 위 ZIP입니다.
- 현재 로컬의 Slack 설정 안내 UI도 그대로 보존했습니다. 이전 0.11 공개 빌드의 HTML 안내 버튼과는 차이가 있습니다.

## 설치

1. 실행 중인 레토를 종료합니다.
2. ZIP을 풀고 Retto.app을 Applications 폴더에 복사합니다.
3. 앱을 실행합니다. macOS가 차단하면 시스템 설정 → 개인정보 보호 및 보안에서 ‘그래도 열기’를 사용합니다.

Apple Developer ID 서명·공증은 포함하지 않으며, 기존 로컬 앱의 ad-hoc 서명을 보존했습니다.

## 검증

- ZIP 재추출본 전체 파일·권한 비교: 원본과 동일
- 재추출본 런타임·Slack·스킨 자체 검사 20종: 통과
- codesign --verify --deep --strict: 통과
- 소스에 기록한 31,487개 그림·효과 리소스와 설치 앱의 해시: 일치
- 이번 PR은 #27의 배포 소스 위에 추가됩니다. PR 생성은 main 병합을 의미하지 않습니다.

[SHA-256 체크섬](https://github.com/rehyundesign/retto/releases/download/v0.11.1-local.20261110/Retto-local-14skins-20261110.sha256) · [검증 결과](https://github.com/rehyundesign/retto/releases/download/v0.11.1-local.20261110/verification.json)
