import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {festiveEffects} from './festive-effects.mjs';
const root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-secondary'),production=path.join(root,'gen-smooth16'),before=path.join(dir,'before'),require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const config=JSON.parse(await fs.readFile(path.join(root,'smooth16-map.json'))),report=JSON.parse(await fs.readFile(path.join(dir,'validation.json'))),hash=b=>createHash('sha256').update(b).digest('hex');
const snapshot=JSON.parse(await fs.readFile(path.join(before,'hashes.json')));let untouched=0,faceChanges=0,lowerBodyChanges=0;
for(const [file,expected]of Object.entries(snapshot)){
 if(!file.endsWith('-character.png'))continue;
 if(!/\/(idle|waving|thinking)-\d+-character\.png$/.test(file)){if(hash(await fs.readFile(file))!==expected)throw new Error('Other state changed');untouched++;continue;}
 const current=await sharp(file).ensureAlpha().raw().toBuffer(),base=await sharp(path.join(before,path.basename(file))).ensureAlpha().raw().toBuffer();
 for(let y=0;y<640;y++)for(let x=0;x<448;x++){
  const p=(y*448+x)*4;if(!current.subarray(p,p+4).equals(base.subarray(p,p+4))){
   if(y>=410)lowerBodyChanges++;
   const faceTop=path.basename(file).startsWith('thinking-')?332:282;
   if(x>=112&&x<267&&y>=faceTop&&y<415)faceChanges++;
  }
  if(!current[p+3]&&current.subarray(p,p+3).some(v=>v))throw new Error('RGB below zero alpha');
 }
}
if(untouched!==128||faceChanges||lowerBodyChanges)throw new Error(`Scope failure: ${untouched}/${faceChanges}/${lowerBodyChanges}`);
const atlas=await sharp(path.resolve(root,'../../assets/spritesheet-christmas-16-character.webp')).ensureAlpha().raw().toBuffer({resolveWithObject:true});
if(atlas.info.width!==7168||atlas.info.height!==7680)throw new Error('Atlas dimensions changed');
const originalAtlas=await sharp(path.join(before,'spritesheet-christmas-16-character.webp')).ensureAlpha().raw().toBuffer();
const cellMap=JSON.parse(await fs.readFile(path.join(production,'validation.json'))).cells;
for(const cell of cellMap){
 const image=await sharp(path.join(production,`${cell.id}-character.png`)).ensureAlpha().raw().toBuffer();
 const baseline=await sharp(path.join(before,`${cell.id}-character.png`)).ensureAlpha().raw().toBuffer();
 for(let y=0;y<640;y++)for(let x=0;x<448;x++){
  const source=(y*448+x)*4,at=((cell.row*640+y)*atlas.info.width+cell.column*448+x)*4;
  const expected=image.readUInt32LE(source)===baseline.readUInt32LE(source)?originalAtlas.readUInt32LE(at):image.readUInt32LE(source);
  if(atlas.data.readUInt32LE(at)!==expected)throw new Error(`Encoded scope mismatch: ${cell.id}`);
 }
}
report.encoded_cells_verified=cellMap.length;
if(!process.argv.includes('--verify-atlas-only'))
for(const id of ['idle','waving','thinking','review']){
 const group=config.groups.find(g=>g.id===id);let time=.1;const layers=[];
 for(let i=0;i<16;i++){
  const image=await fs.readFile(path.join(production,`${id}-${i}-character.png`));
  const fullCell=await sharp(image).composite([{input:Buffer.from(festiveEffects(group,time,false,i)),blend:'dest-over'},{input:Buffer.from(festiveEffects(group,time,true,i))}]).png().toBuffer();
  const composited=await sharp(fullCell).resize(224,320).png().toBuffer();
  layers.push({input:composited,left:(i%8)*224,top:Math.floor(i/8)*320});time+=group.frame_durations[i];
 }
 for(const [background,label]of [['#ffffff','light'],['#1e2531','dark']])await sharp({create:{width:1792,height:640,channels:4,background}}).composite(layers).png().toFile(path.join(dir,`${id}-${label}-review.png`));
}
report.untouched_cells=untouched;report.face_core_changed_pixels=faceChanges;report.lower_body_changed_pixels=lowerBodyChanges;report.review_boards=['idle','waving','thinking','review'].map(id=>`${id}-{light,dark}-review.png`);await fs.writeFile(path.join(dir,'validation.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({untouched,faceChanges,lowerBodyChanges,targetFrames:48,actualChanged:report.actual_changed_cells}));
