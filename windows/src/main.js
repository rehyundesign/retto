// 레토 Windows 판(베타)의 메인 프로세스 — 창·트레이·세션 감시·세션 열기.
//
// 상태를 아는 길은 맥 앱과 같다. 훅이 ~/.claude/retto-pet/sessions.json 에 적고, 여기서 0.25초마다 본다.
// 무엇을 보여 줄지는 core.js 가 정한다(맥 앱 Sessions.swift 를 옮긴 것).
//
// 1차 범위에서 뺀 것 — Claude 앱 사이드바로 바로 가기(맥은 접근성 API), Codex 롤아웃만으로 task 찾기,
// 스킨, 끌 때 달리는 그림. docs/windows.md 「1차에서 뺀 것」.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { app, BrowserWindow, Menu, Tray, ipcMain, nativeImage, screen, shell } = require('electron');
const core = require('./core');
const setupCheck = require('./setup-check');

const POLL_MS = 250;
const RETHINK_MS = 1000;
const PET_SIZE = { width: 280, height: 230 };

const resourcesDir = app.isPackaged ? process.resourcesPath : path.join(__dirname, '..', '..');
const assetsDir = path.join(resourcesDir, 'assets');
const hookDir = path.join(resourcesDir, 'hook');
const { petDir, settingsPath, codexHooksPath, codexHome } = setupCheck.homePaths();
const registryPath = path.join(petDir, 'sessions.json');
const statePath = () => path.join(app.getPath('userData'), 'retto-state.json');

let petWindow;
let setupWindow;
let tray;
let sessions = [];
let view;
let registryMtime = 0;
const trackingStartedAtMs = Date.now();
let local = { seen: {}, pinnedId: null, clickThrough: false, position: null, setupShown: false };

function loadLocal() {
  try { local = { ...local, ...JSON.parse(fs.readFileSync(statePath(), 'utf8')) }; } catch {}
}

function saveLocal() {
  try {
    fs.mkdirSync(path.dirname(statePath()), { recursive: true });
    fs.writeFileSync(statePath(), JSON.stringify(local, null, 2));
  } catch {}
}

// ── 훅 설치 ────────────────────────────────────────────────────────────────

/// hook/install.cjs 와 같은 일을 앱 안에서 한다. 훅을 까는 데에는 사용자 node 가 필요 없다 —
/// Electron 이 node 다. 훅을 돌릴 때만 PATH 의 node 를 쓴다.
function installHooks() {
  // 맥에서 npm start 로 띄운 경우 맥 훅은 scripts/install-hooks.sh 가 맡는다. 여기서 다시 쓰면
  // hook.sh 에 적어 둔 node 자리가 그냥 `node` 로 바뀐다.
  if (process.platform !== 'win32') throw new Error('맥·리눅스는 scripts/install-hooks.sh 로 설치한다');
  const settings = require(path.join(hookDir, 'lib', 'hook-settings.js'));
  const versions = require(path.join(hookDir, 'lib', 'claude-versions.js'));
  const { minimal, reason } = versions.decideEventScope([]);
  settings.installClaudeHooks({
    settingsPath,
    packagedHookPath: path.join(hookDir, 'hook.cjs'),
    packagedShimPath: path.join(hookDir, 'hook.sh'),
    installedHookPath: path.join(petDir, 'hook.cjs'),
    minimal,
    platform: process.platform
  });
  const codex = fs.existsSync(codexHome);
  if (codex) settings.installCodexHooks({ hooksPath: codexHooksPath, installedHookPath: path.join(petDir, 'hook.cjs'), platform: process.platform });
  return {
    reason,
    claude: versions.eventCountFor(minimal),
    codex: codex ? settings.CODEX_EVENT_STATES.length : 0
  };
}

function uninstallHooks() {
  const settings = require(path.join(hookDir, 'lib', 'hook-settings.js'));
  const installedHookPath = path.join(petDir, 'hook.cjs');
  settings.uninstallClaudeHooks({ settingsPath, installedHookPath });
  settings.uninstallCodexHooks({ hooksPath: codexHooksPath, installedHookPath });
  // install.cjs --uninstall 과 같게 깔아 둔 훅 파일도 지운다. 세션 기록은 남긴다.
  for (const leftover of [settings.shimPathFor(installedHookPath), installedHookPath]) fs.rmSync(leftover, { force: true });
}

function expectedHookCounts() {
  try {
    const settings = require(path.join(hookDir, 'lib', 'hook-settings.js'));
    const versions = require(path.join(hookDir, 'lib', 'claude-versions.js'));
    const { minimal } = versions.decideEventScope([]);
    return { expectedClaudeHooks: versions.eventCountFor(minimal), expectedCodexHooks: settings.CODEX_EVENT_STATES.length };
  } catch {
    return {};
  }
}

// ── 세션 감시 ──────────────────────────────────────────────────────────────

function readSessions() {
  let stat;
  try { stat = fs.statSync(registryPath); } catch { sessions = []; registryMtime = 0; return false; }
  if (stat.mtimeMs === registryMtime) return false;
  let text;
  try { text = fs.readFileSync(registryPath, 'utf8'); } catch { return false; }
  const parsed = core.readRegistry(text);
  // 훅이 쓰는 도중에 읽으면 깨진 JSON 이 올 수 있다. 그때는 지난 값을 그대로 두고 다음에 다시 읽는다.
  if (!parsed) return false;
  sessions = parsed;
  registryMtime = stat.mtimeMs;
  return true;
}

function transcriptModifiedAt(session) {
  if (!session.transcriptPath) return undefined;
  try { return fs.statSync(session.transcriptPath).mtimeMs; } catch { return undefined; }
}

function rethink() {
  view = core.chooseView({
    sessions,
    seen: local.seen,
    pinnedId: local.pinnedId,
    nowMs: Date.now(),
    trackingStartedAtMs,
    transcriptModifiedAt
  });
  if (Object.keys(view.newlySeen).length) {
    local.seen = { ...local.seen, ...view.newlySeen };
    saveLocal();
  }
  if (local.pinnedId && !view.keepPin) {
    local.pinnedId = null;
    saveLocal();
  }
  sendView();
  rebuildTrayMenu();
}

function sendView() {
  if (!petWindow || petWindow.isDestroyed()) return;
  const selected = view?.selected;
  let bubble;
  if (!selected) {
    const problems = setupProblems();
    bubble = { kicker: 'ZZZ', title: '레토', message: problems.length ? `연동 확인이 필요해 · ${problems.join(' · ')}` : 'Claude Code나 Codex를 켜면 여기서 알려줄게', tone: 'quiet' };
  } else if (view.asleep) {
    bubble = { kicker: 'ZZZ', title: '레토', message: '쿨쿨…', tone: 'quiet' };
  } else {
    const animation = core.ANIMATIONS[selected.visibleState];
    bubble = {
      kicker: animation.kicker,
      title: core.sessionTitle(selected),
      message: selected.lastAssistantMessage && selected.visibleState === 'waving'
        ? String(selected.lastAssistantMessage).slice(0, 80)
        : animation.title,
      project: core.projectName(selected),
      tone: animation.tone
    };
  }
  const pose = view?.pose || 'sleeping';
  petWindow.webContents.send('view', {
    pose,
    animation: core.ANIMATIONS[pose],
    sprite: core.SPRITE,
    bubble: { ...bubble, colors: core.TONES[bubble.tone] },
    badge: view?.badgeCount || 0,
    pinned: Boolean(local.pinnedId),
    clickThrough: local.clickThrough
  });
}

// ── 세션 열기 ──────────────────────────────────────────────────────────────

/// 맥 앱 OpenTarget.swift 와 같은 순서. VS Code 는 그 세션의 폴더 창을 먼저 앞으로 보내고,
/// 자리를 잡은 뒤 세션 딥링크를 보낸다. 창을 먼저 보내지 않으면 딥링크가 마지막 창에 가서
/// 같은 대화가 새 패널로 한 번 더 열린다(docs/세션-열기.md).
async function openSession(session) {
  if (!session) return;
  const rawId = session.rawSessionId || session.sessionId || session.id;
  markSeen(session);
  if (session.source === 'codex' || session.client === 'codex') {
    if (rawId) await shell.openExternal(`codex://threads/${encodeURIComponent(rawId)}`).catch(() => {});
    return;
  }
  // Claude 앱 세션은 세션 딥링크가 없다(맥에서 확인한 사실). 1차에서는 VS Code 로 보낸다 — 맥의 fallback 순서와 다르다.
  // 작업 폴더를 모르면 폴더 창만 열고 세션 딥링크는 보내지 않는다. 딥링크가 엉뚱한 창으로 가서
  // 같은 대화가 새 패널로 하나 더 열리는 것보다 창만 앞으로 오는 편이 낫다(docs/세션-열기.md).
  //
  // 맥은 그 창이 실제로 앞에 왔는지 확인한 뒤 딥링크를 보낸다. Windows 는 아직 그 확인이 없어 1.2초를 기다린다.
  if (!session.cwd) return;
  const opened = await shell.openExternal(core.vscodeFolderUrl(session.cwd)).then(() => true, () => false);
  if (!opened || !rawId) return;
  setTimeout(() => {
    shell.openExternal(`vscode://anthropic.claude-code/open?session=${encodeURIComponent(rawId)}`).catch(() => {});
  }, 1200);
}


function markSeen(session) {
  if (!session?.id) return;
  const live = new Set(sessions.map((item) => item.id));
  const seen = Object.fromEntries(Object.entries(local.seen).filter(([id]) => live.has(id)));
  seen[session.id] = Math.max(session.updatedAtMs || 0, Date.now());
  local.seen = seen;
  saveLocal();
  rethink();
}

function clearAttention() {
  for (const session of view?.badgeSessions || []) {
    local.seen[session.id] = Math.max(session.updatedAtMs || 0, Date.now());
  }
  saveLocal();
  rethink();
}

// ── 창 ────────────────────────────────────────────────────────────────────

function defaultPosition() {
  const area = screen.getPrimaryDisplay().workArea;
  return { x: area.x + area.width - PET_SIZE.width - 24, y: area.y + area.height - PET_SIZE.height - 8 };
}

/// 저장한 자리가 지금 연결된 화면 밖이면(모니터를 뺐다) 기본 자리로 돌린다.
function onScreen(position) {
  if (!position) return false;
  return screen.getAllDisplays().some(({ workArea: a }) =>
    position.x + PET_SIZE.width / 2 >= a.x && position.x + PET_SIZE.width / 2 <= a.x + a.width
    && position.y + PET_SIZE.height / 2 >= a.y && position.y + PET_SIZE.height / 2 <= a.y + a.height);
}

function createPetWindow() {
  const position = onScreen(local.position) ? local.position : defaultPosition();
  petWindow = new BrowserWindow({
    ...PET_SIZE,
    ...position,
    frame: false,
    transparent: true,
    resizable: false,
    maximizable: false,
    minimizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    hasShadow: false,
    focusable: false,
    alwaysOnTop: true,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });
  petWindow.setAlwaysOnTop(true, 'floating');
  petWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  petWindow.setIgnoreMouseEvents(local.clickThrough, { forward: true });
  const query = new URLSearchParams({
    sprite: pathToFileURL(path.join(assetsDir, 'spritesheet.webp')).href,
    font: pathToFileURL(path.join(assetsDir, 'NanumMiNiSonGeurSsi.ttf')).href
  });
  petWindow.loadFile(path.join(__dirname, 'pet.html'), { search: query.toString() });
  petWindow.once('ready-to-show', () => { petWindow.showInactive(); sendView(); });
  petWindow.on('moved', rememberPosition);
}

function openSetupWindow() {
  if (setupWindow && !setupWindow.isDestroyed()) { setupWindow.show(); setupWindow.focus(); return; }
  setupWindow = new BrowserWindow({
    width: 520,
    height: 560,
    title: 'Retto 연동 확인',
    autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true }
  });
  setupWindow.loadFile(path.join(__dirname, 'setup.html'));
}

function setupReport() {
  return setupCheck.inspect(expectedHookCounts());
}

/// 메인 스레드에서 매초 where.exe 를 띄우지 않도록 30초 동안 결과를 쓴다. 설치·제거 뒤에는 비운다.
let problemsCache = { at: 0, value: [] };
function setupProblems() {
  if (Date.now() - problemsCache.at < 30000) return problemsCache.value;
  let value = [];
  try { value = setupReport().problems.filter((problem) => problem !== '소식 없음'); } catch {}
  problemsCache = { at: Date.now(), value };
  return value;
}

// ── 트레이 메뉴 ────────────────────────────────────────────────────────────

let lastMenuKey = '';

function rebuildTrayMenu() {
  if (!tray) return;
  const listed = (view?.sessions || []).filter((session) => !session.isClosed).slice(0, 12);
  const key = JSON.stringify([listed.map((session) => [session.id, session.visibleState, core.sessionTitle(session)]), local.pinnedId, local.clickThrough, view?.badgeCount]);
  if (key === lastMenuKey) return;
  lastMenuKey = key;
  const sessionItems = listed.length
    ? listed.map((session) => ({
      label: core.menuLabel({ ...session, state: session.visibleState }),
      type: 'radio',
      checked: local.pinnedId === session.id,
      click: () => { local.pinnedId = session.id; saveLocal(); rethink(); }
    }))
    : [{ label: '실행 중인 세션 없음', enabled: false }];
  const menu = Menu.buildFromTemplate([
    { label: '지금 세션 열기', enabled: Boolean(view?.selected), click: () => openSession(view?.selected) },
    { type: 'separator' },
    ...sessionItems,
    { label: '자동으로 급한 세션 따라가기', type: 'radio', checked: !local.pinnedId, click: () => { local.pinnedId = null; saveLocal(); rethink(); } },
    { type: 'separator' },
    { label: `완료 알림 모두 읽음${view?.badgeCount ? ` (${view.badgeCount})` : ''}`, enabled: Boolean(view?.badgeCount), click: clearAttention },
    { label: '클릭 통과', type: 'checkbox', checked: local.clickThrough, click: (item) => setClickThrough(item.checked) },
    { label: 'Windows 시작 시 실행', type: 'checkbox', checked: app.getLoginItemSettings().openAtLogin, click: (item) => app.setLoginItemSettings({ openAtLogin: item.checked }) },
    { type: 'separator' },
    { label: `AI 연동 확인${setupProblems().length ? ` — ${setupProblems().join(' · ')}` : ''}`, click: openSetupWindow },
    { label: '레토 위치 처음으로', click: () => { const p = defaultPosition(); petWindow.setPosition(p.x, p.y); rememberPosition(); } },
    { label: `Retto ${app.getVersion()} (베타)`, enabled: false },
    { label: '종료', role: 'quit' }
  ]);
  tray.setContextMenu(menu);
  tray.setToolTip(view?.selected ? `Retto · ${core.menuLabel({ ...view.selected, state: view.selected.visibleState })}` : 'Retto');
}

function setClickThrough(on) {
  local.clickThrough = on;
  saveLocal();
  petWindow.setIgnoreMouseEvents(on, { forward: true });
  lastMenuKey = '';
  rethink();
}

// ── IPC ───────────────────────────────────────────────────────────────────

ipcMain.on('pet:open', () => openSession(view?.selected));
ipcMain.on('pet:menu', () => { lastMenuKey = ''; rebuildTrayMenu(); tray?.popUpContextMenu(); });
ipcMain.on('pet:drag', (_event, { dx, dy }) => {
  if (!petWindow) return;
  const [x, y] = petWindow.getPosition();
  petWindow.setPosition(Math.round(x + dx), Math.round(y + dy));
  rememberPosition();
});

/// Windows 는 프로그램이 부른 setPosition 에 'moved' 를 내지 않는다. 끄는 동안은 모았다가 멈추면 저장한다.
let positionTimer = null;
function rememberPosition() {
  clearTimeout(positionTimer);
  positionTimer = setTimeout(() => {
    if (!petWindow || petWindow.isDestroyed()) return;
    const [x, y] = petWindow.getPosition();
    local.position = { x, y };
    saveLocal();
  }, 400);
}
ipcMain.handle('setup:report', () => {
  const report = setupReport();
  return { ...report, platform: process.platform, version: app.getVersion(), home: os.homedir() };
});
ipcMain.handle('setup:install', () => {
  try {
    const result = installHooks();
    problemsCache.at = 0;
    lastMenuKey = '';
    rethink();
    return { ok: true, ...result };
  } catch (error) {
    return { ok: false, error: String(error?.message || error) };
  }
});
ipcMain.handle('setup:uninstall', () => {
  try { uninstallHooks(); problemsCache.at = 0; return { ok: true }; } catch (error) { return { ok: false, error: String(error?.message || error) }; }
});
ipcMain.on('setup:open-url', (_event, url) => {
  if (typeof url === 'string' && /^https:\/\//.test(url)) shell.openExternal(url);
});

// ── 시작 ──────────────────────────────────────────────────────────────────

// 미리보기 모드는 무슨 일이 있었는지 파일로 남긴다. Windows 의 GUI 앱은 stdout 이 어디에도 안 남아,
// CI 에서 앱이 그림 없이 끝났을 때 원인을 알 길이 없었다(2026-11-03 첫 CI).
const previewOut = process.argv.includes('--render-preview')
  ? (process.argv[process.argv.indexOf('--render-preview') + 1] || path.join(os.tmpdir(), 'retto-windows-preview.png'))
  : null;
function previewLog(message) {
  if (!previewOut) return;
  try { fs.appendFileSync(`${previewOut}.log`, `${new Date().toISOString()} ${message}\n`); } catch {}
}
if (previewOut) {
  previewLog(`start argv=${JSON.stringify(process.argv)} home=${os.homedir()}`);
  process.on('uncaughtException', (error) => { previewLog(`uncaught ${error?.stack || error}`); app.exit(3); });
  process.on('unhandledRejection', (error) => previewLog(`unhandled ${error?.stack || error}`));
  app.on('render-process-gone', (_event, _contents, details) => previewLog(`renderer gone ${JSON.stringify(details)}`));
  app.on('child-process-gone', (_event, details) => previewLog(`child gone ${JSON.stringify(details)}`));
  app.on('will-quit', () => previewLog('will-quit'));
}

const gotLock = app.requestSingleInstanceLock();
previewLog(`single-instance lock=${gotLock} userData=${app.getPath('userData')} exists=${fs.existsSync(app.getPath('userData'))}`);
// GitHub Actions 의 Windows 러너에서는 다른 레토가 없는데도 잠금이 false 로 온다(2026-11-03 CI 로그).
// 미리보기는 몇 초 뒤 스스로 끝나는 진단이라 잠금 없이 그린다. 실제 PC 에서도 false 가 오는지는 실기로 본다.
if (!gotLock && !previewOut) {
  app.quit();
} else {
  app.on('second-instance', openSetupWindow);
  app.whenReady().then(() => {
    loadLocal();
    if (process.platform === 'darwin') app.dock?.hide();
    tray = new Tray(nativeImage.createFromPath(path.join(assetsDir, 'icon.png')).resize({ width: 16, height: 16 }));
    tray.on('click', () => openSession(view?.selected));
    createPetWindow();
    readSessions();
    rethink();
    setInterval(() => { if (readSessions()) rethink(); }, POLL_MS);
    setInterval(rethink, RETHINK_MS);
    // 진단 — 화면을 PNG 로 남기고 끝낸다(맥 앱 --render-preview 와 같은 이름). CI 가 Windows 에서 쓴다.
    if (previewOut) {
      const out = previewOut;
      previewLog('ready');
      // 무엇이 실패해도 끝나야 한다. CI 가 끝나지 않는 앱을 기다리며 멈추지 않게.
      setTimeout(() => app.exit(2), 20000);
      setTimeout(async () => {
        try {
          const image = await petWindow.webContents.capturePage();
          previewLog(`captured empty=${image.isEmpty()} size=${JSON.stringify(image.getSize())}`);
          fs.writeFileSync(out, image.toPNG());
          console.log(JSON.stringify({ ok: true, out, pose: view?.pose, badge: view?.badgeCount, problems: setupProblems() }));
          app.exit(0);
        } catch (error) {
          previewLog(`capture failed ${error?.stack || error}`);
          app.exit(1);
        }
      }, 2500);
      return;
    }
    // 처음 켤 때는 연동 확인 창을 띄운다. 맥 앱과 같다 — 훅이 안 걸렸으면 레토는 그냥 자고 있을 뿐이라
    // 받은 사람이 고장인지 알 수 없다.
    if (!local.setupShown || setupProblems().length) {
      local.setupShown = true;
      saveLocal();
      openSetupWindow();
    }
  });
  // 창을 다 닫아도 트레이에 남는다. 종료는 메뉴에서.
  app.on('window-all-closed', () => {});
}
