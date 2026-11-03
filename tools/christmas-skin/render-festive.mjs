import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { festiveEffects,effectPeriods } from './festive-effects.mjs';
const require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-festive'),sourceDir=path.join(root,'gen-keyframes');
const config=JSON.parse(await fs.readFile(path.join(root,'keyframes.json'),'utf8'));
await fs.mkdir(dir,{recursive:true});
const digest=b=>createHash('sha256').update(b).digest('hex');
const originals=new Map(),characters=new Map(),report=[];
const clean=data=>{for(let i=0;i<data.length;i+=4)if(!data[i+3])data.fill(0,i,i+4);return data;};
const png=data=>sharp(data,{raw:{width:448,height:640,channels:4}});
async function layer(group,time,front,index){return clean(await sharp(Buffer.from(festiveEffects(group,time,front,index))).ensureAlpha().raw().toBuffer());}
function bounds(data){let l=448,t=640,r=-1,b=-1;for(let y=0;y<640;y++)for(let x=0;x<448;x++)if(data[(y*448+x)*4+3]>8){l=Math.min(l,x);t=Math.min(t,y);r=Math.max(r,x);b=Math.max(b,y);}return r<0?null:[l,t,r+1,b+1];}
async function compose(group,time,index){const char=characters.get(group.id)[index],back=await layer(group,time,false,index),front=await layer(group,time,true,index);
  return sharp(char).composite([{input:await png(back).png().toBuffer(),blend:'dest-over'},{input:await png(front).png().toBuffer()}]).png().toBuffer();}
for(const g of config.groups){
  const cells=[];
  for(let i=0;i<g.frames;i++){
    const file=path.join(sourceDir,`${g.mirror??g.id}-${i}-character.png`),original=await fs.readFile(file);originals.set(file,digest(original));
    const char=g.mirror?await sharp(original).flop().png().toBuffer():original;cells.push(char);
    await fs.writeFile(path.join(dir,`${g.id}-${i}-character.png`),char);
  }
  characters.set(g.id,cells);
  const hashes=new Set();
  for(let sample=0;sample<20;sample++){
    const time=sample/20*effectPeriods[g.id],index=Math.floor(time/g.interval)%g.frames;
    const back=await layer(g,time,false,index),front=await layer(g,time,true,index);hashes.add(digest(Buffer.concat([back,front])));
    for(const [name,data]of [['back',back],['front',front]]){
      const b=bounds(data);if(b&&(b[0]<12||b[1]<12||b[2]>436||b[3]>628))throw new Error(`${g.id}/${sample}/${name}: effect margin ${b}`);
      await png(data).png().toFile(path.join(dir,`${g.id}-effect-${name}-${sample}.png`));
    }
  }
  if(hashes.size<15)throw new Error(`${g.id}: effect is not moving enough (${hashes.size}/20)`);
  report.push({id:g.id,distinct_effect_samples:hashes.size,effect_period:effectPeriods[g.id],margin_minimum:12});
  const review=[];
  for(let i=0;i<g.frames;i++){
    const completed=await compose(g,i*g.interval,i);await fs.writeFile(path.join(dir,`${g.id}-${i}.png`),completed);
    review.push({input:await sharp(completed).resize(224,320).png().toBuffer(),left:i%4*224,top:Math.floor(i/4)*320});
  }
  for(const bg of ['white','dark'])await sharp({create:{width:896,height:640,channels:4,background:bg==='white'?'#fff':'#181c26'}}).composite(review).png().toFile(path.join(dir,`${g.id}-review-${bg}.png`));
}
const W=744,H=1080,frames=[];
for(let tick=0;tick<160;tick++){
  const time=tick/20,overlays=[];let labels='<rect width="744" height="1080" fill="#fffaf2"/><text x="372" y="27" text-anchor="middle" fill="#693d29" font-family="sans-serif" font-size="18">크리스마스 레토 · 움직이는 이펙트</text>';
  for(let i=0;i<config.groups.length;i++){
    const g=config.groups[i],x=12+i%3*244,y=40+Math.floor(i/3)*344,index=Math.floor(time/g.interval)%g.frames;
    labels+=`<rect x="${x}" y="${y}" width="232" height="338" rx="12" fill="#fff" stroke="#e8d5b9"/><text x="${x+116}" y="${y+328}" text-anchor="middle" fill="#69432c" font-family="sans-serif" font-size="14">${g.label}</text>`;
    overlays.push({input:await sharp(await compose(g,time,index)).resize(224,320).png().toBuffer(),left:x+4,top:y-4});
  }
  const data=await sharp(Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">${labels}</svg>`)).composite(overlays).ensureAlpha().raw().toBuffer();frames.push(data);
  if(tick===30)await sharp(data,{raw:{width:W,height:H,channels:4}}).png().toFile(path.join(dir,'poster.png'));
}
await sharp(Buffer.concat(frames),{raw:{width:W,height:H*frames.length,channels:4,pageHeight:H}}).gif({loop:0,delay:Array(160).fill(50),colours:256,effort:7,dither:.7}).toFile(path.join(dir,'motion.gif'));
for(const[file,hash]of originals)if(digest(await fs.readFile(file))!==hash)throw new Error(`character source changed: ${file}`);
const result={ok:true,character_source_changed:0,character_frames:61,jump_gift:false,effect_fps:20,groups:report};
await fs.writeFile(path.join(dir,'validation.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
