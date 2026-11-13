// 레토 그리기와 마우스. 상태 판정은 메인 프로세스(core.js)가 하고, 여기는 받은 대로 그린다.
//
// 스킨이 있으면 맥 앱이 내보낸 클립을 재생한다(macos/Sources/WindowsSkinExport.swift). 어느 클립을 언제 고를지는
// 맥 앱 PetView.swift 를 옮겼다 — 끄는 동안 좌우 달리기, 커서 쪽 시선(16방향, 멈추면 0.8초 뒤 해제),
// 누르면 점프 한 바퀴, 완료 손 흔들기가 끝나면 쉬는 자세. 스킨이 없으면 기본 아틀라스 한 장으로 그린다.

const params = new URLSearchParams(location.search);
const canvas = document.getElementById('pet');
const context = canvas.getContext('2d');
const bubble = document.getElementById('bubble');
const tag = document.getElementById('tag');
const titleEl = document.getElementById('title');
const messageEl = document.getElementById('message');
const badge = document.getElementById('badge');

/// 내보낸 프레임 1px 을 화면 0.5px 로 그린다. 프레임은 맥 배율 0.8 로 그렸으므로 고해상도 화면에서도 선명하다.
const DISPLAY = 0.5;
const GAZE_HOLD_MS = 800;        // Geometry.swift gazeHoldDuration
const GAZE_STEP_MS = 60;         // christmasGazeStepDuration
const GAZE_HYSTERESIS = 4;       // gazeDirectionHysteresisDegrees
const GAZE_STATES = new Set(['idle']);

const font = new FontFace('Retto Hand', `url("${params.get('font')}")`);
font.load().then((loaded) => document.fonts.add(loaded)).catch(() => {});

const sheet = new Image();
sheet.src = params.get('sprite');

let current = null;
let skinKey = '';
const images = new Map();
let clipName = null;
let clipStartedAt = 0;
let restClip = null;       // 한 번만 도는 클립이 끝난 뒤 머무는 클립(완료 → 쉬는 자세)
let reactionUntil = 0;     // 누른 뒤 점프 한 바퀴
let dragDirection = null;  // 'drag-left' · 'drag-right'
let dragStoppedAt = 0;
let gaze = null;           // { current, target, lastMoveAt }

// 스프라이트 한 장(스킨 없음)용 상태.
let frame = 0;
let cycles = 0;
let timer = null;

function image(file) {
  const url = current.skin.base + file;
  let entry = images.get(url);
  if (!entry) { entry = new Image(); entry.src = url; images.set(url, entry); }
  return entry;
}

function layoutForSkin(skin) {
  const root = document.body.style;
  if (!skin) {
    canvas.width = 224; canvas.height = 240;
    root.setProperty('--pet-w', '112px'); root.setProperty('--pet-h', '120px');
    root.setProperty('--pet-top', '-26px'); root.setProperty('--pet-right', '52px');
    return;
  }
  canvas.width = skin.frameWidth; canvas.height = skin.frameHeight;
  root.setProperty('--pet-w', `${skin.frameWidth * DISPLAY}px`);
  root.setProperty('--pet-h', `${skin.frameHeight * DISPLAY}px`);
  root.setProperty('--pet-top', `${skin.petRect.y * DISPLAY}px`);
  root.setProperty('--pet-right', `${(skin.petRect.x + skin.petRect.width - skin.frameWidth / 2) * DISPLAY}px`);
}

// ── 맥 앱 Geometry.swift gazeDirection · nextGazeDirection ───────────────────
function gazeDirection(dx, dy, previous) {
  const sector = 360 / 16;
  const degrees = ((Math.atan2(dx, dy) * 180) / Math.PI + 360) % 360;
  const nearest = Math.round(degrees / sector) % 16;
  if (previous == null) return nearest;
  const offset = Math.abs(((degrees - previous * sector + 540) % 360) - 180);
  return offset <= sector / 2 + GAZE_HYSTERESIS ? previous : nearest;
}

function nextGazeDirection(from, toward) {
  const clockwise = (toward - from + 16) % 16;
  if (clockwise === 0) return from;
  return (from + (clockwise <= 8 ? 1 : -1) + 16) % 16;
}

/// 지금 그릴 클립. 끄는 중 → 시선 → 누른 반응 → 상태 순서다(PetView.draw 와 같다).
function chooseClip(now) {
  const clips = current.skin.clips;
  if (dragDirection && clips[dragDirection]) return dragDirection;
  if (now < reactionUntil && clips.jumping) return 'jumping';
  return restClip || current.pose;
}

/// 위상을 이어 가는 클립 묶음. 아무·란은 작업 중과 도구 사용이 같은 동작이라 바꿔도 처음부터 돌지 않는다
/// (맥 PetView.apply 의 amu work 묶음).
function motionGroup(skinId, name) {
  return skinId === 'amuRan' && (name === 'running' || name === 'review') ? 'amu-work' : name;
}

/// 지금 화면에 보이는 자세. 완료 뒤 쉬는 자세로 넘어갔으면 쉬는 중이다(맥 visibleState).
function visiblePose() { return restClip || current.pose; }

function drawSkin(now) {
  const skin = current.skin;
  const wanted = chooseClip(now);
  if (wanted !== clipName) {
    if (motionGroup(skin.id, wanted) !== motionGroup(skin.id, clipName)) clipStartedAt = now;
    clipName = wanted;
  }
  let name = clipName;
  let clip = skin.clips[name];
  if (!clip) return;
  let index = Math.floor(((now - clipStartedAt) / 1000) * clip.fps);
  if (name === 'jumping' && now < reactionUntil) {
    index = Math.min(index, (clip.cycleFrames || clip.frames) - 1);
  } else if (index >= clip.frames) {
    if (clip.loop) {
      index %= clip.frames;
    } else if (clip.then && skin.clips[clip.then]) {
      // 완료 손 흔들기는 정해진 횟수만 흔들고 쉬는 자세로 넘어간다. 다음 상태가 올 때까지 거기 머문다.
      restClip = clip.then;
      clipName = restClip; clipStartedAt = now;
      name = restClip; clip = skin.clips[name]; index = 0;
    } else {
      index = clip.frames - 1;
    }
  }
  // 시선은 쉬는 자세일 때 커서 쪽 방향 그림 한 장으로 바꾼다.
  if (gaze && skin.clips.gaze && GAZE_STATES.has(visiblePose()) && !dragDirection && now >= reactionUntil) {
    clip = skin.clips.gaze; index = gaze.current;
  }
  const picture = image(clip.file);
  if (!picture.complete || !picture.naturalWidth) return;
  const column = index % clip.columns;
  const row = Math.floor(index / clip.columns);
  context.clearRect(0, 0, canvas.width, canvas.height);
  context.drawImage(picture, column * skin.frameWidth, row * skin.frameHeight, skin.frameWidth, skin.frameHeight,
    0, 0, canvas.width, canvas.height);
}

let lastGazeStep = 0;
function loop(now) {
  if (current?.skin) {
    if (gaze) {
      // 시선이 풀리면 맥처럼 동작을 처음부터 다시 돈다(PetView.clearGaze → restartAnimation).
      if (now - gaze.lastMoveAt > GAZE_HOLD_MS) { gaze = null; clipStartedAt = now; }
      else if (now - lastGazeStep >= GAZE_STEP_MS) { gaze.current = nextGazeDirection(gaze.current, gaze.target); lastGazeStep = now; }
    }
    if (dragDirection && now - dragStoppedAt > 150 && !press) dragDirection = null;
    drawSkin(now);
  }
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);

// ── 스킨이 없을 때: 기본 아틀라스 한 장 ───────────────────────────────────────
function drawSheet() {
  if (!current || current.skin || !sheet.complete || !sheet.naturalWidth) return;
  const { animation, sprite } = current;
  context.clearRect(0, 0, canvas.width, canvas.height);
  context.drawImage(sheet, frame * sprite.cellWidth, animation.row * sprite.cellHeight, sprite.cellWidth, sprite.cellHeight,
    0, 0, canvas.width, canvas.height);
}

function tick() {
  const { animation } = current;
  frame += 1;
  if (frame >= animation.frames) {
    cycles += 1;
    if (animation.cycleLimit && cycles >= animation.cycleLimit) {
      frame = animation.frames - 1;
      clearInterval(timer); timer = null; drawSheet();
      return;
    }
    frame = 0;
  }
  drawSheet();
}

function restartSheet() {
  clearInterval(timer);
  frame = 0; cycles = 0;
  drawSheet();
  if (!current.skin) timer = setInterval(tick, current.animation.interval * 1000);
}

sheet.onload = drawSheet;

window.retto.onView((next) => {
  const poseChanged = !current || current.pose !== next.pose;
  const nextSkinKey = next.skin ? next.skin.id : '';
  const skinChanged = nextSkinKey !== skinKey;
  current = next;
  if (skinChanged) {
    skinKey = nextSkinKey;
    images.clear();
    layoutForSkin(next.skin);
    clipName = null; restClip = null; gaze = null;
  }
  if (poseChanged || skinChanged) {
    restClip = null;
    if (next.skin) clearInterval(timer); else restartSheet();
  }

  const { bubble: b } = next;
  tag.textContent = b.kicker;
  tag.style.background = b.colors.background;
  tag.style.color = b.colors.text;
  titleEl.textContent = b.project ? `${b.title} · ${b.project}` : b.title;
  messageEl.textContent = b.message;
  bubble.style.opacity = next.clickThrough ? '.85' : '1';

  badge.style.display = next.badge > 0 ? 'block' : 'none';
  badge.textContent = String(next.badge);
});

// ── 마우스: 누르면 그 세션으로, 끌면 레토를 옮긴다. 4px 넘게 움직이면 끄는 것으로 본다. ──
let press = null;

canvas.addEventListener('pointerdown', (event) => {
  if (event.button !== 0) return;
  press = { x: event.screenX, y: event.screenY, moved: false };
  canvas.setPointerCapture(event.pointerId);
});

canvas.addEventListener('pointermove', (event) => {
  if (!press) return;
  const dx = event.screenX - press.x;
  const dy = event.screenY - press.y;
  if (!press.moved && Math.hypot(dx, dy) < 4) return;
  press.moved = true;
  press.x = event.screenX;
  press.y = event.screenY;
  if (Math.abs(dx) >= 1) dragDirection = dx > 0 ? 'drag-right' : 'drag-left';
  dragStoppedAt = performance.now();
  gaze = null;
  window.retto.drag(dx, dy);
});

canvas.addEventListener('pointerup', () => {
  if (press && !press.moved) {
    // 누른 반응 — 점프 한 바퀴(PetView.playReaction). 반응을 보여 주고 세션을 연다.
    const jumping = current?.skin?.clips?.jumping;
    if (jumping) reactionUntil = performance.now() + ((jumping.cycleFrames || jumping.frames) / jumping.fps) * 1000;
    gaze = null;
    window.retto.open();
  }
  press = null;
  dragStoppedAt = performance.now();
});

// 커서 쪽을 본다. 맥처럼 레토 창 위에서 움직일 때만, 몸 중심에서 조금 떨어졌을 때만.
document.addEventListener('pointermove', (event) => {
  const skin = current?.skin;
  if (!skin || !skin.clips.gaze || press || !GAZE_STATES.has(visiblePose())) return;
  const rect = canvas.getBoundingClientRect();
  const centerX = rect.left + (skin.petRect.x + skin.petRect.width / 2) * DISPLAY;
  const centerY = rect.top + (skin.petRect.y + skin.petRect.height / 2) * DISPLAY;
  const dx = event.clientX - centerX;
  const dy = centerY - event.clientY;
  if (Math.hypot(dx, dy) <= 22 * 0.8 * DISPLAY) return;
  const target = gazeDirection(dx, dy, gaze ? gaze.target : null);
  if (!gaze) gaze = { current: target, target, lastMoveAt: performance.now() };
  gaze.target = target;
  gaze.lastMoveAt = performance.now();
});

window.addEventListener('contextmenu', (event) => {
  event.preventDefault();
  window.retto.menu();
});
