import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-smooth16');
const activeMap=JSON.parse(await fs.readFile(path.join(root,'smooth16-map.json')));
if(activeMap.groups.find(g=>g.id==='moveRight').sources.every(id=>id.includes('-stride-'))){await import('./review-grounded-gait.mjs');process.exit(0);}
const require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const hash=data=>createHash('sha256').update(data).digest('hex');
const before=JSON.parse(await fs.readFile(path.join(dir,'before-gait-meteor/hashes.json')));
const result={unchanged_character_cells:0,changed_movement_cells:0,completion_character_unchanged:true,groups:[]};
for(const [file,expected] of Object.entries(before)){
  if(!/-character\.png$/.test(file))continue;
  const changed=hash(await fs.readFile(file))!==expected;
  if(/\/move(Right|Left)-\d+-character\.png$/.test(file)){
    if(!changed)throw new Error(`Movement cell was not replaced: ${file}`);
    result.changed_movement_cells++;
  }else{
    if(changed)throw new Error(`Out of scope character changed: ${file}`);
    result.unchanged_character_cells++;
  }
}
const master=await sharp(path.join(root,'gen-production/moveRight-0-character.png')).ensureAlpha().raw().toBuffer();
for(const id of ['moveRight','moveLeft']){
  const frames=[];
  for(let i=0;i<16;i++){
    const raw=await sharp(path.join(dir,`${id}-${i}-character.png`)).ensureAlpha().raw().toBuffer();
    frames.push(raw);
    const right=id==='moveLeft'?await sharp(raw,{raw:{width:448,height:640,channels:4}}).flop().raw().toBuffer():raw;
    const paired=await sharp(path.join(dir,`moveRight-${i}-character.png`)).ensureAlpha().raw().toBuffer();
    if(!right.equals(paired))throw new Error(`Left/right pose mismatch at ${i}`);
    for(let y=0;y<640;y++)for(let x=0;x<448;x++){
      const allowed=y>410&&!(x<145&&y<480)&&((x-334)/100)**2+((y-357)/121)**2>1;
      const p=(y*448+x)*4;
      if(!allowed&&!right.subarray(p,p+4).equals(master.subarray(p,p+4)))throw new Error(`Protected head/tail drift: ${id}-${i}`);
    }
  }
  if(new Set(frames.map(hash)).size!==16)throw new Error(`${id} contains duplicated poses`);
  const deltas=frames.map((frame,i)=>{
    const next=frames[(i+1)%16];let sum=0;
    for(let p=0;p<frame.length;p+=4)sum+=Math.abs(frame[p+3]-next[p+3]);
    return sum/(448*640*255);
  });
  result.groups.push({id,distinct_frames:16,adjacent_silhouette_deltas:deltas,wrap_delta:deltas[15]});
}
if(result.changed_movement_cells!==32)throw new Error('Expected only 32 changed character cells');
const timings=JSON.parse(await fs.readFile(path.resolve(root,'../../assets/christmas-16-timing.json')));
for(const row of ['1','2'])if(timings.frame_seconds[row].some(t=>Math.abs(t-.07)>1e-8))throw new Error('Gait timing mismatch');
result.visual_review='pending runtime-scale review; these checks do not establish anatomical or perceptual smoothness';
await fs.writeFile(path.join(dir,'gait-meteor-validation.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({changed_movement_cells:32,unchanged_character_cells:result.unchanged_character_cells,completion_character_unchanged:true}));
