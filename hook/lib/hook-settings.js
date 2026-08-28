const fs = require('node:fs');
const path = require('node:path');

const EVENT_STATES = [
  { event: 'SessionStart', state: 'idle' },
  { event: 'UserPromptSubmit', state: 'running' },
  { event: 'PreToolUse', state: 'running' },
  { event: 'PostToolUse', state: 'running' },
  { event: 'PostToolBatch', state: 'running' },
  { event: 'PermissionRequest', state: 'waiting' },
  { event: 'Notification', matcher: 'permission_prompt|agent_needs_input', state: 'waiting' },
  { event: 'Elicitation', state: 'waiting' },
  { event: 'PostToolUseFailure', state: 'failed' },
  { event: 'PermissionDenied', state: 'failed' },
  { event: 'SubagentStart', state: 'running' },
  { event: 'SubagentStop', state: 'running' },
  { event: 'TaskCreated', state: 'running' },
  { event: 'TaskCompleted', state: 'review' },
  { event: 'Stop', state: 'waving' },
  { event: 'StopFailure', state: 'failed' },
  { event: 'SessionEnd', state: 'idle' }
];

// 이름을 Retto 로 바로잡으면서 설치 폴더가 reto-pet → retto-pet 으로 바뀌었다.
// settings.json 에는 절대 경로가 박혀 있으므로, 옛 경로도 계속 알아봐야
// 갱신·제거할 때 죽은 항목 17개가 그대로 남는 일이 없다.
const HOOK_PATH_MARKERS = ['.claude/retto-pet/hook.cjs', '.claude/reto-pet/hook.cjs'];

function isRettoHandler(handler, hookPath) {
  if (!handler || handler.type !== 'command') return false;
  const args = Array.isArray(handler.args) ? handler.args : [];
  return args.includes(hookPath) || args.some((arg) =>
    typeof arg === 'string' && HOOK_PATH_MARKERS.some((marker) => arg.includes(marker))
  );
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

function mergeRettoHooks(settings, hookPath, nodeCommand = 'node') {
  const next = removeRettoHooks(settings, hookPath);
  next.hooks = next.hooks || {};

  for (const entry of EVENT_STATES) {
    const group = {
      ...(entry.matcher ? { matcher: entry.matcher } : {}),
      hooks: [
        {
          type: 'command',
          command: nodeCommand,
          args: [hookPath, entry.state],
          timeout: 5,
          async: true
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

function installClaudeHooks({ settingsPath, packagedHookPath, installedHookPath, nodeCommand = 'node' }) {
  const settings = readSettings(settingsPath);
  fs.mkdirSync(path.dirname(installedHookPath), { recursive: true });
  fs.copyFileSync(packagedHookPath, installedHookPath);
  const backupPath = backupSettings(settingsPath);
  writeSettingsAtomic(settingsPath, mergeRettoHooks(settings, installedHookPath, nodeCommand));
  return { settingsPath, installedHookPath, backupPath };
}

function uninstallClaudeHooks({ settingsPath, installedHookPath }) {
  const settings = readSettings(settingsPath);
  const next = removeRettoHooks(settings, installedHookPath);
  const backupPath = backupSettings(settingsPath);
  writeSettingsAtomic(settingsPath, next);
  return { settingsPath, backupPath };
}

module.exports = {
  EVENT_STATES,
  installClaudeHooks,
  isRettoHandler,
  mergeRettoHooks,
  removeRettoHooks,
  uninstallClaudeHooks
};
