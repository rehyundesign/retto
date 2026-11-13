import AppKit

/// 연결 안내에는 계정 정보나 토큰을 포함하지 않는다. 브라우저에서 읽을 수 있는 로컬 문서다.
enum SlackConnectionGuide {
    static func writeDocument() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retto-slack-guide", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("slack-connection.html")
        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static let html = #"""
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'; img-src 'none'; base-uri 'none'; form-action 'none'">
<title>Slack 연결 안내 · 레토</title>
<style>
:root{color-scheme:light;--bg:#fff9f0;--paper:#fffefa;--text:#574435;--muted:#806b5a;--line:#efdfcb;--accent:#995024;--soft:#fff0d4;--warm:#fff5d9;--peach:#ffe1c7;--shadow:0 8px 28px #9d74400b}
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:28px}body{margin:0;background:radial-gradient(ellipse at 90% 0%,#ffedda 0,transparent 38%),var(--bg);color:var(--text);font:16px/1.85 "Apple SD Gothic Neo","Malgun Gothic",sans-serif;word-break:keep-all;overflow-wrap:break-word}a{color:var(--accent);text-underline-offset:4px}button,a{touch-action:manipulation}a:focus-visible,button:focus-visible,summary:focus-visible,textarea:focus-visible{outline:3px solid #c47b42;outline-offset:5px}
.layout{max-width:1120px;margin:auto;padding:48px 32px 80px;display:grid;grid-template-columns:210px minmax(0,1fr);gap:48px}.sidebar{position:sticky;top:36px;align-self:start;padding-top:10px}.brand{font-size:24px;font-weight:800;letter-spacing:-.04em;display:flex;align-items:center;gap:10px}.brand:before{content:"🐾";font-size:25px;display:grid;place-items:center;background:#ffebcf;border-radius:18px;width:48px;height:48px}.tag{font-size:13px;color:var(--muted);margin:8px 0 0 58px}.sidebar nav{display:grid;gap:6px;margin-top:32px}.sidebar nav a{text-decoration:none;font-size:14px;color:var(--muted);padding:9px 14px;border-radius:15px;transition:background .15s,color .15s}.sidebar nav a:hover{background:var(--soft);color:var(--accent)}.sidebar small{display:block;margin:30px 14px 0;color:var(--muted);font-size:12px;line-height:1.9}
header{position:relative;padding:34px 36px;background:#fffdeb;border:1px solid #f0e4bc;border-radius:34px;box-shadow:var(--shadow);margin-bottom:38px}header:after{content:"";position:absolute;bottom:-10px;left:45px;width:20px;height:20px;background:#fffdeb;border-right:1px solid #f0e4bc;border-bottom:1px solid #f0e4bc;transform:rotate(45deg);border-radius:0 0 6px 0}.eyebrow{display:inline-block;font-size:12px;color:var(--accent);font-weight:800;letter-spacing:.08em;background:var(--peach);padding:5px 12px;border-radius:20px}h1{font:800 clamp(29px,4vw,41px)/1.45 "Apple SD Gothic Neo","Malgun Gothic",sans-serif;letter-spacing:-.045em;margin:18px 0 14px;color:#684932}header p{color:var(--muted);margin:0;max-width:590px}.intro{margin-top:24px;padding:18px 20px;background:#fff7dc;border:1px dashed #e9d7aa;border-radius:20px;font-size:14px}.intro strong{display:block}.intro p{margin:5px 0 0;color:var(--muted)}
section{padding:28px 30px;margin:0 0 22px;background:var(--paper);border:1px solid var(--line);border-radius:28px;box-shadow:var(--shadow)}.stephead{display:flex;align-items:center;gap:13px;margin-bottom:18px}.number{display:grid;place-items:center;flex-shrink:0;min-width:43px;height:43px;padding:0 9px;border-radius:16px;background:#ffe9cf;font-size:17px;font-weight:800;color:#8c4b26}#step2 .number{background:#f3edda}#step3 .number{background:#fbe6df}#step4 .number{background:#eaf0df}h2{font-size:22px;letter-spacing:-.035em;line-height:1.5;margin:0}h3{font-size:15px;margin:0 0 8px}p{margin:10px 0}ol,ul{padding-left:24px}li{padding-left:4px;margin:11px 0}li::marker{color:var(--accent);font-weight:700}.note{font-size:14px;color:var(--muted)}.path{font-size:13px;color:var(--accent);font-weight:700;margin:12px 0;padding:10px 14px;background:#fff5e9;border-radius:13px}.pill{display:inline-block;background:var(--soft);border-radius:8px;padding:0 8px;font-size:13px}code{font:13px/1.7 Menlo,Consolas,monospace;overflow-wrap:anywhere}.button,button{display:inline-block;border:1px solid #edc79c;border-radius:16px;padding:12px 18px;font:700 14px/1.5 "Apple SD Gothic Neo","Malgun Gothic",sans-serif;cursor:pointer;text-decoration:none;background:#ffdcad;color:#6c4026;box-shadow:0 3px 0 #b7803820;transition:background .15s,transform .15s}.button:hover,button:hover{background:#ffd19a;transform:translateY(-1px)}.secondary{color:var(--accent);background:#fff8eb;border-color:#ead6b9}.secondary:hover{background:#fff0d5}.actions{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:22px 0 12px}.copy-status{font-size:13px;color:var(--accent);min-height:24px}details{background:#fffbf4;border:1px solid var(--line);border-radius:18px;margin:12px 0;padding:15px 18px}details[open]{background:#fff8eb}summary{cursor:pointer;font-size:15px;font-weight:700}summary::marker{color:#bc8755}details p{font-size:14px;color:var(--muted)}textarea{width:100%;height:290px;resize:vertical;margin-top:14px;padding:16px;background:#fffefa;border:1px solid var(--line);border-radius:14px;color:var(--text);font:12px/1.6 Menlo,Consolas,monospace}.tokens{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:20px 0}.token{padding:18px;border:1px solid #efdabd;border-radius:20px;background:#fff6e4}.token:nth-child(2){background:#fff0e9;border-color:#efdbd0}.token code{font-size:21px;font-weight:700;color:var(--accent)}.token p{font-size:14px;margin-bottom:0}.callout{padding:16px 20px;border:1px solid #eddfb9;border-radius:18px;background:var(--warm);font-size:14px;margin:20px 0}.complete{background:#f1f5e9;border:1px solid #dfe8d2;border-radius:20px;padding:20px;margin-top:24px}.complete p{font-size:14px}footer{padding:8px 20px 0;font-size:12px;color:var(--muted)}
@media(max-width:800px){.layout{display:block;padding:24px 18px 60px}.sidebar{position:static;margin-bottom:26px;padding:0 8px}.sidebar nav{display:flex;gap:4px;flex-wrap:wrap;margin-top:18px}.sidebar nav a{font-size:13px;padding:7px 10px}.sidebar small{display:none}header{padding:28px 26px}section{padding:24px}h2{font-size:20px}}@media(max-width:460px){.tokens{grid-template-columns:1fr}.actions .button,.actions button{width:100%;text-align:center}header{padding:25px 22px}section{padding:23px 20px;border-radius:24px}.stephead{gap:10px}h2{font-size:19px}}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}.button,button,.sidebar nav a{transition:none}}@media print{.sidebar,.actions{display:none}.layout{display:block;padding:0}details,section{break-inside:avoid}body{background:white;color:black}header,section{box-shadow:none}}
</style>
</head>
<body><div class="layout">
<aside class="sidebar"><div class="brand">Retto · 레토</div><div class="tag">Slack 연결 안내</div><nav aria-label="연결 단계"><a href="#prepare">시작하기 전에</a><a href="#step1">01 · Slack 앱 만들기</a><a href="#step2">02 · 사용자 토큰 받기</a><a href="#step3">03 · 앱 토큰 받기</a><a href="#step4">04 · 레토에 연결하기</a><a href="#help">막히는 곳이 있나요?</a></nav><small>이 안내는 맥에서 열립니다.<br>토큰을 입력하는 칸은<br>레토 설정 창에만 있습니다.</small></aside>
<main><header id="prepare"><span class="eyebrow">SLACK × RETTO</span><h1>슬랙 소식도,<br>레토가 알려드릴게요.</h1><p>처음 한 번만 Slack에서 연결을 준비하면 됩니다.<br>이 안내를 옆에 열어두고, 아래 네 단계를 따라 해주세요.</p><div class="intro"><strong>준비물은 Slack 계정과 토큰 두 개예요.</strong><p>본인이 사용할 워크스페이스에 로그인해주세요. 회사 정책에 따라 관리자에게 앱 설치 승인을 받아야 할 수 있습니다. 이미 전용 앱을 만들었다면 <a href="#step2">2단계</a>부터 확인해도 됩니다.</p></div></header>
<section id="step1"><div class="stephead"><span class="number">01</span><h2>레토 전용 Slack 앱 만들기</h2></div><p>아래 설정 JSON에는 레토에 필요한 권한과 메시지 수신 설정이 들어 있습니다. 복사해서 붙여 넣으면 하나씩 설정하지 않아도 됩니다.</p><div class="actions"><a class="button" href="https://api.slack.com/apps" target="_blank" rel="noopener noreferrer">Slack 앱 관리 열기 ↗</a><button class="secondary" id="copy" type="button">설정 JSON 복사</button></div><div class="copy-status" id="copy-status" role="status" aria-live="polite"></div><ol><li>Slack 앱 관리에서 <strong>Create New App → From a manifest</strong>를 선택합니다.</li><li>알림을 받을 <strong>워크스페이스</strong>를 선택합니다.</li><li><strong>JSON</strong> 형식을 선택하고 기존 예시 전체를 지운 뒤, 복사한 설정을 붙여 넣습니다.</li><li><strong>Next</strong>에서 설정을 확인하고 <strong>Create</strong>를 누릅니다.</li></ol><p class="note">Slack 화면에 따라 워크스페이스 선택과 설정 입력 순서가 다를 수 있습니다. JSON에 포함된 이름은 그대로 사용해도 됩니다.</p><details id="manifest-details"><summary>설정 JSON 직접 보기 · 복사가 안 될 때</summary><p>아래 칸을 클릭한 뒤 ⌘A → ⌘C로 복사하세요. 이 내용에는 비밀 토큰이 없습니다.</p><textarea id="manifest" readonly spellcheck="false" aria-label="Slack 앱 설정 JSON">{
  &quot;display_information&quot;: {
    &quot;name&quot;: &quot;Retto personal notifications&quot;,
    &quot;description&quot;: &quot;개인용 레토 데스크톱 알림&quot;,
    &quot;background_color&quot;: &quot;#345A89&quot;
  },
  &quot;oauth_config&quot;: {
    &quot;scopes&quot;: {
      &quot;user&quot;: [
        &quot;channels:read&quot;, &quot;groups:read&quot;, &quot;im:read&quot;, &quot;mpim:read&quot;, &quot;users:read&quot;, &quot;channels:history&quot;,
        &quot;groups:history&quot;, &quot;im:history&quot;, &quot;mpim:history&quot;
      ]
    }
  },
  &quot;settings&quot;: {
    &quot;event_subscriptions&quot;: {
      &quot;user_events&quot;: [&quot;message.channels&quot;, &quot;message.groups&quot;, &quot;message.im&quot;, &quot;message.mpim&quot;]
    },
    &quot;socket_mode_enabled&quot;: true,
    &quot;org_deploy_enabled&quot;: false,
    &quot;token_rotation_enabled&quot;: false
  }
}</textarea></details><p class="note">이 앱은 본인만 설치해서 사용해주세요. 같은 앱을 다른 사람이나 다른 수신 프로그램과 함께 쓰면 알림이 나뉘어 전달될 수 있습니다.</p></section>
<section id="step2"><div class="stephead"><span class="number">02</span><h2>사용자 토큰 복사하기</h2></div><div class="path">왼쪽 메뉴 → OAuth &amp; Permissions</div><ol><li><strong>Install to Workspace</strong>를 누릅니다. 설치 화면이 다르게 보이면 해당 워크스페이스에 설치하는 버튼을 선택해주세요.</li><li>워크스페이스와 요청 권한을 확인한 뒤 <strong>허용 / Allow</strong>를 누릅니다. 승인이 필요하면 관리자에게 요청합니다.</li><li>설정 화면으로 돌아와 <strong>User OAuth Token</strong>의 <span class="pill">xoxp-</span>로 시작하는 값을 복사합니다.</li><li>레토의 <strong>Slack 설정 → 사용자 OAuth 토큰</strong> 칸에 붙여 넣습니다.</li></ol><div class="callout"><strong>Bot User OAuth Token과 구분해주세요.</strong><br><code>xoxb-</code>로 시작하는 봇 토큰은 이 칸에서 사용할 수 없습니다. <code>xoxp-</code>로 시작하는 사용자 토큰을 찾아주세요.</div></section>
<section id="step3"><div class="stephead"><span class="number">03</span><h2>앱 토큰 복사하기</h2></div><div class="path">같은 앱의 왼쪽 메뉴 → Basic Information → App-Level Tokens</div><ol><li><strong>Generate Token and Scopes</strong>를 누릅니다.</li><li>이름은 <strong>Retto</strong>처럼 알아보기 쉽게 입력합니다.</li><li><strong>Add Scope</strong>에서 <code>connections:write</code>를 선택하고 <strong>Generate</strong>를 누릅니다.</li><li><span class="pill">xapp-</span>로 시작하는 값을 복사해 레토의 <strong>앱 수준 토큰</strong> 칸에 붙여 넣습니다.</li></ol><p class="note">왼쪽 <strong>Socket Mode</strong>에서 <strong>Enable Socket Mode</strong>도 켜져 있어야 합니다. 1단계 JSON으로 만들었다면 이 설정은 포함되어 있습니다. 토큰 생성 창이 먼저 나타나면 위와 같이 발급하면 됩니다.</p></section>
<section id="step4"><div class="stephead"><span class="number">04</span><h2>레토에서 연결 마무리하기</h2></div><p>레토 메뉴의 <strong>Slack 설정…</strong>으로 돌아와 두 칸을 확인하세요.</p><div class="tokens"><div class="token"><h3>위쪽 · 사용자 OAuth 토큰</h3><code>xoxp-…</code><p>OAuth &amp; Permissions에서 복사한 값</p></div><div class="token"><h3>아래쪽 · 앱 수준 토큰</h3><code>xapp-…</code><p>App-Level Tokens에서 복사한 값</p></div></div><ol><li><strong>저장하고 연결</strong>을 누르고, 창 위쪽에 연결된 상태가 표시되는지 확인합니다.</li><li><strong>DM 알림</strong>과 <strong>내 멘션 알림</strong> 중 원하는 항목을 켭니다. 추가 채널을 선택하면 그 채널의 모든 새 메시지도 알립니다.</li><li>다른 사람이 보낸 <strong>새 DM</strong>으로 확인해보세요. 본인이 보낸 메시지와 연결 전에 온 메시지는 알리지 않습니다.</li></ol><div class="complete"><strong>연결 후에는 토큰을 다시 넣지 않아도 돼요.</strong><p>저장한 토큰은 이 맥의 키체인에서 관리하며, 입력 칸은 저장 후 비워집니다. 나중에 한 토큰만 바꿀 때는 그 칸만 채워주세요. 빈칸은 기존 값을 유지합니다.</p></div></section>
<section id="help"><div class="stephead"><span class="number">?</span><h2>여기서 막히셨나요?</h2></div>
<details><summary>이미 앱은 있는데, 어디부터 확인하나요?</summary><p>기존 앱의 <strong>App Manifest</strong>에서 권한과 이벤트를 아래 목록과 비교하세요. 기존 앱 설정을 통째로 덮어쓰지 않아도 됩니다. 사용자 권한을 추가했다면 <strong>OAuth &amp; Permissions → Reinstall to Workspace</strong>로 다시 설치하고, 사용자 토큰이 바뀌었으면 레토에서도 갱신해주세요.</p><p><strong>User Token Scopes</strong><br><code>channels:read · groups:read · im:read · mpim:read · users:read · channels:history · groups:history · im:history · mpim:history</code></p><p><strong>Event Subscriptions → Subscribe to events on behalf of users</strong><br><code>message.channels · message.groups · message.im · message.mpim</code><br>Enable Events와 Socket Mode가 켜져 있어야 합니다. Socket Mode에서는 Request URL을 입력하지 않습니다.</p></details>
<details><summary>관리자 승인이 필요하다고 나와요</summary><p>회사에서 앱 설치를 제한한 경우입니다. Slack 화면에서 설치 요청을 보내거나 워크스페이스 관리자에게 승인을 요청해주세요. 승인이 완료되면 2단계의 설치를 이어서 진행합니다.</p></details>
<details><summary>토큰 오류 · 권한 부족이 표시돼요</summary><p>위 칸은 <code>xoxp-</code>, 아래 칸은 <code>xapp-</code>인지, 두 토큰이 <strong>같은 Slack 앱</strong>에서 발급됐는지 확인해주세요. 사용자 토큰은 위 ‘이미 앱은 있는데’ 항목에 적힌 아홉 권한, 앱 토큰은 <code>connections:write</code>가 필요합니다. 권한을 추가했다면 Slack 앱을 다시 설치한 뒤 레토에서 <strong>저장하고 연결</strong>을 눌러주세요.</p></details>
<details><summary>연결됐는데 DM이 안 떠요</summary><p>레토에서 DM 알림이 켜져 있는지, Slack 앱의 Socket Mode와 사용자 이벤트가 설정돼 있는지 확인하세요. 다른 사람이 연결 후 보낸 새 메시지로 확인해주세요. 같은 Slack 앱을 사용하는 다른 레토나 개발용 수신 프로그램이 있다면 종료해주세요. 본인 메시지와 연결이 끊긴 동안의 메시지는 표시하지 않습니다.</p></details>
<details><summary>Slack에서 읽었는데 알림이 남아요</summary><p>읽음 반영에는 시간이 걸릴 수 있습니다. 계속 남고 설정 창에 읽음 권한 문제가 표시된다면 <code>im:read</code>와 <code>mpim:read</code>를 포함한 사용자 권한을 확인하고 앱을 다시 설치해주세요. 새 사용자 토큰을 발급받았다면 레토의 위쪽 칸만 갱신하면 됩니다.</p></details>
<details><summary>키체인 확인 중이라고 나와요</summary><p>연결 정보를 불러오는 중일 수 있습니다. 잠시 후 상태를 다시 확인하세요. macOS가 레토의 기존 Slack 항목 접근을 요청한다면 내용을 확인하고 허용해주세요. 승인 창이 보이지 않으면 다른 창 뒤에 있는지 확인하되, 승인 창이 반드시 뜨는 것은 아닙니다. 계속 연결되지 않으면 설정 창의 <strong>연결 다시 시도</strong>를 눌러주세요.</p></details>
</section><footer>토큰은 레토 설정 창에만 입력해주세요. 이 안내에는 토큰 입력·전송 기능이 없습니다.<br>설정 기준: <a href="https://docs.slack.dev/app-manifests/configuring-apps-with-app-manifests/" target="_blank" rel="noopener noreferrer">Slack 앱 설정 문서</a> · <a href="https://docs.slack.dev/apis/events-api/using-socket-mode/" target="_blank" rel="noopener noreferrer">Socket Mode 문서</a></footer></main></div>
<script>
document.getElementById('copy').addEventListener('click', async function () {
  const field = document.getElementById('manifest');
  const status = document.getElementById('copy-status');
  try {
    if (!navigator.clipboard || !window.isSecureContext) throw new Error('manual');
    await navigator.clipboard.writeText(field.value);
    status.textContent = '복사했습니다. Slack의 JSON 입력 칸에 붙여 넣어주세요.';
  } catch (_) {
    document.getElementById('manifest-details').open = true;
    field.focus(); field.select();
    status.textContent = '설정 내용을 선택했습니다. ⌘C로 복사해주세요.';
  }
});
</script></body></html>
"""#
}
