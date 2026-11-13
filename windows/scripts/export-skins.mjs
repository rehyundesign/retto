// Windows 판 스킨 프레임을 만든다 — `npm run skins` (맥에서만 돈다).
//
// 1. scripts/build-public.py --app-only 로 공개 빌드를 만든다(저장소의 리소스만 쓴다. 설치본을 읽지 않는다)
// 2. 그 앱의 `--export-windows-skins` 로 스킨마다 상태별 프레임 판(PNG)과 manifest.json 을 남긴다
// 3. 판을 WebP 로 바꿔 windows/skins/ 에 둔다. electron-builder 가 resources/skins 로 넣는다
//
// 결과물은 생성물이라 Git 에 넣지 않는다(.gitignore). 맥 쪽 그림·동작이 바뀌면 다시 돌린다.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..');
const out = path.resolve(here, '..', 'skins');

if (process.platform !== 'darwin') {
  console.error('스킨 프레임은 맥 앱이 그린다. 맥에서 돌려 주세요.');
  process.exit(1);
}
for (const tool of ['cwebp']) {
  try { execFileSync('which', [tool], { stdio: 'ignore' }); } catch {
    console.error(`${tool} 가 필요합니다: brew install webp`);
    process.exit(1);
  }
}

console.log('› 공개 빌드');
const log = execFileSync('python3', [path.join(repo, 'scripts', 'build-public.py'), '--app-only'], { cwd: repo, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const work = /build directory: (\S+)/.exec(log)?.[1];
const app = work && path.join(work, 'Retto.app', 'Contents', 'MacOS', 'Retto');
if (!app || !fs.existsSync(app)) { console.error('공개 빌드에서 앱을 찾지 못했습니다'); process.exit(1); }

console.log('› 프레임 내보내기');
const raw = fs.mkdtempSync(path.join(os.tmpdir(), 'retto-skins-'));
execFileSync(app, ['--export-windows-skins', raw, ...process.argv.slice(2)], { stdio: 'inherit' });
const manifest = JSON.parse(fs.readFileSync(path.join(raw, 'manifest.json'), 'utf8'));

console.log('› WebP 로 바꾸기');
fs.rmSync(out, { recursive: true, force: true });
for (const skin of manifest.skins) {
  fs.mkdirSync(path.join(out, skin.id), { recursive: true });
  for (const clip of Object.values(skin.clips)) {
    const source = path.join(raw, skin.id, clip.file);
    clip.file = clip.file.replace(/\.png$/, '.webp');
    execFileSync('cwebp', ['-quiet', '-q', '82', '-alpha_q', '90', '-m', '4', source, '-o', path.join(out, skin.id, clip.file)]);
  }
}
manifest.generatedAt = new Date().toISOString();
manifest.source = execFileSync('git', ['-C', repo, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim();
fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(manifest, null, 2));
fs.rmSync(raw, { recursive: true, force: true });

const bytes = execFileSync('du', ['-sh', out], { encoding: 'utf8' }).split('\t')[0];
console.log(`✓ ${manifest.skins.length}개 스킨 · ${bytes} · ${out}`);
