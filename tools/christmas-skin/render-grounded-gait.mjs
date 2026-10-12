// 독립 전신 셀을 실제 프레임 유지 시간으로 재생한다.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire}from'node:module';
import {fileURLToPath}from'node:url';
import {festiveEffects}from'./festive-effects.mjs';
const require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-smooth16/grounded-gait-video');
const config=JSON.parse(await fs.readFile(path.join(root,'smooth16-map.json')));
const groups=['moveRight','moveLeft'].map(id=>config.groups.find(g=>g.id===id));
await fs.mkdir(dir,{recursive:true});
const cells=new Map();
for(const g of groups)for(let i=0;i<16;i++)cells.set(`${g.id}-${i}`,await fs.readFile(path.join(root,`gen-smooth16/${g.id}-${i}-character.png`)));
for(let frame=0;frame<112;frame++){
 const time=frame*.05,layers=[];
 for(const [column,g]of groups.entries()){
  const duration=g.frame_durations,cycle=duration.reduce((a,b)=>a+b,0);let phase=time%cycle,index=0;
  while(index<15&&phase>=duration[index]){phase-=duration[index];index++;}
  const cell=await sharp(cells.get(`${g.id}-${index}`)).composite([{input:Buffer.from(festiveEffects(g,time,false,index)),blend:'dest-over'},{input:Buffer.from(festiveEffects(g,time,true,index))}]).png().toBuffer();
  layers.push({input:await sharp(cell).resize(224,320).png().toBuffer(),left:column*224,top:0});
 }
 await sharp({create:{width:448,height:320,channels:4,background:'#fffaf2'}}).composite(layers).png().toFile(path.join(dir,`${String(frame).padStart(3,'0')}.png`));
}
console.log(JSON.stringify({frames:112,fps:20,duration:5.6,directory:dir}));
