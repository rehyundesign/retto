// 최종 독립 셀을 실제 유지 시간으로 재생하는 1× 검토 영상 프레임.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {festiveEffects} from './festive-effects.mjs';
const require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-smooth16/gait-meteor-video');
const map=JSON.parse(await fs.readFile(path.join(root,'smooth16-map.json')));
const groups=['moveRight','moveLeft','waving'].map(id=>map.groups.find(g=>g.id===id));
await fs.mkdir(dir,{recursive:true});
const images=new Map();
for(const g of groups)for(let i=0;i<16;i++)images.set(`${g.id}-${i}`,await fs.readFile(path.join(root,`gen-smooth16/${g.id}-${i}-character.png`)));
for(let frame=0;frame<224;frame++){
  const time=frame*.05,layers=[];
  for(const [column,g]of groups.entries()){
    const duration=g.frame_durations,cycle=duration.reduce((a,b)=>a+b,0);let remaining=time%cycle,index=0;
    while(index<15&&remaining>=duration[index]){remaining-=duration[index];index++;}
    const full=await sharp(images.get(`${g.id}-${index}`)).composite([
      {input:Buffer.from(festiveEffects(g,time,false,index)),blend:'dest-over'},
      {input:Buffer.from(festiveEffects(g,time,true,index))}
    ]).png().toBuffer();
    layers.push({input:await sharp(full).resize(224,320).png().toBuffer(),left:column*224,top:0});
  }
  await sharp({create:{width:672,height:320,channels:4,background:'#fffaf2'}}).composite(layers).png().toFile(path.join(dir,`${String(frame).padStart(3,'0')}.png`));
}
console.log(JSON.stringify({frames:224,fps:20,duration:11.2,directory:dir}));
