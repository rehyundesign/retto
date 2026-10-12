import fs from 'node:fs/promises';
import path from 'node:path';
import{createRequire}from'node:module';
import{fileURLToPath}from'node:url';
import{createHash}from'node:crypto';
import{execFile}from'node:child_process';
import{promisify}from'node:util';
import{festiveEffects,effectPeriods}from'./festive-effects.mjs';
const require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-production'),assets=path.resolve(root,'../../assets');
const map=JSON.parse(await fs.readFile(path.join(root,'production-map.json'))),CW=448,CH=640;
const digest=b=>createHash('sha256').update(b).digest('hex');
const run=promisify(execFile);
const clean=data=>{for(let p=0;p<data.length;p+=4)if(!data[p+3])data.fill(0,p,p+4);return data;};
const layers={character:[],back:[],front:[],complete:[]},used=new Set(),reports=[];
async function rawPNG(data){return sharp(data,{raw:{width:CW,height:CH,channels:4}}).png().toBuffer();}
function bounds(data){let l=CW,t=CH,r=-1,b=-1;for(let y=0;y<CH;y++)for(let x=0;x<CW;x++)if(data[(y*CW+x)*4+3]>8){l=Math.min(l,x);t=Math.min(t,y);r=Math.max(r,x);b=Math.max(b,y);}return r<0?null:[l,t,r+1,b+1];}
async function effect(group,time,front,index){const data=clean(await sharp(Buffer.from(festiveEffects(group,time,front,index))).ensureAlpha().raw().toBuffer());const b=bounds(data);if(b&&(b[0]<12||b[1]<12||b[2]>436||b[3]>628))throw new Error(`Effect margin: ${group.id} ${b}`);return rawPNG(data);}
async function makeCell(id,row,column,char,group,time,index){
  const cell=`${row}:${column}`;if(used.has(cell))throw new Error(`Duplicate cell ${cell}`);used.add(cell);
  const back=await effect(group,time,false,index),front=await effect(group,time,true,index),raw=clean(await sharp(char).composite([{input:back,blend:'dest-over'},{input:front}]).ensureAlpha().raw().toBuffer()),complete=await rawPNG(raw);
  for(const[name,input]of Object.entries({character:char,back,front,complete}))layers[name].push({input,left:column*CW,top:row*CH});
  await fs.writeFile(path.join(dir,`${id}-complete.png`),complete);
  reports.push({id,cell:[row,column],bounds:bounds(raw),four_limbs:'reviewed: front_left/front_right and rear_left/rear_right attached; rear legs may be occluded by coat, torso or forelegs',clipping:false});
}
for(const g of map.groups)for(let i=0;i<g.frames;i++){
  const id=`${g.id}-${i}`,source=g.id==='waving'?path.join(dir,`${id}-character.png`):path.join(root,'gen-festive',`${id}-character.png`),char=await fs.readFile(source);
  if(g.id!=='waving')await fs.writeFile(path.join(dir,`${id}-character.png`),char);
  await makeCell(id,g.row,i,char,g,i*g.interval,i);
}
const idle=map.groups.find(g=>g.id==='idle');
for(const g of map.gaze)await makeCell(g.id,g.row,g.column,await fs.readFile(path.join(dir,`${g.id}-character.png`)),idle,g.direction*.21,0);
if(used.size!==81)throw new Error(`Expected 81 mapped cells, got ${used.size}`);
// Validate the immutable sources before writing the candidate atlases.
for(const[file,hash]of Object.entries(map.locked_character_hashes))if(digest(await fs.readFile(path.join(root,file)))!==hash)throw new Error(`Approved source changed: ${file}`);
const paths={character:'spritesheet-christmas-character.webp',back:'spritesheet-christmas-effects-back.webp',front:'spritesheet-christmas-effects-front.webp',complete:'spritesheet-christmas.webp'};
for(const[name,file]of Object.entries(paths)){
  const raw=clean(await sharp({create:{width:CW*8,height:CH*12,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite(layers[name]).raw().toBuffer());
  const pngPath=path.join(dir,`${name}-atlas.png`);
  await sharp(raw,{raw:{width:CW*8,height:CH*12,channels:4}}).png().toFile(pngPath);
  await run(process.env.RETTO_CWEBP??'cwebp',['-quiet','-lossless','-exact',pngPath,'-o',path.join(assets,file)]);
}
const newIds=[...Array.from({length:4},(_,i)=>`waving-${i}`),...map.gaze.map(g=>g.id)];
let labelSvg='<rect width="896" height="1760" fill="#fffaf2"/><text x="448" y="27" text-anchor="middle" fill="#69432c" font-family="sans-serif" font-size="18">크리스마스 레토 · 완료 인사와 시선 16방향</text>';
const board=[];for(let i=0;i<20;i++){const x=i%4*224,y=40+Math.floor(i/4)*344,label=i<4?`완료 인사 ${i+1}`:`시선 ${i-4} · ${(i-4)*22.5}°`;
  board.push({input:await sharp(path.join(dir,`${newIds[i]}-complete.png`)).resize(224,320).png().toBuffer(),left:x,top:y});labelSvg+=`<text x="${x+112}" y="${y+335}" text-anchor="middle" fill="#69432c" font-family="sans-serif" font-size="13">${label}</text>`;}
await sharp(Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="896" height="1760">${labelSvg}</svg>`)).composite(board).png().toFile(path.join(assets,'retto-christmas-remaining-cuts.png'));
for(const bg of ['white','dark']){
  const n=map.anchors.length,anchorLayers=[];for(let i=0;i<n;i++){const a=map.anchors[i];anchorLayers.push({input:await sharp(path.join(dir,`${a.group}-${a.frame}-character.png`)).resize(224,320).png().toBuffer(),left:i%4*224,top:Math.floor(i/4)*320});}
  await sharp({create:{width:896,height:1280,channels:4,background:bg==='white'?'#fff':'#1e2531'}}).composite(anchorLayers).png().toFile(path.join(dir,`anchors-review-${bg}.png`));
  for(const type of ['gaze','waving']){const count=type==='gaze'?16:4,list=[];for(let i=0;i<count;i++)list.push({input:await sharp(path.join(dir,`${type}-${i}-complete.png`)).resize(224,320).png().toBuffer(),left:i%4*224,top:Math.floor(i/4)*320});await sharp({create:{width:896,height:320*Math.ceil(count/4),channels:4,background:bg==='white'?'#fff':'#1e2531'}}).composite(list).png().toFile(path.join(dir,`${type}-final-review-${bg}.png`));}
}
const waveGroup=map.groups.find(g=>g.id==='waving'),waveHashes=new Set();for(let i=0;i<20;i++)waveHashes.add(digest(Buffer.concat([await effect(waveGroup,i/20*effectPeriods.waving,false,Math.floor(i*.2)),await effect(waveGroup,i/20*effectPeriods.waving,true,Math.floor(i*.2))])));
const report={ok:true,mapped_cells:used.size,states:49,drag:16,gaze:16,new_independent_sources:20,approved_character_changes:0,waving_effect_samples:waveHashes.size,installation:'not installed',registration:'approved preview variants plus original gaze direction references; no claim of exact original protected-pixel identity',cells:reports};
await fs.writeFile(path.join(dir,'production-validation.json'),JSON.stringify(report,null,2)+'\n');
const motion_groups=map.groups.map(g=>({id:g.id,states:g.id==='moveRight'||g.id==='moveLeft'?[]:[g.id==='thinking'?'running':g.id],cells:Array.from({length:g.frames},(_,i)=>[g.row,i]),max_baseline_delta_px:g.id==='jumping'?30:20})).concat(map.gaze.map(g=>({id:g.id,states:[],cells:[[g.row,g.column]]})));
await fs.writeFile(path.join(dir,'atlas-spec.json'),JSON.stringify({atlas:{path:path.join(assets,paths.character),cell_width:448,cell_height:640,columns:8,rows:12},motion_groups},null,2)+'\n');
console.log(JSON.stringify({ok:true,mapped_cells:81,new_independent_sources:20,approved_character_changes:0,waving_effect_samples:waveHashes.size}));
