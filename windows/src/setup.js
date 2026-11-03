// 연동 확인 창. 무엇이 어긋났는지와 손댈 곳을 한 줄씩 보여 준다.

const rows = document.getElementById('rows');
const result = document.getElementById('result');

function ago(ms) {
  const minutes = Math.round((Date.now() - ms) / 60000);
  if (minutes < 1) return '방금';
  if (minutes < 60) return `${minutes}분 전`;
  const hours = Math.round(minutes / 60);
  return hours < 48 ? `${hours}시간 전` : `${Math.round(hours / 24)}일 전`;
}

function row(state, name, detail) {
  const div = document.createElement('div');
  div.className = 'row';
  const mark = document.createElement('span');
  mark.className = `mark ${state}`;
  mark.textContent = state === 'ok' ? '✓' : state === 'bad' ? '!' : '·';
  const title = document.createElement('span');
  title.className = 'name';
  title.textContent = name;
  const info = document.createElement('span');
  info.className = 'detail';
  info.textContent = detail;
  div.append(mark, title, info);
  rows.append(div);
}

async function render() {
  const report = await window.retto.report();
  rows.textContent = '';

  const expected = report.expectedClaudeHooks ? ` / ${report.expectedClaudeHooks}` : '';
  if (report.claudeHooks > 0 && report.hookFile && (!report.expectedClaudeHooks || report.claudeHooks >= report.expectedClaudeHooks)) {
    row('ok', `Claude Code 훅 ${report.claudeHooks}${expected}개`, report.paths.settingsPath);
  } else {
    row('bad', `Claude Code 훅 ${report.claudeHooks}${expected}개`, `아래 「훅 설치」를 누른다 · ${report.paths.settingsPath}`);
  }

  if (report.codexInstalled) {
    const ok = report.codexHooks > 0;
    row(ok ? 'ok' : 'bad', `Codex 훅 ${report.codexHooks}개`, ok
      ? 'Codex 를 한 번 다시 켜서 훅 승인 화면에서 허용해야 소식이 온다'
      : `아래 「훅 설치」를 누른다 · ${report.paths.codexHooksPath}`);
  } else {
    row('info', 'Codex', '~/.codex 가 없어 등록하지 않는다');
  }

  if (report.node) row('ok', 'node', report.node);
  else row('bad', 'node 없음', '훅은 PATH 의 node 로 돈다. https://nodejs.org 에서 LTS 를 설치한 뒤 Claude Code 를 다시 켠다');

  const channels = ['VS Code', 'Claude 앱', '터미널', 'Codex', '알 수 없음'];
  const seen = channels.filter((channel) => report.news[channel]);
  if (seen.length === 0) {
    row('bad', '아직 소식 없음', 'Claude Code 나 Codex 에서 아무 요청이나 한 번 보내 본다. 그래도 없으면 위 두 줄을 본다');
  } else {
    for (const channel of seen) row('ok', `${channel} 소식`, ago(report.news[channel]));
  }
  row('info', `Retto ${report.version}`, `${report.platform} · ${report.home}`);
}

document.getElementById('install').addEventListener('click', async () => {
  const outcome = await window.retto.install();
  result.textContent = outcome.ok
    ? `설치했다 · Claude 이벤트 ${outcome.claude}개 (${outcome.reason})${outcome.codex ? ` · Codex ${outcome.codex}개` : ''}\n열려 있는 Claude Code 는 다시 켜야 새 훅을 읽는다.`
    : `실패: ${outcome.error}`;
  render();
});

document.getElementById('uninstall').addEventListener('click', async () => {
  const outcome = await window.retto.uninstall();
  result.textContent = outcome.ok ? '레토 훅을 뺐다. 다른 훅은 그대로 둔다.' : `실패: ${outcome.error}`;
  render();
});

document.getElementById('refresh').addEventListener('click', render);
render();
