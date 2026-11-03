// 레토 그리기와 마우스. 상태 판정은 메인 프로세스(core.js)가 하고, 여기는 받은 대로 그린다.

const params = new URLSearchParams(location.search);
const canvas = document.getElementById('pet');
const context = canvas.getContext('2d');
const bubble = document.getElementById('bubble');
const tag = document.getElementById('tag');
const titleEl = document.getElementById('title');
const messageEl = document.getElementById('message');
const badge = document.getElementById('badge');

const font = new FontFace('Retto Hand', `url("${params.get('font')}")`);
font.load().then((loaded) => document.fonts.add(loaded)).catch(() => {});

const sheet = new Image();
sheet.src = params.get('sprite');

let current = null;
let frame = 0;
let cycles = 0;
let timer = null;

function draw() {
  if (!current || !sheet.complete || !sheet.naturalWidth) return;
  const { animation, sprite } = current;
  context.clearRect(0, 0, canvas.width, canvas.height);
  context.drawImage(
    sheet,
    frame * sprite.cellWidth, animation.row * sprite.cellHeight, sprite.cellWidth, sprite.cellHeight,
    0, 0, canvas.width, canvas.height
  );
}

function tick() {
  const { animation } = current;
  frame += 1;
  if (frame >= animation.frames) {
    cycles += 1;
    // 완료 손 흔들기는 두 번만 흔들고 마지막 칸에서 멈춘다(맥 앱 cycleLimit).
    if (animation.cycleLimit && cycles >= animation.cycleLimit) {
      frame = animation.frames - 1;
      clearInterval(timer);
      timer = null;
      draw();
      return;
    }
    frame = 0;
  }
  draw();
}

function restart() {
  clearInterval(timer);
  frame = 0;
  cycles = 0;
  draw();
  timer = setInterval(tick, current.animation.interval * 1000);
}

sheet.onload = draw;

window.retto.onView((next) => {
  const poseChanged = !current || current.pose !== next.pose;
  current = next;
  if (poseChanged) restart();

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

// 누르면 그 세션으로, 끌면 레토를 옮긴다. 4px 넘게 움직이면 끄는 것으로 본다.
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
  window.retto.drag(dx, dy);
});

canvas.addEventListener('pointerup', () => {
  if (press && !press.moved) window.retto.open();
  press = null;
});

window.addEventListener('contextmenu', (event) => {
  event.preventDefault();
  window.retto.menu();
});
