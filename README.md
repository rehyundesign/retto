# 레토 (Retto)
> **Retto** · luxia yoon 의 랙돌 고양이
> 만든 사람 luxia yoon · ydh3600@mail.com · [linkedin.com/in/donghyunyoon](https://www.linkedin.com/in/donghyunyoon/)
> 영어 표기는 `t` 를 둘 쓴다 — Reto 가 아니라 **Retto**.
> 앱에서는 발바닥 메뉴 → **Retto 정보** 에서 같은 내용을 볼 수 있다(메일 주소 복사 버튼 포함).

Claude Code와 Codex 상태에 맞춰 움직이는 랙돌 고양이. 앱 하나가 두 제품의 세션을 함께 추적한다.
원래는 Codex 의 `hatch-pet` 스킬로 스프라이트를 만들고
`~/Documents/Codex/.../work` 에서 굴리던 작업이고, 2026-08-27 부터 이 레포에서 관리한다.

```
apps/retto-pet/
├── assets/   스프라이트 아틀라스·손글씨 폰트·아이콘
├── macos/    데스크탑 오버레이 (Swift, 모든 Space·전체화면 위에 상주)
├── hook/     Claude Code·Codex 훅과 설치기
├── scripts/  훅 설치 래퍼
└── tools/    에셋 검사·교정 도구
```

VS Code 사이드바 확장은 2026-08-27 에 은퇴시켰다. 오버레이 하나로 정리하면서 확장이 하던
훅 설치를 `hook/install.cjs` 로 독립시켰다.

Claude와 Codex용 앱을 따로 두지 않는다. 설치기가 `~/.claude/settings.json`과
`~/.codex/hooks.json`에 같은 상태 브리지를 등록하고, 두 제품의 이벤트를
`~/.claude/retto-pet/sessions.json` 하나로 모은다. Codex 키에는 `codex:` 접두사를 붙여
두 제품에서 같은 세션 ID가 나와도 충돌하지 않게 한다.

Codex 훅은 그 쪽이 실제로 부르는 아홉 개(`SessionStart` `UserPromptSubmit` `PreToolUse`
`PermissionRequest` `PostToolUse` `SubagentStart` `SubagentStop` `Stop` `SessionEnd`)만 건다 —
Codex 바이너리에 박힌 `HookEventName` 목록과 훅 입력 JSON 스키마를 읽고 맞춘 것이다.
Claude 전용 이벤트(`Notification` `Elicitation` `TaskCompleted` 등)를 섞으면 훅 설정 전체가 거부될 수 있다.
Codex 는 `cwd` `session_id` `transcript_path` `tool_name` `tool_response` 를 Claude 와 같은 이름으로 준다.


Codex 는 등록된 훅을 바로 돌리지 않는다. 훅 설정이 새로 생기거나 바뀌면 시작할 때
승인 화면(`startup_hooks_review`)을 띄우고, 승인한 내용을 `trusted_hash` 로 기억한다.
그래서 설치 직후에는 Codex 를 한 번 다시 켜서 승인해 줘야 세션이 레토에게 보인다 —
설치기가 훅을 다시 쓸 때마다 해시가 바뀌므로 승인도 다시 물어본다.

### 두 트랜스크립트는 모양이 다르다

말풍선 본문과 이름표는 훅이 아니라 트랜스크립트에서 온다. 그런데 같은 것을 서로 다르게 적는다.

| | Claude Code | Codex |
| --- | --- | --- |
| 말 | `{"type":"assistant","message":{"content":[{"type":"text"}]}}` | `{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text"}]}}` |
| 이름 | 트랜스크립트 안 `custom-title` → `ai-title` | 파일 밖 `~/.codex/session_index.jsonl` 의 `thread_name` |

한쪽 모양만 읽으면 그 클라이언트 세션의 말풍선이 통째로 비어 "생각중" 에 머문다. 그래서 훅의
`assistantTextIn` 과 오버레이의 `assistantText(in:)` 이 두 모양을 함께 받는다(같은 규칙, 두 언어).
Codex 의 `event_msg:agent_message` 에도 같은 문장이 있지만 도구 결과까지 섞여 들어와 쓰지 않는다.

이름은 Codex 롤아웃 안에 아예 없다. `session_index.jsonl` 을 안 읽으면 이름표가 첫 프롬프트로
떨어져 레토가 내 말을 되돌려 주는 것처럼 읽힌다. 이름이 붙지 않은 스레드는 그대로 프롬프트를 쓴다.

## macOS 오버레이

```sh
apps/retto-pet/macos/scripts/build.sh            # 빌드 + 셀프 테스트 + dist/ 산출
apps/retto-pet/macos/scripts/build.sh --install  # 위 + ~/Applications 설치 후 재실행
```

빌드 중 `--self-test` 가 자동으로 돌아 아틀라스 크기, 상태 7종, 딥링크, 배율 프리셋,
레이아웃 기준값을 검사한다. 하나라도 어긋나면 빌드가 실패한다.

배율별 레이아웃을 화면 없이 확인할 때:

```sh
"apps/retto-pet/macos/build/Retto Claude Pet.app/Contents/MacOS/RetoClaudePet" \
  --render-preview /tmp/reto-scale.png
```

### 몸과 말풍선은 따로 자란다

예전에는 창 크기에서 뽑은 배율 하나를 몸·리본·글자에 전부 곱했다. 그래서 크기를 줄이면
상태 말풍선의 글자까지 같이 줄어 읽을 수 없었다. 지금은 `petLayout(scale:)` 이 두 배율을 나눠 쓴다.

- **몸**: 고른 배율(`35% ~ 140%`)을 그대로 따른다
- **리본·글자**: `chromeScaleFloor`(현재 `1.0`) 아래로는 줄지 않는다
- **배지**: 숫자만 읽히면 되므로 더 낮은 `badgeScaleFloor`(`0.7`) 를 쓴다
- **창**: 몸 폭과 리본 최소 폭 중 넓은 쪽에 맞춘다. 그래서 작은 배율에서는 창이 몸보다 넓고,
  남는 여백은 `hitTest` 가 클릭을 통과시킨다

배율 1 에서의 창·몸·리본 좌표는 예전 값(`306×372`, 몸 `252`, 리본 `280×75`)을 그대로 유지하며,
셀프 테스트가 이 기준값과 작은 배율의 분리 동작을 함께 검사한다.

### 배지를 누르면 기다리는 세션이 나온다

오른쪽 어깨의 빨간 배지는 `attention` 세션 수(권한 대기·실패·완료)를 센다. 여럿을 대표하는 숫자인데
클릭은 선택된 한 세션만 열었고, 나머지로 가려면 메뉴 막대를 거쳐야 했다. 지금은 `petClickTarget` 이
누른 지점을 배지·몸통으로 갈라준다.

- **배지**: 기다리는 세션이 하나면 바로 열고, 여럿이면 그 목록을 배지 아래 띄운다. 골라도 고정(pin)은
  바뀌지 않는다 — 여는 것과 따라가는 것은 다른 일이다
- **몸통·리본**: 예전대로 선택된 세션을 딥링크로 연다
- **배지가 없을 때**(`attentionCount == 0`)는 같은 자리도 몸통으로 간다

`badgeRect` 는 `petLayout` 이 창 안쪽으로 가둬 계산하고 그리기와 클릭 판정이 그 값을 함께 쓴다.
셀프 테스트가 배율 3종에서 배지가 창을 벗어나지 않고 리본을 덮지 않는지, 클릭이 옳게 갈라지는지 본다.

### 말풍선 (동물의 숲 대화창)

```
      ╭────────────────────╮
 ╭────┤ 레토 앱          │  ← 이름표: 세션 타이틀(12자), 색은 상태
 │    ╰────────────────────╯
 │  그 파란 숫자의 정체를 코드에서 확인하고
 │  맞췄어. Claude Code 확장이 세션 목록…
 ╰──────────────▼─────────────╯   ← 잘렸을 때만 나오는 삼각형
```

- **이름표**: 세션 타이틀(열두 글자 초과분은 `…`). 배경색이 상태를 말하므로 대문자 상태 줄이 필요없다.
  색은 배경·글자를 `StatusTone` 한 쌍으로 묶어 지정값을 그대로 쓴다 —
  `toneWorking` `#73DF5D`/`#0A5225`(진행 중) · `toneNeedsYou` `#0885FE`/`#FFFFFF`(내 답 대기) ·
  `toneDone` `#FF7009`/`#FFFFFF`(완료) · `toneFailed` `#F82D39`/`#FFF499`(문제) ·
  `toneQuiet` `#848484`/`#FFFFFF`(쉬는 중). 배지도 같은 쌍을 쓴다.

  세션 타이틀은 Claude Code 가 트랜스크립트에 적어 두는 값이다 — `custom-title`(직접 바꾼 이름) →
  `ai-title`(Claude 가 붙인 이름) 순. 훅이 `transcript_path` 의 끝 256KB 만 읽어 최신값을 집는다.
  예전에는 `displayTitle`(보낸 프롬프트 앞 80자)이 떠서 자기 말이 되돌아오는 것처럼 읽혔다.
- **윤곽**: 사용자가 Figma 에서 그린 벡터(`Frame 19.svg`)의 좌표를 그대로 옮긴 뒤 다듬어 쓴다.
  원본에는 곡선 사이에 짧은 직선 조각이 끼어 있어 접선이 꺾이는데(최대 꺾임 149°), 윤곽을 둘레 기준
  160점으로 다시 뽑아 이동평균 6회를 돌리고 Catmull-Rom 으로 이어 붙이면 14° 로 떨어진다.
  위아래로 두 번 부풀고 좌우에 허리가 들어간 실루엣(폭이 99.8% → 94.8% → 92.9%)은 그대로 남는다.
  `--shape-report` 로 높이별 폭과 최대 꺾임을 이미지 없이 확인할 수 있다.
- **타이핑**: 새 멘트가 오면 한 글자씩 찍는다(0.018초/자). 다 찍히면 타이머가 스스로 멈춘다.
- **본문**: 훅이 담아 둔 `lastAssistantMessage`(180자)에서 마크다운 기호를 걷어낸 것. 없으면 레토가 하는 말.
- **삼각형**: 본문이 잘렸을 때만. 마우스를 0.3초 올려두면 말풍선이 아래로 펼쳐진다(`ribbonBodyHeight`).
  펼침은 창의 위 변을 고정하고 아래로만 늘려서 레토가 화면에서 움직이지 않게 한다.

### 말풍선에 쓰는 말

Codex 의 `hatch-pet` 규격은 스프라이트와 16방향 시선까지만 정의한다. 상태 말풍선은 이 오버레이만의
설계다(에디터 밖에 떠 있고 세션이 여러 개라 어느 세션인지 말할 필요가 있다).

- 평소: 레토가 하는 말 (`animationCatalog` 의 `title`)
- `waiting`·`failed`: 그 세션의 제목 — 지금 당신을 기다리는 게 어느 세션인지 알아야 하므로
- 아래줄: 프로젝트 · 고정/자동 · 세션 수 (항상)

세션 제목은 훅이 받은 사용자 프롬프트 앞 80자(`vscode/scripts/hook.cjs`)다. 그래서 평상시에 띄우면
레토가 아니라 자기 말이 되돌아오는 것처럼 읽힌다.

### 클릭과 배지 — 코덱스 펫 규격

코덱스 펫의 실제 구현(`/Applications/ChatGPT.app/Contents/Resources/app.asar` 안
`webview/assets/avatar-mascot-button-*.js`, `codex-pet-assets-*.js`)을 읽고 맞췄다.

펫 본체 컴포넌트에는 `onClick` 이 없다. 클릭은 그 위 드래그 레이어의 pointerup 에서
"움직이지 않았으면 클릭"으로 판정한다(`avatar-overlay-native-page-*.js`).

```js
// 떼는 순간, 4px 넘게 움직이지 않았다면
t && !i && (Z(ACTION_MASCOT_CLICKED, SOURCE_MASCOT), F && N != null ? Ue?.() : ne())
// onMascotClick:
function Ki(){ H.dispatchMessage(`open-current-main-window`, {focusComposer: true, stealFocus: true, …}) }
```

즉 코덱스 펫 클릭은 **현재 메인 창을 띄우고 입력창에 포커스**한다. 새 창을 만들지는 않는다.
음성 세션이 살아 있으면 그 세션 locator 로 이동한다.

| | 코덱스 펫 | 레토 오버레이 |
|---|---|---|
| 몸통 클릭 | `open-current-main-window` + 입력창 포커스 | 점프 반응 + 그 세션의 VS Code 창을 앞으로 (⌥ 클릭이면 새 패널) |
| 반응 계기 | 마우스를 올리면 `jumping` | 클릭하면 `jumping` |
| 시선 추적 | `idle`·`running`·`waving` 에서만 | 같음 |
| 세션 고르기 | 배지 클릭 → 알림 스택 | 말풍선 클릭, 배지 클릭 → 기다리는 세션 목록 |
| 배지 색 | 알림 등급별(warning·danger·success·info) | 기다리는 세션의 상태색 |
| 배지 위치 | 네 모서리로 드래그, 4px 임계값, 저장 | 같음 (`RetoClaudePetBadgeCorner`) |
| 배지 모션 | 등장 `0.7→1` 스프링, hover `1.06`, tap `0.94` | 같음 (60fps 타이머로 근사) |
| 배지 재질 | `backdrop-blur-xl` + `border-white/85` | 흰 테두리·그림자만, 실제 블러는 없음 |
| 드래그 | 끄는 방향으로 달리고(행 1·2), 던지면 튕김 | 같음. 던져도 튕기지는 않는다 |

### 어느 세션을 보여줄지

Claude Code 확장은 세션 상태를 셋으로만 보고하고, 사이드바 아이콘의 파란 숫자는 그중 하나의 개수다.

```js
// state: J0(["idle","running","waiting_input"])
updateSessionListBadge($) {
  let Q = $.filter(J => J.state === "waiting_input").length
  this.sessionListView.badge = Q > 0 ? { tooltip: `${Q} session… waiting for input`, value: Q } : { value: 0 }
}
```

`waiting_input` 은 권한·질문 대기만이 아니라 턴이 끝나 답을 기다리는 상태까지 포함한다. 훅이 만드는
우리 상태로는 `waiting`·`failed`·`waving` 세 가지가 그 묶음이고(`needsInputStates`), 이 셋을
`running`·`review` 보다 위에 둔다. 예전에는 `waving`(답변 완료)이 `running` 아래여서 파란 숫자가
떠도 작업 중인 세션에 가려졌다.

### 몸보다 글씨를 따로 깎을 때

말풍선 배율(`chromeScale`)은 프리셋 두 점(35%·50%)에 맞춘 직선이라, 한 프리셋만 손보려고 기울기를
건드리면 일곱 개가 전부 따라 움직인다. 그래서 프리셋 하나의 글자만 줄일 때는 배율이 아니라
`chromeTextDeltas` 에 pt 를 적는다. 말풍선 치수·여백은 그대로 두고 이름표와 본문 글자 크기에만 더한다.

- 50%: `-1.5pt` — 본문 19.6→18.1, 이름표 18.0→16.5. 몸이 126pt 인데 글자가 100% 때와 비슷해 보였다

이름표 폭 상한은 글자 폭으로 재므로 알약도 같이 줄고, 셀프 테스트가 두 줄 규칙이 세 줄로 늘지 않는지
확인한다 — 글자만 작아지고 칸은 그대로여서 줄 수가 바뀌면 말풍선이 다른 물건으로 보인다.

### 세션으로 데려가는 방법

딥링크 `vscode://anthropic.claude-code/open?session=<id>` 는 확장의 URI 핸들러에서
`claude-vscode.primaryEditor.open` → `createPanel()` 로 들어간다.

```js
if ($) { let V = this.sessionPanels.get($); if (V) { V.reveal(); return } }
… createWebviewPanel("claudeVSCodePanel", "Claude Code", …)   // 없으면 새 패널
```

`sessionPanels` 에 등록되는 건 에디터 패널 세션뿐이다. 사이드바 뷰(`resolveWebviewView`)의
세션 콜백은 `updateSessionState(...)` 만 부르고 그 맵을 건드리지 않으며, 맵 자체가 창(확장 호스트)마다
따로다. 그래서 사이드바에서 돌던 세션이나 다른 창의 세션은 딥링크로 되살릴 수 없고, 같은 대화가
새 패널로 한 번 더 열린다. 확장이 노출하는 URI 는 `/open` 과 `/install-plugin` 둘뿐이라 이걸
URI 로 우회할 방법은 없다.

그래서 순서를 둘로 나눈다.

1. `NSWorkspace.open([cwd], withApplicationAt: VSCode)` 로 **그 세션의 작업 폴더 창을 앞으로** 보낸다.
   이미 그 폴더를 열어 둔 창이 있으면 VS Code 가 그 창을 앞으로 가져오고 새 창을 만들지 않는다.
2. 창이 자리 잡은 뒤(0.45초, 앱을 새로 띄웠으면 2.5초) 딥링크를 보낸다. 이제 그 URI 를 받는 창이
   세션을 가진 창이므로 `sessionPanels.get(id)` 이 맞아 `V.reveal()` 로 **그 탭이 되살아난다**.

창을 먼저 보내지 않으면 URI 가 마지막으로 활성화된 창에 배달되고, 그 창에는 그 세션이 없으니
같은 대화가 새 패널로 한 번 더 열린다. 이게 "클릭하면 새 섹션이 열린다"의 정체였다.
`claudeCode.preferredLocation` 이 `sidebar` 인 경우에는 2단계가 탭을 만들기만 하므로,
창만 앞으로 보내려면 ⌥ 를 누른 채 클릭한다.

### VS Code 와 Claude 앱을 같이 쓴다

훅은 VS Code 것이 아니다. `~/.claude/settings.json`(유저 전역)에 들어가고 `~/.claude/retto-pet/hook.cjs`
를 절대경로 node 로 부른다. Claude 데스크탑 앱도 Claude Code 세션을 `settingSources: ["user","project","local"]`
로 띄우므로(앱 번들 `app.asar` 에서 확인) 같은 훅이 그대로 돈다. VS Code 확장은 그 훅을 설치해 주는
버튼일 뿐이라, 설치가 끝났으면 확장 없이도 상태 추적·말풍선·배지가 다 동작한다.

갈리는 건 **클릭했을 때 어디로 데려가는가** 하나다. 그래서 훅이 세션마다 어디서 왔는지 적는다.
훅은 Claude Code 프로세스의 자식이라 `CLAUDE_CODE_ENTRYPOINT` 를 그대로 물려받는다.

| `CLAUDE_CODE_ENTRYPOINT` | `client` | 어디로 |
|---|---|---|
| `claude-vscode` | `vscode` | VS Code |
| `claude-desktop` | `claude` | Claude 앱 |
| 그 밖의 값(`sdk-ts` 등) | `claude` | Claude 앱 |
| `cli` · 빈 값 | `cli` · `` | VS Code |

`claude-desktop` 은 **실측값**이다. 앱 번들(`app.asar`)만 읽으면 SDK 기본값 `sdk-ts` 로 떨어질 것처럼
보이는데, 실제로 데스크탑 앱에서 세션을 돌려 보면 이 값을 박는다. 코드를 읽어 짐작한 값과 달랐다.

`CLAUDE_CODE_EXECPATH` 에 `.vscode` 가 있는지도 잠깐 봤는데, 그건 Cursor 같은 포크를 가려내려던
것이었다. 포크를 빼기로 하면서 근거가 사라졌고 판별만 흐렸다. 이름으로 확실히 가려지는 건 VS Code 뿐이라,
모르는 호스트는 VS Code 가 아닌 쪽으로 본다.

터미널(`cli`)은 `client` 로는 구분해 두되 여는 건 VS Code 로 보낸다. 돌아가는 터미널 세션을 되살릴
방법이 없어서다 — `claude --resume` 은 그 세션으로 가는 게 아니라 프로세스를 하나 더 만드는 일이다.

값을 못 읽은 훅 한 번이 이미 알아낸 값을 지우면 그 세션 클릭이 그때부터 엉뚱한 앱으로 가므로,
빈 값은 이전 값을 덮지 않는다. 반대로 같은 세션이 VS Code 와 Claude 앱 양쪽에 열리면(딥링크로 그렇게 된다)
마지막에 쓴 쪽이 이긴다 — 지금 그 세션이 실제로 사는 곳이 마지막에 쓴 쪽이므로 그게 맞다.

### 두 앱은 세션을 다르게 굴린다

VS Code 는 세션마다 claude 프로세스를 붙들고 있다. Claude 앱은 **턴마다 새로 띄웠다 내린다** —
`ps` 에 Claude 앱이 띄운 claude 프로세스가 하나도 안 잡히는 게 그 증거다. 여기서 두 가지가 새어 나왔다.

**하나. `SessionStart` 가 하던 일을 덮었다.** `Stop` 2초 뒤에 `SessionStart(source=resume)` 이 또 오고,
훅이 그걸 `jumping` 으로 받았다. 우선순위가 `jumping` 20 < `running` 40 < `waving` 55 라 그 세션이
목록 바닥으로 내려가고, 완료 배지는 2초 만에 사라지고 다음 턴의 "생각중" 도 곧바로 덮였다.
클로드 앱에서 레토가 멍하니 있던 이유가 이것이다.

`SessionStart` 는 "이 세션에 프로세스가 붙었다" 는 뜻이지 "상태가 바뀌었다" 가 아니다. 그래서 최근
2분 안에 소식이 있던 세션에는 상태도 **시각도** 건드리지 않는다(`isLiveRestart`). 시각까지 묶은 건,
그걸 밀면 이미 읽은 완료 알림이 안 읽음으로 되살아나기 때문이다 — 읽음 판정이 이 시각을 본다.
진짜 오랜만에 되살린 세션과 이미 닫힌 세션만 예전처럼 `jumping` 으로 반긴다.

**둘. 유령 세션.** 창을 띄우거나 폴더를 훑을 때마다 프롬프트 한 번 없는 세션이 1초짜리로 났다
사라진다(실측에서 한 번에 세 개씩). 그대로 두면 레지스트리가 하루치 껍데기로 찬다. 사람이 말을 건 적도
Claude 가 답한 적도 없이 끝난 세션은 기록에 남기지 않고, 이미 쌓인 것도 다음 훅이 돌 때 쓸어낸다
(`isGhost`). 말을 건 적이 있는지는 `UserPromptSubmit` 때 찍는 `promptedAt` 하나로 판단한다.

### 어디로 데려갈지 고르기

오버레이는 `client` 값으로 앱을 고른다. 메뉴바 **발바닥 → 세션 열 곳**에서 `자동`(기본)·`VS Code`·`Claude 앱`.
자동이 기본인 이유는 둘을 섞어 쓰면 고정값이 반드시 절반을 틀리기 때문이다 — 배지에 셋이 떠 있는데
하나는 VS Code, 하나는 Claude 앱이면 고정으로는 답이 없다. 고정은 자동이 잘못 짚을 때의 탈출구다.

| | VS Code | Claude 앱 |
|---|---|---|
| 딥링크 | `vscode://anthropic.claude-code/open?session=` | `claude://resume?session=` |
| 창 먼저 앞으로 | 필요 (`needsWindowFocusFirst`) — 안 하면 새 패널이 생긴다 | 불필요 — 세션이 창 하나에 모여 있다 |
| 창을 못 찾으면 | 앱만 앞으로 보내고 딥링크는 접는다 | 해당 없음 |

`client` 를 아직 안 적은 옛 세션과 `cli` 는 VS Code 로 간다 — 지금까지의 동작 그대로다.

`claude://resume` 은 앱의 URL 핸들러에서 `importCliSession(sessionId)` 으로 들어간다. 이름이 import 라
VS Code 쪽 `reveal()`(살아 있는 탭 되살리기)과 다른 것 아닌가 걱정했는데, 실제로 눌러 보면 그 세션의
대화가 그대로 열린다. 다만 **앱이 안 떠 있을 때 보낸 첫 URL 은 조용히 버려진다** — 앱이 뜨는 중에
배달되기 때문이다. 그래서 `focusHostApp` 이 앱을 먼저 앞으로 보내고 2.5초(이미 떠 있으면 0.45초)
기다렸다가 딥링크를 보낸다. 이 대기는 원래 VS Code 때문에 넣은 것인데 Claude 앱에도 그대로 필요했다.

의도적으로 다른 세 가지가 있다.

- **반응을 hover 가 아니라 클릭에 걸었다.** 코덱스 펫은 앱 창 안에 있어서 hover 를 반응에 쓸 수 있지만,
  이 오버레이는 창이 레토만 한 크기다. hover 를 점프에 쓰면 마우스를 올릴 때마다 시선 추적을 잃는다.
- **끌 때는 코덱스 펫처럼 끌리는 방향으로 달린다**(아틀라스 행 1·2). 방향은 직전 마우스 위치와의
  차이로 정하고 2pt 이하 떨림은 무시한다 — 안 그러면 좌우가 매 프레임 뒤집힌다. 끄는 동안에는
  시선 추적을 쉬고, 손을 놓으면 원래 동작으로 돌아간다. 원본 행 2 는 얼굴이 칸 밖으로 잘려 있어
  행 1 을 좌우로 뒤집어 다시 만들었다.
- **배지 뒤 블러는 구현하지 않았다.** `NSVisualEffectView` 를 투명 창에 얹어야 해서, 흰 테두리와
  그림자로 유리질 느낌만 냈다.

## 소스 구성

`macos/Sources` 는 2026-08-27 에 2,039줄 한 파일에서 아홉으로 쪼갰다. 두 세션이 같은 파일을
동시에 고치다 함수가 날아간 일이 있어서, 충돌 면적을 줄이는 게 목적이었다.

| 파일 | 줄 | 맡은 일 |
|---|---:|---|
| `Uninstall.swift` | 73 | 훅 등록·상태 파일·앱 되돌리기 |
| `main.swift` | 87 | 실행 진입점, 진단 플래그(`--self-test`·`--shape-report`·`--render-preview`) |
| `OpenTarget.swift` | 97 | 세션을 어디서 열지(VS Code·Claude 앱·Codex)와 딥링크 |
| `Tones.swift` | 126 | 뜻 단위 색 넷과 상태별 애니메이션 |
| `Bubble.swift` | 128 | 동물의 숲 윤곽(Figma 벡터 + 다듬기) |
| `ClaudeAppNavigator.swift` | 194 | Claude 앱 안에서 세션 찾아가기 |
| `Geometry.swift` | 260 | 몸/말풍선 크기·자리 계산 |
| `Sessions.swift` | 332 | 훅이 적은 상태 읽기, 우선순위, 두 모양의 트랜스크립트 읽기 |
| `SelfTest.swift` | 436 | 자체 검사, 배율별 미리보기 |
| `PetView.swift` | 961 | 그리기와 마우스 |
| `AppDelegate.swift` | 1,254 | 창·메뉴·세션 감시, 클릭을 동작으로 |

최상단 선언만 `internal` 로 열고 멤버의 `private` 는 그대로 뒀다. `build.sh` 는 `Sources/*.swift`
전체를 넘긴다.

## 검사

```sh
apps/retto-pet/scripts/check.sh    # 빌드 + 자체 검사 + Claude·Codex 훅 테스트
```

`.githooks/pre-commit` 이 `apps/retto-pet/` 를 건드린 커밋에서만 이걸 돌린다
(`git config core.hooksPath .githooks`). 다른 작업 커밋은 그대로 지나간다.
급하면 `--no-verify`.

## 말풍선이 지금 하는 말을 따라가는 법

훅은 도구를 부를 때만 돈다. 그래서 도구 없이 긴 글을 쓰는 동안에는 말풍선이 멈춰 있었다.
이제 훅이 `transcriptPath` 를 적어 주고, 앱이 표시 중인 세션의 그 파일만 직접 들여다본다
(`TranscriptReader`). 끝 512KB 만 읽고, 크기와 수정 시각이 그대로면 다시 읽지 않는다.

## 잘 때

두 가지로 나뉜다. 둘 다 자는 행(행 11)을 0.46초 간격으로 돌려 약 2.76초에 한 번 숨 쉰다.

**전부 조용한 채로 10분** — 알릴 것이 아무것도 없다.

- 이름표에 세션 이름 대신 **레토**
- 말풍선에 **Zzz…**
- 색은 회색

**다 끝났는데 아무도 보러 오지 않은 채 30분** — 기다리다 졸았다.

- 이름표·말풍선·배지는 **그대로 둔다**. 알릴 것이 남아 있기 때문이다
- 그림만 잠든다

깨우는 것은 훅 한 번이다. 어느 세션이든 다시 움직이면 즉시 그 세션으로 돌아간다.

### 자는 행은 어떻게 만들었나

행 11에는 레토 사진을 참고해 새로 만든 누운 수면 그림 여섯 장을 넣었다. 얼굴·앞발·꼬리
아랫부분과 바닥선은 고정하고, 등과 흉곽의 높이만 `낮음 → 들숨 → 최고점 → 날숨 → 낮음`으로
변한다. 프레임 바닥선은 같은 위치에 남아 좌우로 흔들리지 않는다.

```sh
swift tools/sprite-sleep.swift assets/spritesheet.webp out.png --strip sleeping-row.png
cwebp -lossless -exact out.png -o assets/spritesheet.webp
```

처음 칸과 마지막 칸이 자연스럽게 이어져 조용히 엎드려 자는 한 호흡으로 반복된다.

## 남에게 보낼 때

`macos/scripts/build.sh` 가 배포 묶음을 만든다 — `dist/Retto-Claude-Pet-<버전>.zip` 안에
앱, `설치.command`, `먼저-읽어주세요.txt` 셋이 들어간다. 앱만 보내면 받는 쪽은
"손상되었습니다" 만 보고 끝난다(애드혹 서명이라 격리 딱지를 떼야 한다). 설치기가 그 일을 한다.

받는 쪽에서 확인한 것들.

- **세션이 하나도 없는 첫 실행** — 회색으로 잠든 채 "Claude Code 를 켜면 여기서 알려줄게"
  라고 말한다. 예전에는 화면을 갱신하지 않아서 이름표에 `Claude Code` 만 걸린 고양이가
  떠 있었고, 고장인지 아닌지 알 수 없었다
- **VS Code 가 없는 사람** — 자동으로 고른 앱이 깔려 있지 않으면 다른 쪽으로 보낸다.
  예전에는 없는 앱을 열려다 삐 소리만 났다. 메뉴에서 직접 고른 경우에는 그 뜻을 지킨다
- **제거** — 발바닥 메뉴의 「레토 제거…」가 훅 등록·상태 파일·자동 실행·앱 설정을 정리하고
  앱을 휴지통으로 옮긴다. 확인 창의 기본 단추는 취소다

## 읽음은 어떻게 판정하나

배지는 "답이 끝났는데 아직 안 본" 세션을 센다. 지우는 길은 셋이다.

- 배지·몸통·말풍선을 눌러 그 세션에 다녀오면 읽음
- 발바닥 메뉴 **완료 표시 지우기** — 레토를 거치지 않고 세션에 직접 다녀왔을 때
- 그 세션에 다시 말을 걸면(작업 중이 되면) 배지 집합에서 빠진다

시간이 지나면 저절로 조용해지게 하지는 않는다. 돌려놓고 한참 뒤에 돌아오는 것이
배지의 쓸모이기 때문이다.

`~/.claude` 를 뒤져 봤지만 **"사용자가 세션을 봤다" 는 기록은 어디에도 없다.** 남는 흔적은
트랜스크립트의 접근 시각(atime) 하나인데, 재보니 Claude 앱도 VS Code 도 세션을 열 때
그 파일을 다시 읽지 않는다(자체 캐시에서 불러온다). 그래서 그 규칙으로 잡히는 것은
CLI 로 `claude --resume` 한 경우 정도다. 앱이 말풍선·이름을 읽을 때는 `utimensat` 으로
atime 을 되돌려, 자기가 자기를 읽음 처리하지 않게 한다.

## 훅 — 레토가 상태를 아는 길

```
Claude Code 이벤트
   ↓  ~/.claude/settings.json 에 등록된 명령
node ~/.claude/retto-pet/hook.cjs <상태>
   ↓
~/.claude/retto-pet/sessions.json
   ↓  0.25초마다 읽음
레토 (그림·색·말풍선)
```

설치는 두 가지 일을 한다 — `hook.cjs` 를 `~/.claude/retto-pet/` 로 복사하고,
`settings.json` 에 이벤트 17개를 등록한다(다른 훅은 건드리지 않고, 고치기 전에 백업하고 최근 5개만 남긴다).

```sh
apps/retto-pet/scripts/install-hooks.sh              # 설치·갱신
apps/retto-pet/scripts/install-hooks.sh --uninstall  # 제거
cd apps/retto-pet/hook && npm test                   # 훅·설치기 테스트 10개
```

`build.sh --install` 이 앱을 깔 때 훅도 함께 갱신한다. 발바닥 메뉴에 같은 항목을 두었다가
걷어냈다 — 설치 경로 둘이 이미 하는 일이라 누를 일이 없었다. 설정에 박는 node 경로는 버전이 든 실경로(`.../Cellar/node/26.6.0/...`)
대신 `/opt/homebrew/bin/node` 처럼 안정적인 자리를 고른다 — brew 로 node 를 올려도 훅이 죽지 않게.

## 지난 구조

```sh
cd apps/retto-pet/vscode
npm install
npm test              # 훅 설치·제거 로직
npm run package       # 에셋 동기화 후 ../dist 에 vsix
```

`media/spritesheet.webp` 와 `media/icon.png` 는 `assets/` 에서 복사해 오는 파일이라 git 에 넣지 않는다.
`npm run sync-assets` 가 복사하고, `npm run package` 가 먼저 그걸 호출한다.

## 에셋 교정 기록

`tools/sprite-scale.swift` 는 아틀라스 셀마다 알파 면적의 제곱근을 재서 "같은 고양이를 얼마나
확대해 그렸는지"를 비교한다.

- 2026-08-27: 시선 행 10(`180°~337.5°`) 8칸이 행 9 대비 약 0.70 배로 작게 생성돼 있었다.
  마우스를 아래·왼쪽으로 옮기면 레토가 훅 작아지던 원인. 행 중앙값을 맞추는 배율로 교정했다.

  ```sh
  swift apps/retto-pet/tools/sprite-scale.swift measure apps/retto-pet/assets/spritesheet.webp
  swift apps/retto-pet/tools/sprite-scale.swift apply \
    apps/retto-pet/assets/spritesheet.webp /tmp/corrected.png 10=1.274
  cwebp -lossless -exact -z 9 /tmp/corrected.png -o apps/retto-pet/assets/spritesheet.webp
  ```

  교정 후 행 9 중앙값 `136.2`, 행 10 중앙값 `136.5`. 확대는 콘텐츠 바닥 중앙을 고정점으로 해서
  발이 같은 선에 남는다. 아틀라스 규격(당시 `1536×2288`, 8×11 그리드, 무손실 VP8L)은 그대로다.

`hatch-pet` 스킬(Apache-2.0)은 아직 `~/.codex/skills/hatch-pet` 에 있다. Codex 펫으로 쓰는
`~/.codex/pets/reto/spritesheet.webp` 는 위 교정이 반영되지 않은 사본이다.
