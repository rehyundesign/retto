# Windows 판 (베타)

맥 앱을 옮긴 것이 아니라, 같은 훅 기록을 읽는 두 번째 앱이다. 훅(`hook/`)은 두 앱이 함께 쓰고,
화면은 `windows/` 에 Electron 으로 따로 만들었다. 2026-11-03 시작.

## 실패로 보는 것 — 먼저 정했다

만들기 전에 정했다. 아래가 일어나면 Windows 판은 고장이다. 오른쪽은 그걸 막는 자리다.

| 실패 | 막는 자리 |
| --- | --- |
| 훅이 한 번도 안 돌았는데 레토가 정상 대기처럼 잔다 | 처음 켜면 연동 확인 창(`windows/src/setup.html`). 세션이 없을 때 말풍선이 「연동 확인이 필요해 · 훅 없음」으로 바뀐다. 트레이 메뉴 제목에도 붙는다 |
| `settings.json` 에 sh 경로가 적혀 Claude Code 가 훅마다 오류를 띄운다 | Windows 에서는 `hook.sh` 를 깔지도 부르지도 않는다(`hook/lib/hook-settings.js` `hookCommand`) |
| Claude Code 가 훅을 돌리는 셸이 버전마다 달라 어떤 버전에서만 훅이 안 돈다 | 훅 한 줄을 cmd · PowerShell · bash 셋에서 같은 뜻이 되는 꼴로 적는다 — `node "C:/…/hook.cjs" "running"`. 셋 다 실제로 돌려 보는 테스트가 있다 |
| 레토가 `sessions.json` 을 읽는 순간 훅의 덮어쓰기가 거절돼(EPERM) 상태가 한 칸 사라진다 | 훅이 10ms 간격으로 40번까지 다시 쓴다(`hook/hook.cjs` `writeJSONAtomic`) |
| 훅 여러 개가 동시에 돌 때 하나의 상태가 사라진다 | Windows 는 방금 지운 잠금 폴더가 「삭제 대기」로 남아 EPERM 을 낸다. 훅이 이걸 포기 대신 기다림으로 본다. Windows CI 에서 16개 중 15개만 남은 적이 있어 찾았다(2026-11-03) |
| 백신 검사 등으로 `sessions.json` 을 잠깐 못 읽으면 빈 기록으로 덮어써 모든 세션이 사라진다 | 없는 파일 · 깨진 JSON 만 처음부터 쓰고, 읽기 거절은 기다렸다 다시 읽는다. 끝내 못 읽으면 그 회차만 포기한다. 맥에서도 재현됐다(권한을 막은 시험) |
| 모니터를 뺀 뒤 레토가 화면 밖에 남아 안 보인다 | 저장한 자리가 지금 화면 밖이면 기본 자리로 띄운다. 트레이에 「레토 위치 처음으로」 |
| PATH 에 node 가 없어 Claude Code 가 훅마다 오류를 띄운다 | **아직 못 막는다.** 맥은 `hook.sh` 가 node 를 못 찾으면 오류 없이 끝나지만, Windows 한 줄은 맨 앞이 `node` 라 그대로 실패한다. 연동 확인 창의 「node」 줄은 레토 자신의 PATH 로 찾으므로 Claude Code 가 훅을 돌리는 셸(Git Bash 비로그인 셸 등)과 다를 수 있다 |
| Claude 앱 안의 낮은 claude-code 가 모르는 이벤트 때문에 훅 등록 전체를 버린다 | **아직 못 막는다.** 버전을 `~/Library/Application Support/Claude/claude-code` 에서만 찾아 Windows 에서는 늘 「못 찾음 → 17개 전부 등록」이다. Windows 의 자리는 실기로 확인한 뒤 넣는다 |
| 레토가 발표·게임 화면 위에서 클릭을 막는다 | 트레이 「클릭 통과」. 전체화면 앱 위에서 어떻게 보이는지는 아직 실기 전이다 |

## 증거 단계 — 무엇을 어디까지 확인했나

`[소스]` 코드를 읽음 · `[테스트]` 테스트가 돌았음 · `[실기]` 사람이 쓰는 Windows PC 에서 Claude Code 와 함께 확인. 단계가 다르면 다른 증거다.

| 항목 | 단계 | 근거 |
| --- | --- | --- |
| 훅 한 줄이 bash 에서 돈다 | [테스트] 맥 | `hook/tests/hook-runtime.test.js` 「the Windows-form hook line …」 sh 1건 |
| 훅 한 줄이 cmd · PowerShell · Git Bash 에서 돈다 | [테스트] Windows | windows-latest 에서 세 셸 모두 sessions.json 에 상태를 적었다(2026-11-03 CI, `hook-runtime.test.js` 28~30번) |
| 훅 · 앱 테스트, zip 빌드 | [테스트] Windows | 같은 CI 에서 통과 |
| 설치 → 훅 실행 → 화면 → 제거 | [테스트] Windows | `windows/test-e2e/flow.mjs` — 설치본의 「훅 설치」로 등록하고, 등록된 명령을 cmd · PowerShell · Git Bash 로 돌려 작업 중 → 기다림 → 완료 · 배지 1 이 그려지는지, 「훅 제거」 뒤 다른 훅이 그대로인지 본다. Claude Code 자체는 띄우지 않는다 |
| 상태 판정이 맥 앱과 같다 | [테스트] 맥 | `windows/test/core.test.js` 14건 — 우선순위 · 배지 · 읽음 · 유령 · 고정 · 잠 · VS Code 폴더 링크 |
| 화면이 그려진다(그림 · 말풍선 · 배지 · 손글씨) | [테스트] Windows | CI 가 설치본 `Retto.exe --render-preview` 를 `RETTO_HOME` 가짜 홈으로 띄워 PNG 를 남긴다. 시험용 홈은 `USERPROFILE` 이 아니라 `RETTO_HOME` 으로 바꾼다 — `USERPROFILE` 을 바꾸면 Electron 이 시작하자마자 0x80000003 으로 끝난다(2026-11-03, 사용자 PC 와 무관한 시험 조건 문제) |
| Windows zip 이 만들어진다 | 맥에서 빌드 | x64 · arm64 각 약 159MB(풀면 394MB, `Retto.exe` 246MB) |
| Claude Code(Windows)가 실제로 이 훅을 부른다 | 미검증 | [실기] 필요 |
| VS Code 로 세션 열기 | [소스] | 폴더 창 → 1.2초 뒤 세션 딥링크. 맥은 그 창이 앞에 온 것을 확인한 뒤 보내지만 Windows 는 시간만 기다린다. 작업 폴더를 모르면 딥링크를 보내지 않는다. 같은 탭이 살아나는지는 [실기] 필요 |
| 독립 검토 | 2026-11-03 | 코드를 쓰지 않은 세션이 검토해 HIGH 2 · MEDIUM 5 · LOW 5. 맥 사용자 settings.json 을 깨는 경로는 없었다. 고친 것과 남긴 것은 이 문서에 반영했다 |

## 0.12.1-beta.1 에서 맥과 맞춘 것 (2026-11-13)

맥 0.12.1 과 기능을 맞추는 1단계다. 규칙은 맥 코드를 옮겼고, 값이 갈리면 두 앱이 같은 세션을 다르게 보여 주므로 함께 고친다.

| 기능 | 파일 | 맥 쪽 원본 | 증거 |
| --- | --- | --- | --- |
| Codex 롤아웃으로 task 찾기(최근 하루, 제목 색인, worker 제외) | `windows/src/codex.js` `RolloutDiscovery` | `Sessions.swift` `CodexRolloutDiscovery` | [테스트] 맥 · 이 맥의 실제 `~/.codex` 552개 파일로 맥 레토와 같은 task 를 찾았다 |
| 훅 상태를 롤아웃으로 바로잡기(완료·질문·중단·새 턴) | `codex.js` `reconcileTask` · `transcriptStatus` | `reconcileCodexTask` · `codexTranscriptStatus` | [테스트] 맥 |
| Orca 세션 알아보기 · 메뉴 「· Orca」 | `orca.js` `isOrcaSession` · `core.js` `menuLabel` | `OrcaSessions.swift` · `sessionMenuLabel` | [테스트] 맥 |
| Orca 의 Codex 채팅 제목 · 탭 ID (Orca 세션 기록, `node:sqlite` 읽기 전용) | `orca.js` `ThreadIndex` | `OrcaCodexThreadIndex` | [테스트] 맥 · 실제 Orca 기록 8개 |
| Orca 의 Codex 채팅 입력 대기 · 실패 · 취소 | `orca.js` `ChatStatusReader` · `applyChatStatus` | `OrcaChatStatusReader` · `applyOrcaChatStatus` | [테스트] 맥 · 이 맥의 Orca 1.4.257 에서 Electron 안 실행으로 상태를 읽었다 |
| 누르면 Orca 의 그 탭으로(채팅 · 터미널 · 워크스페이스) | `orca.js` `reveal` | `OrcaNavigator` · `orcaRevealScript` | [소스] |
| 합치기(훅 → 롤아웃 → Orca) | `windows/src/status.js` | `AppDelegate.swift` `applySessions` | [테스트] 맥 · `--render-preview` 로 앱이 실제 세션을 그렸다 |

**맥과 다른 점.** 맥은 Orca 의 Electron 을 node 로 따로 띄운다. Windows 판은 그 자체가 Electron 이라 Orca 의
`runtime-client.js` 를 직접 불러 쓴다. Orca 를 찾는 길 — 떠 있는 `Orca.exe` 의 경로(PowerShell `Get-Process`),
없으면 `%LOCALAPPDATA%\Programs\Orca`. **Windows 에서 Orca 가 실제로 그 자리에 깔리는지는 확인하지 못했다.**
못 찾으면 Orca 기능은 아무것도 하지 않고, 누르면 예전처럼 Codex 앱 · VS Code 로 간다.

## 스킨 — 맥 앱이 그린 프레임을 재생한다 (2단계, 2026-11-13)

스킨은 다시 짜지 않았다. 맥 스킨은 스킨마다 Swift 코드(효과 · 위치 보정 · 시선 · 잠 호흡 · 무작위 변형)가 따로 있어,
옮기면 두 앱의 그림이 갈린다. 대신 맥 앱의 실제 그리기(`RettoView`)를 가짜 시계로 돌려 프레임을 내보낸다.

- **내보내기** `Retto --export-windows-skins <폴더> [--fps 15] [--scale 0.8] [--skins a,b]` (`macos/Sources/WindowsSkinExport.swift`).
  `PetView.swift` 의 시각 읽기를 `nowUptime` 한 자리로 모으고, 값이 있으면 타이머 대신 `exportAdvance(to:)` 가
  타이머가 울렸을 차례마다 `advanceFrame` 을 부른다. 스킨마다 8개 상태 · 끌기 좌우 · 시선 16방향을 담는다
- **만들기** `cd windows && npm run skins` — 공개 빌드(`build-public.py --app-only`)로 내보내고 WebP 로 바꿔
  `windows/skins/` 에 둔다(14종 · 85MB, 생성물이라 Git 밖). zip 을 만들기 전에 돌린다
- **재생** `windows/src/pet.js` — 고르는 순서는 맥 `PetView.draw` 와 같다. 끄는 동안 좌우 달리기 → 누른 뒤 점프 한 바퀴 →
  상태. 완료 손 흔들기는 정해진 횟수 뒤 쉬는 자세(`then`). 쉬는 중에는 커서 쪽 시선(16방향 · 히스테리시스 4° · 한 칸 60ms ·
  멈추면 0.8초 뒤 해제, 맥 `Geometry.swift` 값)
- **스킨 고르기** 트레이 메뉴 「스킨」. 고른 것은 `retto-state.json` 에 남는다
- 스킨 프레임이 없으면(Windows CI 빌드) 예전처럼 기본 아틀라스 한 장으로 그린다

**맥과 다른 점** — 무작위로 고르는 변형(아무 · 란의 완료 동작, 천사의 쉬는 동작 등)은 내보낼 때 뽑힌 한 가지만 담긴다.
시선은 쉬는 중에만 쓴다(맥은 스킨에 따라 작업 중 · 완료에도 쓴다). 한 클립은 최대 6초를 이어 돌린다.
증거: [테스트] 맥 — `electron . --render-preview` 로 기본 · 천사 · 하츄핑핑 · 잔느 · 아무란이 맥과 같은 그림 · 효과로 그려졌다.

## 맥과 아직 다른 것

| 다른 것 | 다음 단계 |
| --- | --- |
| 스킨의 무작위 변형 · 작업 중 시선 | 위 「스킨」. 내보낸 한 가지만 재생한다 |
| Slack 연동 | 3단계. 맥은 토큰을 키체인에 둔다. Windows 자격 증명으로 다시 짜야 한다 |
| Claude 앱 사이드바로 바로 가기 · Claude 앱 · 터미널 세션을 그 앱으로 | 4단계. 맥은 접근성 API 로 행을 누른다. Windows 는 UI Automation 으로 다시 짜야 한다. 지금은 VS Code 로 보낸다 |
| Codex 앱 실시간 상태 스트림 · 밖에서 읽음 판정 · 창 제목으로 읽음 · 트랜스크립트에서 말풍선 문장 | 4단계. 없으면 롤아웃만으로 본 질문 대기는 맥처럼 확인 안 된 것으로 보고 표시하지 않는다 |
| 설치 프로그램 · 서명 · 자동 업데이트 | zip 을 풀어 `Retto.exe` 를 실행한다. 서명이 없어 SmartScreen 이 「추가 정보 → 실행」을 한 번 묻는다 |

## 왜 Electron 인가

- 이 맥에 Rust · .NET 이 없다. Electron 은 맥에서 같은 코드를 띄워 확인할 수 있고 Windows zip 도 맥에서 만든다
- 대가는 크기다. zip 159MB 는 맥 앱보다 훨씬 무겁다. 베타에서 쓰는 사람이 생기면 Tauri(WebView2)로 옮길지 다시 본다 — 화면은 HTML · JS 라 옮길 때 그대로 간다

## 확인하지 못한 것 — 실기 시나리오

1. Windows PC 에 Node.js · Claude Code(VS Code 확장) 설치 → `Retto.exe` 실행 → 연동 확인 창에서 「훅 설치」 → Claude Code 다시 켜기 → 요청 하나 → 레토가 초록(작업 중) → 끝나면 주황 + 배지 1
2. 권한 요청이 뜨는 작업 → 파랑(기다림)
3. 레토를 누르면 그 VS Code 창과 그 세션 탭이 앞으로 오는가(새 패널이 하나 더 열리면 실패)
4. 전체화면 앱 · 가상 데스크톱 전환 · 125% · 150% 배율에서 레토 자리와 크기
5. Codex 가 있으면 훅 승인 화면 → 허용 → Codex 세션도 보이는가
6. 한글 사용자 이름(`C:\Users\레토 사용자`)에서 훅 경로. `$`·`%` 가 든 사용자 이름은 PowerShell·bash 가 변수로 펼칠 수 있어 다루지 않았다
7. Claude 앱(Windows)이 claude-code 를 어디에 내려받는지 — 이벤트 범위 판정에 넣어야 한다

## 돌리는 법

```sh
cd windows && npm install
npm start                                  # 맥에서도 뜬다 — ~/.claude/retto-pet 를 읽는다
npm test                                   # 상태 판정 · 연동 확인
npx electron-builder --win zip --x64 --arm64   # ../dist/windows/ 에 zip
```

Claude Code 안에서 돌리면 `ELECTRON_RUN_AS_NODE=1` 이 걸려 있어 창이 안 뜬다. `env -u ELECTRON_RUN_AS_NODE npm start`.
