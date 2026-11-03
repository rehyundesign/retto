// 실제 Windows 에서 처음부터 끝까지 — 설치본 Retto.exe 의 「훅 설치」 → Claude Code 가 하듯 등록된 명령 실행 →
// 레토 화면 → 「훅 제거」. CI(windows-latest)가 돌린다. 맥에서는 돌지 않는다.
//
// Claude Code 자체는 띄우지 않는다(로그인이 필요하다). 대신 Claude Code 가 settings.json 에서 읽어 셸로 넘기는
// 그 명령 문자열을 그대로 꺼내, Claude Code 가 쓴다고 보고된 셸(cmd · PowerShell · Git Bash)로 돌린다.
// 그래서 이 시험이 증명하는 것은 「등록된 명령이 Windows 셸에서 돌아 레토가 맞게 바뀐다」까지다.
//
//   node windows/test-e2e/flow.mjs <Retto.exe> <결과 폴더>

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const [exe, outDir] = process.argv.slice(2);
if (process.platform !== 'win32' || !exe || !outDir) {
  console.error('Windows 에서 node flow.mjs <Retto.exe> <결과 폴더> 로 돌린다');
  process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

// 띄어쓰기와 한글이 든 홈. 실제 사용자 이름에 흔하다.
const home = fs.mkdtempSync(path.join(os.tmpdir(), '레토 사용자 '));
const env = { ...process.env, RETTO_HOME: home, PATH: `${path.dirname(process.execPath)}${path.delimiter}${process.env.PATH}`, CLAUDE_CODE_ENTRYPOINT: '' };
const settingsPath = path.join(home, '.claude', 'settings.json');
const codexHooksPath = path.join(home, '.codex', 'hooks.json');
const neighbor = { hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo neighbor' }] }] } };
fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
fs.mkdirSync(path.dirname(codexHooksPath), { recursive: true });
fs.writeFileSync(settingsPath, JSON.stringify(neighbor, null, 2));
fs.writeFileSync(codexHooksPath, JSON.stringify(neighbor, null, 2));

const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok: Boolean(ok), detail });
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${detail ? ` — ${detail}` : ''}`);
}

function run(file, args, { input, verbatim = false } = {}) {
  return new Promise((resolve) => {
    const child = spawn(file, args, { env, windowsVerbatimArguments: verbatim, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', (error) => resolve({ code: -1, stdout, stderr: String(error) }));
    child.on('exit', (code) => resolve({ code, stdout, stderr }));
    child.stdin.end(input ?? '');
  });
}

const shells = {
  cmd: (command) => ['cmd.exe', ['/d', '/s', '/c', command], true],
  PowerShell: (command) => ['powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], false],
  'Git Bash': (command) => ['C:/Program Files/Git/bin/bash.exe', ['-c', command], false]
};

function commandFor(file, event, { codex = false } = {}) {
  const settings = JSON.parse(fs.readFileSync(file, 'utf8'));
  for (const group of settings.hooks?.[event] || []) {
    for (const handler of group.hooks || []) {
      const command = String(handler.command || '');
      if (command.includes('retto-pet/hook.') && command.includes('"codex"') === codex) return command;
    }
  }
  return undefined;
}

async function fire(shell, event, payload, options) {
  const command = commandFor(options?.codex ? codexHooksPath : settingsPath, event, options);
  if (!command) return { code: -1, stderr: `${event} 명령이 등록돼 있지 않다` };
  const [file, args, verbatim] = shells[shell](command);
  return run(file, args, { verbatim, input: JSON.stringify({ hook_event_name: event, cwd: 'C:\\work\\landing', ...payload }) });
}

async function render(label) {
  const png = path.join(outDir, `${label}.png`);
  fs.rmSync(`${png}.log`, { force: true });
  await run(exe, ['--render-preview', png]);
  const log = fs.existsSync(`${png}.log`) ? fs.readFileSync(`${png}.log`, 'utf8') : '';
  const pose = /pose=(\w+)/.exec(log)?.[1];
  const badge = Number(/badge=(\d+)/.exec(log)?.[1] ?? NaN);
  return { pose, badge, png: fs.existsSync(png) };
}

// 1. 설치 — 연동 확인 창의 「훅 설치」와 같은 코드
const installOut = path.join(outDir, 'install.json');
await run(exe, ['--install-hooks', installOut]);
const install = fs.existsSync(installOut) ? JSON.parse(fs.readFileSync(installOut, 'utf8')) : { ok: false, error: '결과 파일 없음' };
check('훅 설치', install.ok, install.ok ? `Claude ${install.claude}개 · Codex ${install.codex}개 · ${install.reason}` : install.error);
const afterInstall = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
check('설치해도 다른 훅이 남는다', afterInstall.hooks.Stop.some((group) => group.hooks.some((handler) => handler.command === 'echo neighbor')));
check('Windows 에는 hook.sh 를 깔지 않는다', !fs.existsSync(path.join(home, '.claude', 'retto-pet', 'hook.sh')));
const sample = commandFor(settingsPath, 'UserPromptSubmit');
check('등록된 명령 꼴', sample?.startsWith('node "') && !sample.includes('\\'), sample);

// 2. Claude Code 처럼 명령을 돌리고 화면을 본다. 단계마다 다른 셸로 돌려 세 셸을 다 거친다.
const session = { session_id: 'e2e-claude', prompt: '랜딩 히어로 고쳐줘' };
const steps = [
  { shell: 'cmd', event: 'UserPromptSubmit', payload: session, expect: { pose: 'running' } },
  { shell: 'PowerShell', event: 'PermissionRequest', payload: { ...session, tool_name: 'Bash' }, expect: { pose: 'waiting' } },
  { shell: 'Git Bash', event: 'Stop', payload: { ...session, last_assistant_message: '히어로 문구를 고쳤어.' }, expect: { pose: 'waving', badge: 1 } }
];
for (const step of steps) {
  const fired = await fire(step.shell, step.event, step.payload);
  check(`${step.event} 를 ${step.shell} 로 실행`, fired.code === 0, fired.code === 0 ? '' : `exit ${fired.code} ${fired.stderr.slice(-300)}`);
  const view = await render(`${step.event}-${step.shell.replace(' ', '')}`);
  const okPose = view.pose === step.expect.pose;
  const okBadge = step.expect.badge === undefined || view.badge === step.expect.badge;
  check(`→ 레토 ${step.expect.pose}${step.expect.badge !== undefined ? ` · 배지 ${step.expect.badge}` : ''}`, view.png && okPose && okBadge, `pose=${view.pose} badge=${view.badge}`);
}

// 3. Codex 훅도 같은 파일에 적히는가
const codexFired = await fire('PowerShell', 'UserPromptSubmit', { session_id: 'e2e-codex', prompt: '테스트 고쳐줘' }, { codex: true });
const registry = JSON.parse(fs.readFileSync(path.join(home, '.claude', 'retto-pet', 'sessions.json'), 'utf8'));
check('Codex 훅이 sessions.json 에 적힌다', codexFired.code === 0 && registry.sessions?.['codex:e2e-codex']?.state === 'running',
  `exit ${codexFired.code} state=${registry.sessions?.['codex:e2e-codex']?.state}`);

// 4. 제거 — 레토 것만 빠지고 다른 훅은 그대로
const uninstallOut = path.join(outDir, 'uninstall.json');
await run(exe, ['--uninstall-hooks', uninstallOut]);
const uninstall = fs.existsSync(uninstallOut) ? JSON.parse(fs.readFileSync(uninstallOut, 'utf8')) : { ok: false };
check('훅 제거', uninstall.ok, uninstall.error || '');
check('제거 뒤 Claude 설정은 원래 이웃만 남는다', JSON.stringify(JSON.parse(fs.readFileSync(settingsPath, 'utf8')).hooks) === JSON.stringify(neighbor.hooks));
check('제거 뒤 Codex 설정은 원래 이웃만 남는다', JSON.stringify(JSON.parse(fs.readFileSync(codexHooksPath, 'utf8')).hooks) === JSON.stringify(neighbor.hooks));
check('제거 뒤 hook.cjs 가 남지 않는다', !fs.existsSync(path.join(home, '.claude', 'retto-pet', 'hook.cjs')));

fs.writeFileSync(path.join(outDir, 'flow.json'), JSON.stringify({ home, results }, null, 2));
const failed = results.filter((item) => !item.ok);
console.log(`\n${results.length - failed.length}/${results.length} 통과`);
process.exit(failed.length ? 1 : 0);
