// 승인한 독립 원본을 상태별로 변형해 움직임 시안을 렌더링한다.
// 시안 보드는 입력으로 사용하지 않는다. 앱 등록·설치는 이 도구의 범위 밖이다.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const sharp = process.env.RETTO_NODE_MODULES
  ? require(path.join(process.env.RETTO_NODE_MODULES, 'sharp')) : require('sharp');
const root = path.dirname(fileURLToPath(import.meta.url));
const CW = 448, CH = 640;
const output = path.join(root, 'gen-frames');
const config = JSON.parse(await fs.readFile(path.join(root, 'motion.json'), 'utf8'));
const anchorsOnly = process.argv.includes('--anchors-only');
await fs.mkdir(output, { recursive: true });
const png = (data, width = CW, height = CH) => sharp(data, { raw: { width, height, channels: 4 } });
const clean = (data) => { for (let i = 0; i < data.length; i += 4) if (!data[i + 3]) data.fill(0, i, i + 4); return data; };

function alphaBounds(data, width, height, threshold = 8) {
  let x0 = width, y0 = height, x1 = -1, y1 = -1;
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    if (data[(y * width + x) * 4 + 3] > threshold) {
      x0 = Math.min(x0, x); y0 = Math.min(y0, y);
      x1 = Math.max(x1, x); y1 = Math.max(y1, y);
    }
  }
  return x1 < 0 ? null : [x0, y0, x1 + 1, y1 + 1];
}

async function register(group) {
  const source = path.resolve(root, group.source);
  const meta = await sharp(source).metadata();
  const face = group.face_box.map((n, i) => n * (i % 2 ? meta.height : meta.width));
  let scale = group.target_face_width / (face[2] - face[0]);
  let eyeGap = null;
  if (group.target_eye_gap) {
    const { data, info } = await sharp(source).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const points = [];
    for (let y = Math.ceil(face[1]); y < Math.floor(face[3]); y++) for (let x = Math.ceil(face[0]); x < Math.floor(face[2]); x++) {
      const p = (y * info.width + x) * 4;
      if (data[p + 3] > 220 && data[p + 2] > 50 && data[p + 2] > data[p] * 1.12 && data[p + 2] > data[p + 1] * 1.03) points.push([x, y]);
    }
    if (points.length < 50) throw new Error(`${group.id}: cannot locate both blue irises`);
    let centers = [[Math.min(...points.map(p => p[0])), points[0][1]], [Math.max(...points.map(p => p[0])), points[0][1]]];
    for (let k = 0; k < 20; k++) {
      const sums = [[0, 0, 0], [0, 0, 0]];
      for (const p of points) {
        const d = centers.map(c => (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2), i = d[0] < d[1] ? 0 : 1;
        sums[i][0] += p[0]; sums[i][1] += p[1]; sums[i][2]++;
      }
      centers = sums.map(s => [s[0] / s[2], s[1] / s[2]]);
    }
    eyeGap = Math.hypot(centers[0][0] - centers[1][0], centers[0][1] - centers[1][1]);
    scale = group.target_eye_gap / eyeGap;
  }
  const width = Math.round(meta.width * scale), height = Math.round(meta.height * scale);
  const resized = await sharp(source).ensureAlpha().resize(width, height).raw().toBuffer();
  const dx = Math.round(group.center - group.body_center_x * meta.width * scale);
  const dy = Math.round(group.baseline - group.foot_baseline_y * meta.height * scale);
  const data = Buffer.alloc(CW * CH * 4);
  let clipped = 0;
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const sourceIndex = (y * width + x) * 4, tx = x + dx, ty = y + dy;
    if (tx < 0 || tx >= CW || ty < 0 || ty >= CH) {
      if (resized[sourceIndex + 3] > 8) clipped++;
    } else resized.copy(data, (ty * CW + tx) * 4, sourceIndex, sourceIndex + 4);
  }
  if (clipped) throw new Error(`${group.id}: registration clips ${clipped} visible pixels; repair the anchor profile`);
  const registeredFace = face.map((n, i) => n * scale + (i % 2 ? dy : dx));
  clean(data);
  await png(data).png().toFile(path.join(root, 'gen-anchors', `${group.id}-registered.png`));
  return { data, face: registeredFace, bounds: alphaBounds(data, CW, CH), scale, dx, dy, registeredEyeGap: eyeGap === null ? null : eyeGap * scale };
}

function displacement(x, y, group, phase, face) {
  // 같은 시점의 얼굴 픽셀은 프레임 사이에서 그대로 유지한다.
  if (x >= face[0] - 3 && x <= face[2] + 3 && y >= face[1] - 3 && y <= face[3] + 3) return [0, 0];
  const s = Math.sin(phase), c = Math.cos(phase);
  let dx = 0, dy = 0;
  for (const region of group.rig || []) {
    const [cx, cy, rx, ry, mx, my, offset = 0] = region;
    const d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2;
    if (d >= 4) continue;
    const weight = Math.exp(-d * 2) * Math.min(1, (4 - d));
    const wave = Math.sin(phase + offset);
    dx += mx * weight * wave;
    const vertical = group.id === 'moveRight'
      ? -Math.abs(my) * Math.max(0, Math.sin(phase + (my < 0 ? 0 : Math.PI)))
      : my * wave;
    dy += vertical * weight;
  }
  // 발 주변은 바닥선을 유지하고, 흉곽 안쪽만 호흡한다.
  if (group.id === 'idle') dy += -1.2 * s * Math.exp(-(((x - 176) / 48) ** 2 + ((y - 475) / 44) ** 2));
  if (group.id === 'sleeping') dy += -2.0 * c * Math.exp(-(((x - 240) / 52) ** 2 + ((y - 530) / 24) ** 2));
  if (group.grounded && y >= group.baseline - 5) return [0, 0];
  return [dx, dy];
}

function warp(anchor, group, phase) {
  const output = Buffer.alloc(CW * CH * 4), source = anchor.data;
  const lift = group.id === 'jumping' ? Math.round(22 * (0.5 - 0.5 * Math.cos(phase))) : 0;
  for (let y = 0; y < CH; y++) for (let x = 0; x < CW; x++) {
    let sx = x, sy = y + lift;
    for (let k = 0; k < 2; k++) {
      const d = displacement(sx, sy, group, phase, anchor.face);
      sx = x - d[0]; sy = y + lift - d[1];
    }
    if (sx < 0 || sy < 0 || sx >= CW - 1 || sy >= CH - 1) continue;
    const ox = Math.floor(sx), oy = Math.floor(sy), fx = sx - ox, fy = sy - oy;
    const weights = [(1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy];
    const indices = [(oy * CW + ox) * 4, (oy * CW + ox + 1) * 4, ((oy + 1) * CW + ox) * 4, ((oy + 1) * CW + ox + 1) * 4];
    let a = 0, red = 0, green = 0, blue = 0;
    for (let k = 0; k < 4; k++) {
      const p = indices[k], w = weights[k] * source[p + 3] / 255;
      a += w; red += source[p] * w; green += source[p + 1] * w; blue += source[p + 2] * w;
    }
    const p = (y * CW + x) * 4;
    if (a > 0) { output[p] = Math.round(red / a); output[p + 1] = Math.round(green / a); output[p + 2] = Math.round(blue / a); output[p + 3] = Math.round(a * 255); }
  }
  return clean(output);
}

const svg = (body) => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${CW}" height="${CH}" viewBox="0 0 ${CW} ${CH}">${body}</svg>`);
function star(x, y, size, opacity) {
  const points = Array.from({ length: 10 }, (_, i) => {
    const r = size * (i % 2 ? .44 : 1), angle = -Math.PI / 2 + i * Math.PI / 5;
    return `${(x + Math.cos(angle) * r).toFixed(2)},${(y + Math.sin(angle) * r).toFixed(2)}`;
  }).join(' ');
  return `<polygon points="${points}" fill="#ffe096" stroke="#db942c" stroke-width="1" opacity="${opacity.toFixed(3)}"/>`;
}
function effects(group, phase, front) {
  let shapes = '';
  if (['thinking', 'review', 'jumping'].includes(group.id)) {
    for (let i = 0; i < 5; i++) {
      const p = (phase / (2 * Math.PI) + i / 5) % 1;
      const x = group.id === 'review' ? 55 + i * 8 : 300 + i * 16;
      shapes += star(x + 5 * Math.sin(phase + i), 510 - p * 95, 3 + 4 * Math.sin(Math.PI * p), Math.sin(Math.PI * p) * .85);
    }
  }
  if (group.id === 'waiting' && front) {
    const alpha = Math.max(0, Math.sin(phase));
    shapes += `<g fill="none" stroke="#d9a044" stroke-width="2.5" stroke-linecap="round" opacity="${alpha}"><path d="M354 409 Q365 421 354 433"/><path d="M365 401 Q383 421 365 441"/></g>`;
  }
  if (group.id === 'failed' && front) {
    const alpha = .25 + .65 * Math.max(0, Math.sin(phase * 2));
    shapes += `<circle cx="220" cy="606" r="5" fill="#ffe597" opacity="${alpha}"/>`;
    if (Math.sin(phase) > .55) shapes += `<path d="M233 592 l5 5 -6 3 5 5" fill="none" stroke="#e76e47" stroke-width="2"/>`;
  }
  if (group.id === 'sleeping' && !front) {
    shapes += `<path d="M280 420 A14 14 0 1 0 295 437 A13 13 0 0 1 280 420" fill="#f6cd75" opacity=".8"/>`;
    for (let i = 0; i < 3; i++) {
      const y = 438 + 7 * Math.sin(phase + i), x = 235 + i * 47;
      shapes += `<g stroke="#b3d2e6" stroke-width="1.6" opacity="${.45 + .25 * Math.cos(phase + i)}"><path d="M${x - 4} ${y}h8 M${x} ${y - 4}v8 M${x - 3} ${y - 3}l6 6 M${x - 3} ${y + 3}l6 -6"/></g>`;
    }
  }
  if (group.id === 'jumping' && !front) {
    shapes += `<defs><linearGradient id="gift" x2="1" y2="1"><stop stop-color="#2e7251"/><stop offset="1" stop-color="#134833"/></linearGradient></defs><rect x="150" y="598" width="75" height="30" rx="3" fill="url(#gift)"/><rect x="182" y="598" width="10" height="30" fill="#b71931"/><rect x="147" y="594" width="81" height="9" rx="2" fill="#286c49"/><path d="M187 596 C161 570 161 596 187 596 C210 570 215 599 187 596" fill="none" stroke="#cf3244" stroke-width="4"/>`;
  }
  if (front && ['thinking', 'review', 'jumping'].includes(group.id)) shapes = '';
  return svg(shapes);
}

const rendered = new Map(), report = [];
let anchorFailures = 0;
for (const group of config.groups) {
  if (group.mirror) continue;
  let anchor;
  try { anchor = await register(group); } catch (error) {
    if (!anchorsOnly) throw error;
    anchorFailures++; console.error(error.message); continue;
  }
  const frames = [], cellReports = [];
  if (anchorsOnly) {
    console.log(JSON.stringify({id:group.id,face:anchor.face,bounds:anchor.bounds,scale:anchor.scale}));
    continue;
  }
  for (let i = 0; i < group.frames; i++) {
    const phase = i / group.frames * Math.PI * 2;
    const raw = warp(anchor, group, phase), bounds = alphaBounds(raw, CW, CH);
    if (!bounds || bounds[0] < 8 || bounds[1] < 8 || bounds[2] > CW - 8 || bounds[3] > CH - 8) throw new Error(`${group.id}/${i}: clipped or insufficient transparent margin ${bounds}`);
    let protectedDifferences = 0;
    const lift = group.id === 'jumping' ? Math.round(22 * (0.5 - 0.5 * Math.cos(phase))) : 0;
    for (let y = Math.ceil(anchor.face[1]); y < Math.floor(anchor.face[3]); y++) for (let x = Math.ceil(anchor.face[0]); x < Math.floor(anchor.face[2]); x++) {
      const sourcePixel = (y * CW + x) * 4, targetPixel = ((y - lift) * CW + x) * 4;
      for (let c = 0; c < 4; c++) if (raw[targetPixel + c] !== anchor.data[sourcePixel + c]) protectedDifferences++;
    }
    if (protectedDifferences) throw new Error(`${group.id}/${i}: protected face changed (${protectedDifferences})`);
    await png(raw).png().toFile(path.join(output, `${group.id}-${i}-character.png`));
    const back = await sharp(effects(group, phase, false)).png().toBuffer();
    const front = await sharp(effects(group, phase, true)).png().toBuffer();
    await fs.writeFile(path.join(output, `${group.id}-${i}-effect-back.png`), back);
    await fs.writeFile(path.join(output, `${group.id}-${i}-effect-front.png`), front);
    const completed = await png(raw).composite([{ input: back, blend: 'dest-over' }, { input: front }]).png().toBuffer();
    frames.push(completed);
    await fs.writeFile(path.join(output, `${group.id}-${i}.png`), completed);
    cellReports.push({ column: i, bounds, protected_face_changed_channels: protectedDifferences, face_box: anchor.face.map((value,index)=>value-(index%2?lift:0)), baseline: group.baseline-lift, four_limbs: group.limbs });
  }
  rendered.set(group.id, frames);
  report.push({ id: group.id, frames: group.frames, source: group.source, registered_face: anchor.face, registered_eye_gap: anchor.registeredEyeGap, scale: anchor.scale, cells: cellReports });
}
if (anchorsOnly) process.exit(anchorFailures ? 1 : 0);
for (const group of config.groups.filter((g) => g.mirror)) {
  const frames = [];
  for (let i = 0; i < rendered.get(group.mirror).length; i++) {
    const frame = await sharp(rendered.get(group.mirror)[i]).flop().png().toBuffer();
    frames.push(frame); await fs.writeFile(path.join(output, `${group.id}-${i}.png`), frame);
  }
  rendered.set(group.id, frames);
  report.push({ id: group.id, frames: frames.length, mirror_of: group.mirror });
}

const BW = 744, BH = 1080, seconds = 6, FPS = 20;
const boardFrames = [];
for (let tick = 0; tick < seconds * FPS; tick++) {
  let labels = '<rect width="744" height="1080" fill="#fffaf2"/><text x="372" y="27" text-anchor="middle" fill="#693d29" font-size="18" font-family="sans-serif">크리스마스 레토 · 움직임 시안</text>';
  const overlays = [];
  for (let index = 0; index < config.groups.length; index++) {
    const group = config.groups[index], column = index % 3, row = Math.floor(index / 3);
    const x = 12 + column * 244, y = 40 + row * 344;
    labels += `<rect x="${x}" y="${y}" width="232" height="338" rx="12" fill="#ffffff" stroke="#e8d5b9"/><text x="${x + 116}" y="${y + 328}" text-anchor="middle" fill="#69432c" font-size="14" font-family="sans-serif">${group.label}</text>`;
    const frames = rendered.get(group.id), frame = frames[Math.floor(tick / FPS / group.interval) % frames.length];
    const smaller = await sharp(frame).resize(224, 320).png().toBuffer();
    overlays.push({ input: smaller, left: x + 4, top: y - 4 });
  }
  const background = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${BW}" height="${BH}">${labels}</svg>`);
  const raw = await sharp(background).composite(overlays).ensureAlpha().raw().toBuffer();
  boardFrames.push(raw);
  if (tick === 0) await png(raw, BW, BH).png().toFile(path.join(root, 'preview', 'poster.png'));
}
const animatedRaw = Buffer.concat(boardFrames);
await sharp(animatedRaw, { raw: { width: BW, height: BH * boardFrames.length, channels: 4, pageHeight: BH } })
  .gif({ loop: 0, delay: Array(boardFrames.length).fill(Math.round(1000 / FPS)), colours: 256, effort: 7, dither: 0.7 })
  .toFile(path.join(root, 'preview', 'motion.gif'));
const characterCount = report.reduce((sum, r) => sum + (r.mirror_of ? 0 : r.frames), 0);
await fs.writeFile(path.join(root, 'gen-frames', 'validation.json'), JSON.stringify({ status: 'motion-prototype', ok: true, character_frames: characterCount, independent_source_anchors: config.groups.filter(g => !g.mirror).length, derived_left_run: true, frame_size: [CW, CH], runtime_preview_size: [224, 320], gif_frames: boardFrames.length, groups: report }, null, 2) + '\n');
console.log(JSON.stringify({ ok: true, character_frames: characterCount, gif_frames: boardFrames.length, preview: path.join(root, 'preview', 'motion.gif') }));
