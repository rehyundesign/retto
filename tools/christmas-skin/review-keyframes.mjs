import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const require=createRequire(import.meta.url);
const sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-keyframes');
const config=JSON.parse(await fs.readFile(path.join(root,'keyframes.json'),'utf8'));
const checks=[];
for(const g of config.groups){
  const sheets={white:[],dark:[]};
  for(let i=0;i<g.frames;i++){
    const file=path.join(dir,`${g.id}-${i}.png`),{data,info}=await sharp(file).ensureAlpha().raw().toBuffer({resolveWithObject:true});
    let hidden=0;for(let p=0;p<data.length;p+=4)if(!data[p+3]&&(data[p]||data[p+1]||data[p+2]))hidden++;
    if(hidden)throw new Error(`${g.id}/${i}: hidden RGB ${hidden}`);
    const thumb=await sharp(file).resize(224,320).png().toBuffer();
    for(const bg of Object.keys(sheets))sheets[bg].push({input:thumb,left:(i%4)*224,top:Math.floor(i/4)*320});
    checks.push({id:g.id,frame:i,size:[info.width,info.height],transparent_rgb:0});
  }
  for(const [bg,layers]of Object.entries(sheets))await sharp({create:{width:896,height:640,channels:4,background:bg==='white'?'#ffffff':'#181c26'}}).composite(layers).png().toFile(path.join(dir,`${g.id}-review-${bg}.png`));
}
const idle=await sharp(path.join(dir,'idle-0-character.png')).raw().toBuffer();
for(const frame of [3,4,5]){
  const data=await sharp(path.join(dir,`idle-${frame}-character.png`)).raw().toBuffer();let changedOutside=0;
  for(let y=0;y<640;y++)for(let x=0;x<448;x++){
    if(y>=292&&y<336&&((x>=124&&x<174)||(x>=196&&x<246)))continue;
    const p=(y*448+x)*4;for(let c=0;c<4;c++)if(data[p+c]!==idle[p+c])changedOutside++;
  }
  if(changedOutside)throw new Error(`blink changes outside eyes: ${changedOutside}`);
}
for(let i=0;i<8;i++){
  const expected=await sharp(path.join(dir,`moveRight-${i}.png`)).flop().raw().toBuffer(),actual=await sharp(path.join(dir,`moveLeft-${i}.png`)).raw().toBuffer();
  if(!expected.equals(actual))throw new Error(`left mirror differs at ${i}`);
}
const runHashes = new Set();
for(let i=0;i<8;i++)runHashes.add(createHash('sha256').update(await sharp(path.join(dir,`moveRight-${i}-character.png`)).raw().toBuffer()).digest('hex'));
if(runHashes.size !== 8)throw new Error(`run has only ${runHashes.size} distinct character frames`);
const gif = await sharp(path.join(dir,'motion.gif'),{animated:true}).metadata();
if(gif.loop !== 0 || gif.delay.reduce((sum,ms)=>sum+ms,0) !== 8000)throw new Error('GIF timing or loop differs');
const result = {ok:true,frames:checks.length,run_distinct_character_frames:8,blink_outside_eye_differences:0,mirror_exact:true,gif_duration_ms:8000,cells:checks};
await fs.writeFile(path.join(dir,'cell-review-checks.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({...result,cells:undefined}));
