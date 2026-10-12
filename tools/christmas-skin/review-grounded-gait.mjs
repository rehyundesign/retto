import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash}from'node:crypto';
import {createRequire}from'node:module';
import {fileURLToPath}from'node:url';
const root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-smooth16');
const require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const hash=d=>createHash('sha256').update(d).digest('hex');
const before=JSON.parse(await fs.readFile(path.join(dir,'before-grounded-gait-v2/hashes.json')));
let changed=0,unchanged=0;
for(const [file,expected]of Object.entries(before)){
 if(!/-character\.png$/.test(file))continue;
 const current=hash(await fs.readFile(file));
 if(/\/move(Right|Left)-\d+-character\.png$/.test(file)){if(current===expected)throw new Error(`Unreplaced movement cell: ${file}`);changed++;}
 else {if(current!==expected)throw new Error(`Out of scope character changed: ${file}`);unchanged++;}
}
if(changed!==32)throw new Error(`Expected 32 movement replacements, found ${changed}`);
const rightHashes=[];
for(let i=0;i<16;i++){
 const right=await sharp(path.join(dir,`moveRight-${i}-character.png`)).ensureAlpha().raw().toBuffer();
 const left=await sharp(path.join(dir,`moveLeft-${i}-character.png`)).flop().ensureAlpha().raw().toBuffer();
 if(!right.equals(left))throw new Error(`Mirrored temporal order mismatch: ${i}`);
 rightHashes.push(hash(right));
}
if(new Set(rightHashes).size!==16)throw new Error('Expected 16 distinct whole-character poses');
const production=JSON.parse(await fs.readFile(path.join(dir,'validation.json')));
const registration=production.registration.filter(r=>r.id.includes('-stride-'));
if(registration.length!==16)throw new Error('Missing shared-registration report');
if(new Set(registration.map(r=>r.shared_scale)).size!==1)throw new Error('Per-pose scale changes');
if(registration.some(r=>Math.abs(r.bounds[3]-620)>1))throw new Error('Ground-contact line drift');
const range=values=>Math.max(...values)-Math.min(...values);
const headX=range(registration.map(r=>r.eye_center[0])),headY=range(registration.map(r=>r.eye_center[1]));
if(headX>2||headY>12)throw new Error(`Body/head registration pop: x=${headX}, y=${headY}`);
const output={changed_movement_cells:32,unchanged_character_cells:unchanged,shared_scale:registration[0].shared_scale,head_center_x_range:headX,head_center_y_range:headY,eye_gap_range:range(registration.map(r=>r.eye_gap)),registration,visual_review:'pending: gait anatomy, support phases and playback must be reviewed separately',limits:'Shared geometry is not a full original Retto identity or measured face-box comparison.'};
await fs.writeFile(path.join(dir,'grounded-gait-validation.json'),JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify({changed_movement_cells:changed,unchanged_character_cells:unchanged,shared_scale:output.shared_scale,head_center_range:[headX,headY]}));
