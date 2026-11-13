// Slack 설정 창. 맥 앱 SlackSettingsWindow.swift 와 같은 항목이다.

const $ = (id) => document.getElementById(id);
let state = null;

function render(next) {
  state = next;
  const status = $('status');
  status.textContent = next.status + (next.issue && next.issue !== next.status ? `\n${next.issue}` : '');
  status.className = `status ${next.connectionState}`;
  $('disconnect').disabled = !next.hasCredentials;
  $('dm').checked = next.preferences.directMessages;
  $('mention').checked = next.preferences.mentions;
  $('preview').checked = next.preferences.preview;
  const box = $('channels');
  box.replaceChildren();
  for (const channel of next.channels) {
    const label = document.createElement('label');
    label.className = 'check';
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.checked = next.preferences.channelIDs.includes(channel.id);
    input.addEventListener('change', () => {
      const ids = new Set(state.preferences.channelIDs);
      if (input.checked) ids.add(channel.id); else ids.delete(channel.id);
      window.retto.slackPreferences({ channelIDs: [...ids] });
    });
    label.append(input, ` #${channel.name}`);
    box.append(label);
  }
  if (!next.channels.length) box.textContent = next.hasCredentials ? '채널 목록이 비어 있다.' : '연결하면 채널 목록이 보인다.';
}

$('connect').addEventListener('click', async () => {
  $('result').textContent = '';
  const outcome = await window.retto.slackConnect($('user').value, $('app').value);
  if (!outcome.ok) $('result').textContent = outcome.error;
  else { $('user').value = ''; $('app').value = ''; }
});
$('disconnect').addEventListener('click', async () => {
  const outcome = await window.retto.slackDisconnect();
  $('result').textContent = outcome.ok ? '' : outcome.error;
});
$('refresh').addEventListener('click', () => window.retto.slackRefreshChannels());
for (const [id, key] of [['dm', 'directMessages'], ['mention', 'mentions'], ['preview', 'preview']]) {
  $(id).addEventListener('change', (event) => window.retto.slackPreferences({ [key]: event.target.checked }));
}
$('guide').addEventListener('click', (event) => {
  event.preventDefault();
  window.retto.openUrl('https://github.com/rehyundesign/retto/blob/main/docs/Slack-연결.md');
});

window.retto.onSlackState(render);
window.retto.slackState().then(render);
