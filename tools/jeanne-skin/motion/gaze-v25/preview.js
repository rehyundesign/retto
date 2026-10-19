'use strict';
const gazeData = window.JeanneGaze25;
const gazeCache25 = Date.now().toString(36);
const gazeArea = document.getElementById('gaze-area');
const gazeImage = document.getElementById('gaze-image');
const gazeLabel = document.getElementById('gaze-current');
const gazeButtons = document.getElementById('gaze-buttons');
const gazeAuto = document.getElementById('gaze-auto');
let gazeSelected = 0, gazeAutomatic = false, gazeEpoch = performance.now();
function gazeDirection25(dx, dy, previous) {
  const degrees = (Math.atan2(dx, dy) * 180 / Math.PI + 360) % 360;
  const nearest = Math.round(degrees / 22.5) % 16;
  if (previous === null) return nearest;
  const offset = Math.abs((degrees - previous * 22.5 + 540) % 360 - 180);
  return offset <= 15.25 ? previous : nearest;
}
function showGaze25(direction) {
  gazeSelected = direction;
  const cell = gazeData[direction];
  if (gazeImage.dataset.src !== cell.file) {
    gazeImage.src = cell.file + '?rev=' + gazeCache25;
    gazeImage.dataset.src = cell.file;
  }
  gazeLabel.textContent = cell.label + ' · ' + (direction + 1) + ' / 16';
  [...gazeButtons.children].forEach((button, i) => button.classList.toggle('active', i === direction));
}
gazeData.forEach((cell, direction) => {
  const button = document.createElement('button');
  button.textContent = cell.label;
  button.onclick = () => {
    gazeAutomatic = false;
    gazeAuto.textContent = '방향 순서대로 보기';
    showGaze25(direction);
  };
  gazeButtons.append(button);
});
gazeArea.addEventListener('pointermove', event => {
  const rect = gazeImage.getBoundingClientRect();
  const scale = rect.width / 224;
  const dx = (event.clientX - rect.left - rect.width / 2) / scale;
  const dy = (rect.top + rect.height / 2 - event.clientY) / scale;
  if (Math.hypot(dx, dy) <= 22) return;
  gazeAutomatic = false;
  gazeAuto.textContent = '방향 순서대로 보기';
  showGaze25(gazeDirection25(dx, dy, gazeSelected));
});
gazeAuto.onclick = () => {
  gazeAutomatic = !gazeAutomatic;
  gazeEpoch = performance.now() - gazeSelected * 200;
  gazeAuto.textContent = gazeAutomatic ? '방향 고정' : '방향 순서대로 보기';
};
gazeImage.onerror = () => { gazeLabel.textContent = '시선 이미지 로딩 실패'; };
Promise.all(gazeData.map(cell => new Promise((resolve, reject) => {
  const image = new Image();
  image.onload = resolve;
  image.onerror = () => reject(new Error('시선 이미지 로딩 실패: ' + cell.file));
  image.src = cell.file + '?rev=' + gazeCache25;
}))).then(() => showGaze25(0)).catch(error => { gazeLabel.textContent = error.message; });
function gazeTick25(now) {
  if (gazeAutomatic) showGaze25(Math.floor((now - gazeEpoch) / 200) % 16);
  requestAnimationFrame(gazeTick25);
}
requestAnimationFrame(gazeTick25);
