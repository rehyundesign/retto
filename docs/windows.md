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
| 상태 판정이 맥 앱과 같다 | [테스트] 맥 | `windows/test/core.test.js` 14건 — 우선순위 · 배지 · 읽음 · 유령 · 고정 · 잠 · VS Code 폴더 링크 |
| 화면이 그려진다(그림 · 말풍선 · 배지 · 손글씨) | 맥에서 띄움 | `Retto --render-preview` 를 가짜 홈으로 맥에서 실행해 확인. Windows 렌더는 CI 대기 |
| Windows zip 이 만들어진다 | 맥에서 빌드 | x64 · arm64 각 약 159MB(풀면 394MB, `Retto.exe` 246MB) |
| Claude Code(Windows)가 실제로 이 훅을 부른다 | 미검증 | [실기] 필요 |
| VS Code 로 세션 열기 | [소스] | 폴더 창 → 1.2초 뒤 세션 딥링크. 맥은 그 창이 앞에 온 것을 확인한 뒤 보내지만 Windows 는 시간만 기다린다. 작업 폴더를 모르면 딥링크를 보내지 않는다. 같은 탭이 살아나는지는 [실기] 필요 |
| 독립 검토 | 2026-11-03 | 코드를 쓰지 않은 세션이 검토해 HIGH 2 · MEDIUM 5 · LOW 5. 맥 사용자 settings.json 을 깨는 경로는 없었다. 고친 것과 남긴 것은 이 문서에 반영했다 |

## 1차에서 뺀 것

| 뺀 것 | 이유 |
| --- | --- |
| Claude 앱 사이드바로 바로 가기 | 맥은 접근성 API 로 행을 누른다. Windows 는 UI Automation 으로 다시 짜야 한다. 지금은 VS Code 로 보낸다 |
| Codex 롤아웃만으로 task 찾기 | 훅을 승인하지 않은 Codex 도 보여 주는 맥 기능. Windows 의 Codex 기록 위치를 확인한 뒤 옮긴다 |
| Claude 앱 · 터미널 세션을 그 앱으로 보내기 | 맥은 세션이 시작된 곳 → 설치된 앱 순서로 보낸다. 지금은 전부 VS Code 로 간다 |
| Codex 완료 보정 · 밖에서 읽음 판정 · 창 제목으로 읽음 · 트랜스크립트에서 말풍선 문장 읽기 | 맥에 있는 정밀 기능이다. 없으면 Codex 세션이 Stop 을 놓쳤을 때 완료 대신 10분 뒤 회색이 되고, 레토를 안 거치고 읽은 세션도 배지에 남는다. 「모두 읽음」으로 지운다 |
| 스킨 · 끌 때 달리는 그림 · 자는 그림 교체 | 상태를 알리는 일과 무관하다 |
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
8. 처음 켤 때 단일 실행 잠금이 false 로 와서 레토가 아무 표시 없이 꺼지지 않는가 — GitHub Actions 러너에서는 다른 레토가 없는데도 false 였다(2026-11-03). 실제 PC 에서도 그러면 「켜도 아무것도 안 뜬다」가 된다

## 돌리는 법

```sh
cd windows && npm install
npm start                                  # 맥에서도 뜬다 — ~/.claude/retto-pet 를 읽는다
npm test                                   # 상태 판정 · 연동 확인
npx electron-builder --win zip --x64 --arm64   # ../dist/windows/ 에 zip
```

Claude Code 안에서 돌리면 `ELECTRON_RUN_AS_NODE=1` 이 걸려 있어 창이 안 뜬다. `env -u ELECTRON_RUN_AS_NODE npm start`.
