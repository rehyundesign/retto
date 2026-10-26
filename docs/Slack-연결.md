# Slack 연결

레토 메뉴 → **Slack 설정…**에서 연결과 알림 범위를 바꾼다. 개인 DM·그룹 DM, 내 사용자 멘션, 추가로 선택한 채널의 모든 새 메시지를 각각 설정한다. 기본값은 DM·멘션 켜기, 추가 채널 없음, 내용 미리보기 켜기다.

## 연결 준비

이 버전은 별도 서버 없이 Slack 공식 Socket Mode로 연결한다. 브라우저 로그인만으로 연결하는 OAuth 화면은 포함하지 않는다. 본인만 설치하는 전용 Slack 앱과 같은 앱에서 발급한 두 토큰이 필요하다. 회사 워크스페이스에는 관리자 승인이 필요할 수 있다.

1. [Slack 앱 관리](https://api.slack.com/apps)에서 앱을 만든다. 아래 `slack-app-manifest.json` 내용을 이용해 **From a manifest**로 만들 수 있다.
2. OAuth & Permissions에서 앱을 워크스페이스에 설치하고 **User OAuth Token** (`xoxp-`)을 확인한다. 봇 토큰은 개인 DM을 받는 용도로 쓰지 않는다.
3. Socket Mode를 켠다. Basic Information → App-Level Tokens에서 `connections:write` 권한으로 앱 토큰 (`xapp-`)을 만든다.
4. 레토의 Slack 설정에 두 토큰을 입력하고 **저장하고 연결**을 누른다. 토큰은 채팅이나 문서에 붙이지 않는다.
5. 연결 상태를 확인하고, 다른 사람이 보낸 새 DM이나 내 멘션으로 확인한다. 자신의 메시지는 알리지 않는다.

수동으로 설정한다면 **User Token Scopes**는 `channels:read`, `groups:read`, `users:read`, `channels:history`, `groups:history`, `im:history`, `mpim:history`다. **Subscribe to events on behalf of users**는 `message.channels`, `message.groups`, `message.im`, `message.mpim`이다. `app_mention`은 봇 멘션이므로 개인 멘션을 대신하지 않는다. 권한을 변경하면 워크스페이스에 다시 설치한다.

같은 Slack 앱에 여러 사용자를 설치하거나 다른 Socket Mode 클라이언트를 함께 연결하지 않는다. Socket Mode 이벤트는 앱 연결 사이에서 나뉘어 전달될 수 있다. 레토는 선택한 워크스페이스와 사용자 권한에 해당하는 이벤트만 표시한다.

## 표시와 읽음

- 읽지 않은 Slack 메시지는 고정된 AI 완료 상태보다 먼저 표시한다. 이름표와 배지는 보라색이다. 이름표에는 `#채널명`, DM에는 `DM · 상대 이름`을 표시하고 본문은 `@보낸 사람 메시지`로 표시한다. 이름을 조회하지 못하면 사용자 ID를 표시한다.
- 레토가 받은 새 메시지를 말풍선과 배지로 표시한다. 알림은 최대 최근 100개를 메모리에 유지한다.
- 메시지를 누르면 `slack://channel` 링크를 Slack 데스크톱 앱에 직접 전달한다. 브라우저를 경유하지 않는다. 워크스페이스·대화 ID와 메시지 시각, 스레드 시각을 링크에 포함한다. 앱이 없거나 실행에 실패하면 알림을 유지한다. 앱 실행 성공은 메시지 화면 표시 성공을 보장하지 않는다.
- 레토에서 메시지를 열거나 메뉴의 표시 지우기를 누르면 레토에서 읽음으로 본다. Slack API로 읽음 상태를 변경하지 않는다. Slack에서 직접 읽은 메시지와의 읽음 동기화는 없다.
- 미리보기를 끄면 말풍선과 접근성 텍스트에서 메시지 본문을 표시하지 않는다. 본문은 수신 처리를 위해 메모리에 남으며 디스크에는 저장하지 않는다.
- 범위를 끄면 해당 알림을 목록에서 뺀다. 나중에 다시 켜도 지난 메시지를 복구하지 않는다.
- 앱이 종료되었거나 연결이 끊긴 동안의 메시지 이력은 조회하지 않는다. 자동 재연결은 지원하지만 누락 메시지를 복구하지 않는다.
- 인증 오류는 설정에 표시하며 자동 재연결을 멈춘다. 일시적인 연결 오류에는 재시도 간격을 늘리고, API의 HTTP 429에는 `Retry-After`를 적용한다.

## 저장과 해제

토큰은 `com.luxia.retto.slack` 서비스의 macOS 키체인 항목 하나에 함께 저장한다. 사용자 설정에는 알림 범위만 저장한다. 토큰을 저장한 후 입력 필드는 비운다. 연결 후에는 바꿀 토큰만 입력하면 비워 둔 토큰은 기존 값을 유지한다. 애드혹 서명으로 다시 빌드한 앱에서는 키체인 접근 허용을 다시 요청할 수 있다.

**연결 해제**는 이 맥의 토큰과 수신 목록을 삭제한다. Slack 서버의 앱 설치·권한을 취소하지는 않는다. 완전한 권한 철회는 Slack 앱 관리에서 진행한다. 레토의 기존 제거 기능도 키체인 항목을 삭제한다.

## 검증

`Retto --self-test-slack`은 실제 토큰이나 네트워크 없이 사용자·워크스페이스 필터, DM·멘션·채널 선택, 자체 메시지와 수정·삭제 제외, 중복 수신, 목록 제한, 미리보기, 메시지 링크 검증을 검사한다. 실제 계정의 인증·이벤트 전달과 Slack 앱 화면 이동은 별도 연결 후 확인해야 한다.

공식 문서: [Socket Mode](https://docs.slack.dev/apis/events-api/using-socket-mode/), [사용자 대화 목록](https://docs.slack.dev/reference/methods/users.conversations/), [DM 이벤트](https://docs.slack.dev/reference/events/message.im/).
