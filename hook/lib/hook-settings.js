const fs = require('node:fs');
const path = require('node:path');

// 필수(`required`)는 Claude Code 가 오래전부터 부르던 이벤트다. 이 여덟 개만으로도
// 상태 일곱 종이 다 나온다. 나머지는 최근에 생긴 것들이라 정밀도만 올린다 —
// 실패를 따로 잡아내고, 권한 대기를 Notification 보다 먼저 받고, 서브에이전트와
// 백그라운드 작업을 센다.
//
// 나눠 둔 이유는 낮은 버전 대비다. 모르는 이벤트 이름이 섞이면 설정 검증에서
// 훅 등록 전체가 무시될 수 있다. 그때는 필수만 등록한다(`minimal`).
const EVENT_STATES = [
  { event: 'SessionStart', state: 'idle', required: true },
  { event: 'UserPromptSubmit', state: 'running', required: true },
  { event: 'PreToolUse', state: 'running', required: true },
  { event: 'PostToolUse', state: 'running', required: true },
  { event: 'Notification', matcher: 'permission_prompt|agent_needs_input', state: 'waiting', required: true },
  { event: 'SubagentStop', state: 'running', required: true },
  { event: 'Stop', state: 'waving', required: true },
  { event: 'SessionEnd', state: 'idle', required: true },

  { event: 'PostToolBatch', state: 'running' },
  { event: 'PermissionRequest', state: 'waiting' },
  { event: 'Elicitation', state: 'waiting' },
  { event: 'PostToolUseFailure', state: 'failed' },
  { event: 'PermissionDenied', state: 'failed' },
  { event: 'SubagentStart', state: 'running' },
  { event: 'TaskCreated', state: 'running' },
  { event: 'TaskCompleted', state: 'review' },
  { event: 'StopFailure', state: 'failed' }
];

const REQUIRED_EVENT_STATES = EVENT_STATES.filter((entry) => entry.required);

// Codex 가 공식적으로 제공하는 lifecycle hook만 등록한다.
// Claude Code 전용 이벤트(Notification, Elicitation, TaskCompleted 등)를 섞으면
// Codex 시작 때 알 수 없는 이벤트로 전체 훅 설정이 거부될 수 있다.
const CODEX_EVENT_STATES = [
  { event: 'SessionStart', state: 'idle' },
  { event: 'UserPromptSubmit', state: 'running' },
  { event: 'PreToolUse', state: 'running' },
  { event: 'PermissionRequest', state: 'waiting' },
  { event: 'PostToolUse', state: 'running' },
  { event: 'SubagentStart', state: 'running' },
  { event: 'SubagentStop', state: 'running' },
  { event: 'Stop', state: 'waving' },
  { event: 'SessionEnd', state: 'idle' }
];

// 이름을 Retto 로 바로잡으면서 설치 폴더가 reto-pet → retto-pet 으로 바뀌었고,
// 0.8.0 에서 훅을 부르는 파일이 hook.cjs → hook.sh 로 바뀌었다. settings.json 에는
// 절대 경로가 들어가므로, 옛 경로도 계속 알아봐야 갱신·제거할 때 동작하지 않는
// 항목이 그대로 남는 일이 없다.
const HOOK_PATH_MARKERS = ['.claude/retto-pet/hook.', '.claude/reto-pet/hook.'];

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

/// 설치된 훅 파일(hook.sh)이 있는 폴더에서 hook.cjs 도 같이 산다.
function shimPathFor(installedHookPath) {
  return path.join(path.dirname(installedHookPath), 'hook.sh');
}

function mentionsRetto(value, hookPath) {
  if (typeof value !== 'string') return false;
  return value.includes(hookPath)
    || value.includes(shimPathFor(hookPath))
    || HOOK_PATH_MARKERS.some((marker) => value.includes(marker));
}

/// 우리 훅인가. 0.7.0 까지는 `command: node` + `args: [hook.cjs, 상태]` 였고
/// 지금은 `command: "'…/hook.sh' '상태'"` 한 줄이다. 갱신할 때 옛 항목도 빼야 하므로
/// 두 모양을 함께 알아본다.
function isRettoHandler(handler, hookPath) {
  if (!handler || handler.type !== 'command') return false;
  if (mentionsRetto(handler.command, hookPath)) return true;
  const args = Array.isArray(handler.args) ? handler.args : [];
  return args.some((arg) => mentionsRetto(arg, hookPath));
}

function removeRettoHooks(settings, hookPath) {
  const next = structuredClone(settings || {});
  if (!next.hooks || typeof next.hooks !== 'object') return next;

  for (const [event, groups] of Object.entries(next.hooks)) {
    if (!Array.isArray(groups)) continue;
    next.hooks[event] = groups
      .map((group) => {
        if (!group || !Array.isArray(group.hooks)) return group;
        return {
          ...group,
          hooks: group.hooks.filter((handler) => !isRettoHandler(handler, hookPath))
        };
      })
      .filter((group) => !group || !Array.isArray(group.hooks) || group.hooks.length > 0);

    if (next.hooks[event].length === 0) delete next.hooks[event];
  }

  if (Object.keys(next.hooks).length === 0) delete next.hooks;
  return next;
}

function isRettoCodexHandler(handler, hookPath) {
  if (!handler || handler.type !== 'command' || typeof handler.command !== 'string') return false;
  return mentionsRetto(handler.command, hookPath)
    && /(?:^|[\s'\"])codex(?:$|[\s'\"])/.test(handler.command);
}

function removeRettoCodexHooks(settings, hookPath) {
  const next = structuredClone(settings || {});
  if (!next.hooks || typeof next.hooks !== 'object') return next;

  for (const [event, groups] of Object.entries(next.hooks)) {
    if (!Array.isArray(groups)) continue;
    next.hooks[event] = groups
      .map((group) => {
        if (!group || !Array.isArray(group.hooks)) return group;
        return {
          ...group,
          hooks: group.hooks.filter((handler) => !isRettoCodexHandler(handler, hookPath))
        };
      })
      .filter((group) => !group || !Array.isArray(group.hooks) || group.hooks.length > 0);

    if (next.hooks[event].length === 0) delete next.hooks[event];
  }

  if (Object.keys(next.hooks).length === 0) delete next.hooks;
  return next;
}

/// Claude 훅을 등록한다.
///
/// `command` 한 줄 문자열로 적는다. 예전에는 `command: node` + `args: […]` 로 나눠 적었는데,
/// 그 모양은 최근 버전에만 있다. 데스크탑 앱은 CLI 와 별개로 자기 claude-code 를 내려받아
/// 쓰기 때문에 한 기계 안에서도 버전이 갈린다 — 터미널에서는 되는데 앱에서만 안 되는 일이
/// 여기서 나온다. 한 줄 문자열은 오래된 규격이라 양쪽에서 다 읽힌다.
///
/// `minimal` 이면 필수 여덟 개만 등록한다.
function mergeRettoHooks(settings, hookPath, options = {}) {
  const minimal = options.minimal === true;
  const next = removeRettoHooks(settings, hookPath);
  next.hooks = next.hooks || {};
  const shim = shimPathFor(hookPath);

  for (const entry of minimal ? REQUIRED_EVENT_STATES : EVENT_STATES) {
    const group = {
      ...(entry.matcher ? { matcher: entry.matcher } : {}),
      hooks: [
        {
          type: 'command',
          command: [shim, entry.state].map(shellQuote).join(' '),
          timeout: 5,
          async: true
        }
      ]
    };
    next.hooks[entry.event] = [...(next.hooks[entry.event] || []), group];
  }

  return next;
}

function mergeRettoCodexHooks(settings, hookPath) {
  const next = removeRettoCodexHooks(settings, hookPath);
  next.description = next.description || 'User lifecycle hooks for Codex.';
  next.hooks = next.hooks || {};
  const shim = shimPathFor(hookPath);

  for (const entry of CODEX_EVENT_STATES) {
    const command = [shim, entry.state, 'codex'].map(shellQuote).join(' ');
    const group = {
      hooks: [
        {
          type: 'command',
          command,
          timeout: entry.event === 'SessionEnd' ? 3 : 5,
          async: entry.event !== 'SessionEnd'
        }
      ]
    };
    next.hooks[entry.event] = [...(next.hooks[entry.event] || []), group];
  }

  return next;
}

function readSettings(settingsPath) {
  if (!fs.existsSync(settingsPath)) return {};
  const raw = fs.readFileSync(settingsPath, 'utf8').replace(/^\uFEFF/, '');
  if (!raw.trim()) return {};
  return JSON.parse(raw);
}

function writeSettingsAtomic(settingsPath, settings) {
  fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
  const tempPath = `${settingsPath}.reto-${process.pid}.tmp`;
  fs.writeFileSync(tempPath, `${JSON.stringify(settings, null, 2)}\n`, 'utf8');
  fs.renameSync(tempPath, settingsPath);
}

const BACKUP_KEEP = 5;

function backupSettings(settingsPath) {
  if (!fs.existsSync(settingsPath)) return undefined;
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupPath = `${settingsPath}.reto-backup-${stamp}`;
  fs.copyFileSync(settingsPath, backupPath);
  pruneBackups(settingsPath);
  return backupPath;
}

/// 설치를 돌릴 때마다 백업이 쌓이면 ~/.claude 가 지저분해진다. 최근 것만 남긴다.
function pruneBackups(settingsPath) {
  try {
    const directory = path.dirname(settingsPath);
    const prefix = `${path.basename(settingsPath)}.reto-backup-`;
    const stale = fs.readdirSync(directory)
      .filter((name) => name.startsWith(prefix))
      .sort()
      .slice(0, -BACKUP_KEEP);
    for (const name of stale) fs.rmSync(path.join(directory, name), { force: true });
  } catch {}
}

/// hook.sh 를 깔면서 설치할 때 고른 node 경로를 그 안에 적어 둔다.
/// 그 경로가 사라져도 hook.sh 가 다른 자리를 찾아보므로 훅이 멈추지는 않는다.
function installShim({ packagedShimPath, installedShimPath, nodeCommand }) {
  const template = fs.readFileSync(packagedShimPath, 'utf8');
  const body = template.replace('__RETTO_NODE__', String(nodeCommand || '').replaceAll("'", "'\\''"));
  fs.writeFileSync(installedShimPath, body, { encoding: 'utf8', mode: 0o755 });
  fs.chmodSync(installedShimPath, 0o755);
}

function installClaudeHooks({
  settingsPath,
  packagedHookPath,
  packagedShimPath,
  installedHookPath,
  nodeCommand = 'node',
  minimal = false
}) {
  const settings = readSettings(settingsPath);
  fs.mkdirSync(path.dirname(installedHookPath), { recursive: true });
  fs.copyFileSync(packagedHookPath, installedHookPath);
  const installedShimPath = shimPathFor(installedHookPath);
  installShim({ packagedShimPath, installedShimPath, nodeCommand });
  const backupPath = backupSettings(settingsPath);
  writeSettingsAtomic(settingsPath, mergeRettoHooks(settings, installedHookPath, { minimal }));
  return { settingsPath, installedHookPath, installedShimPath, backupPath };
}

function uninstallClaudeHooks({ settingsPath, installedHookPath }) {
  const settings = readSettings(settingsPath);
  const next = removeRettoHooks(settings, installedHookPath);
  const backupPath = backupSettings(settingsPath);
  writeSettingsAtomic(settingsPath, next);
  return { settingsPath, backupPath };
}

function installCodexHooks({ hooksPath, installedHookPath }) {
  const settings = readSettings(hooksPath);
  const backupPath = backupSettings(hooksPath);
  writeSettingsAtomic(hooksPath, mergeRettoCodexHooks(settings, installedHookPath));
  return { hooksPath, installedHookPath, backupPath };
}

function uninstallCodexHooks({ hooksPath, installedHookPath }) {
  const settings = readSettings(hooksPath);
  const next = removeRettoCodexHooks(settings, installedHookPath);
  const backupPath = backupSettings(hooksPath);
  writeSettingsAtomic(hooksPath, next);
  return { hooksPath, backupPath };
}

module.exports = {
  CODEX_EVENT_STATES,
  EVENT_STATES,
  REQUIRED_EVENT_STATES,
  installClaudeHooks,
  installCodexHooks,
  isRettoCodexHandler,
  isRettoHandler,
  mergeRettoCodexHooks,
  mergeRettoHooks,
  removeRettoCodexHooks,
  removeRettoHooks,
  shimPathFor,
  uninstallCodexHooks,
  uninstallClaudeHooks
};
