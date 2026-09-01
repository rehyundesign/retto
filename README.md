# Retto

A desk pet for [Claude Code](https://claude.com/claude-code) and Codex — a macOS overlay cat
that sits above every Space and full-screen app. It turns green while your agents work, blue
when one needs your answer, orange when a turn finished and you haven't looked yet, red when
something failed, and it takes you to that session when you click. One app watches sessions
coming from VS Code, the Claude desktop app, the terminal, and Codex at once.

Requires an Apple Silicon Mac (macOS 13 or later) and Node.js. Two ways to install:

```sh
git clone https://github.com/rehyundesign/retto.git
cd retto && macos/scripts/build.sh --install
```

or drag `Retto.app` out of the DMG on the [releases page](../../releases). A locally built app
skips Gatekeeper entirely; the DMG is unsigned, so the first launch needs one trip through
System Settings → Privacy & Security → "Open Anyway".

**The Korean sections below, and the design notes under [`docs/`](docs/), are in Korean** — that
is where the reasoning behind each decision lives, so a translation would lose most of the point.
MIT licensed. Not affiliated with Anthropic or OpenAI; Claude and Codex are the products this
tool watches, not its makers.

---

# 레토 (Retto)
> **Retto** · luxia yoon 의 랙돌 고양이
> 만든 사람 luxia yoon · ydh3600@mail.com · [linkedin.com/in/donghyunyoon](https://www.linkedin.com/in/donghyunyoon/)
> 영어 표기는 `t` 를 둘 쓴다 — Reto 가 아니라 **Retto**.
> 앱에서는 발바닥 메뉴 → **Retto 정보** 에서 같은 내용을 볼 수 있다(메일 주소 복사 버튼 포함).

Claude Code와 Codex 상태에 맞춰 움직이는 랙돌 고양이. 앱 하나가 두 제품의 세션을 함께 추적한다.
원래는 Codex 의 `hatch-pet` 스킬로 스프라이트를 만들고
`~/Documents/Codex/.../work` 에서 굴리던 작업이고, 2026-08-27 부터 이 레포에서 관리한다.

**이 레포는 쓰는 법과 함께 결정 기록을 남긴다.** 무엇을 왜 그렇게 정했는지는 [`docs/`](docs/) 에
따로 적는다 — 고칠 때 같은 자리를 다시 파지 않으려고 쓴 것이다. 쓰기만 할 거라면 아래 설치까지만
읽으면 된다.

## 설치

Apple Silicon 맥(macOS 13 이상)과 Node.js 가 필요하다.

```sh
brew tap rehyundesign/retto
brew install --cask retto
```

세 가지 길이 있고 갈리는 건 Gatekeeper 한 단계뿐이다. 레토는 애플 개발자 서명이 없다.

| 길 | 첫 실행에서 막히나 |
| --- | --- |
| `brew install --cask retto` | 아니오 — cask 가 격리 표시를 뗀다 |
| `git clone` 뒤 `macos/scripts/build.sh --install` | 아니오 — 내려받은 것이 아니라 딱지가 안 붙는다 |
| [릴리스](../../releases)의 DMG 를 `Applications` 로 끌어다 놓기 | 예 — 시스템 설정에서 「그래도 열기」 한 번 |

탭은 [rehyundesign/homebrew-retto](https://github.com/rehyundesign/homebrew-retto) 다.
Homebrew 6.0 에서 `--no-quarantine` 이 없어졌고, 그 대신 cask 의 `postflight` 가 그 일을 한다 —
공식 homebrew-cask 는 이 방식을 받지 않으므로, 서명을 붙이면 뺀다.

처음 켜면 설정 창이 저절로 떠서 훅이 걸렸는지, node 가 있는지, 어느 클라이언트에서 소식이
오는지 스스로 알려준다. 발바닥 메뉴 **「Claude 연동 확인」** 이 같은 창을 다시 연다.

`~/.codex` 가 있으면 Codex 훅도 함께 등록한다. Codex 는 훅 설정이 바뀌면 시작할 때 승인 화면을
띄우므로, 설치 직후 한 번 다시 켜서 허용해 줘야 세션이 레토에게 보인다.

## 무엇이 어디에

```
assets/   스프라이트 아틀라스·손글씨 폰트·아이콘
macos/    데스크탑 오버레이 (Swift, 모든 Space·전체화면 위에 상주)
hook/     Claude Code·Codex 훅(hook.sh·hook.cjs)과 설치기
scripts/  훅 설치 래퍼와 진단기
tools/    에셋 검사·교정 도구
docs/     결정 기록
```

```sh
scripts/check.sh                  # 빌드 + 자체 검사 + Claude·Codex 훅 테스트
scripts/install-hooks.sh          # 훅만 다시 설치
scripts/doctor.command            # 어디서 멈췄는지 본다
```

## 결정 기록

| 문서 | 무엇이 적혀 있나 |
| --- | --- |
| [화면에 보이는 것](docs/오버레이.md) | 몸·말풍선·배지의 배율과 모양. 말풍선 윤곽은 Figma 벡터를 둘레 기준 160점으로 다시 뽑아 다듬은 것이다(`--shape-report` 로 수치 확인) |
| [상태를 어떻게 아는가](docs/훅과-세션.md) | 훅 등록, 두 제품의 트랜스크립트가 다른 점, 유령 세션, 읽음 판정, 앱에서만 안 될 때 |
| [클릭하면 어디로 가는가](docs/세션-열기.md) | 딥링크와 창 순서, VS Code·Claude 앱·Codex 중 어디로 보낼지 |
| [빌드·검사·배포](docs/빌드와-배포.md) | `build.sh`, 소스 열세 파일의 역할, 자체 검사, DMG 와 서명 |
| [스프라이트 아틀라스](docs/에셋.md) | 아틀라스 배율 교정, 자는 행 만들기 |
| [자는 그림 규격](docs/자는-그림-규격.md) | 행 11 에 넣을 그림을 받을 때의 규격 |
