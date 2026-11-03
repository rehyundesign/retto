import fs from 'node:fs/promises';
import path from 'node:path';
import{createRequire}from'node:module';
import{fileURLToPath}from'node:url';
const require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-production');
const sources=JSON.parse(await fs.readFile(path.join(root,'production-sources.json')));
const master=await sharp(path.join(root,'gen-festive/idle-0-character.png')).ensureAlpha().raw().toBuffer({resolveWithObject:true});
function clean(data){for(let i=0;i<data.length;i+=4)if(!data[i+3])data.fill(0,i,i+4);return data;}
function buttons(data,w,h){
  const points=[];for(let y=Math.floor(h*.50);y<Math.floor(h*.85);y++)for(let x=Math.floor(w*.38);x<Math.floor(w*.56);x++){
    const p=(y*w+x)*4,[r,g,b,a]=data.subarray(p,p+4);if(a>220&&r>130&&g>80&&r>b*1.9&&g>b*1.3&&r>g*1.08)points.push([x,y]);
  }
  if(points.length<20)throw new Error('Cannot locate coat gold hardware');
  const lines=new Map();for(const p of points){if(!lines.has(p[1]))lines.set(p[1],[]);lines.get(p[1]).push(p);}
  const segments=[];let last=-Infinity;for(const y of [...lines.keys()].sort((a,b)=>a-b)){if(y-last>3)segments.push([]);segments.at(-1).push(...lines.get(y));last=y;}
  const selected=segments.sort((a,b)=>b.length-a.length).slice(0,3);if(selected.length!==3)throw new Error('Cannot distinguish two buttons and belt buckle');
  return selected.map(ps=>[ps.reduce((s,p)=>s+p[0],0)/ps.length,ps.reduce((s,p)=>s+p[1],0)/ps.length]).sort((a,b)=>a[1]-b[1]);
}
function bounds(data,w,h){let l=w,t=h,r=-1,b=-1;for(let y=0;y<h;y++)for(let x=0;x<w;x++)if(data[(y*w+x)*4+3]>8){l=Math.min(l,x);t=Math.min(t,y);r=Math.max(r,x);b=Math.max(b,y);}return[l,t,r+1,b+1];}
function blueFeatures(data,w,h){let sx=0,sy=0,n=0;for(let y=0;y<h*.67;y++)for(let x=0;x<w;x++){const p=(y*w+x)*4;if(data[p+3]>220&&data[p+2]>50&&data[p+2]>data[p]*1.12&&data[p+2]>data[p+1]*1.03){sx+=x;sy+=y;n++;}}return n?[sx/n,sy/n,n]:null;}
const targetButtons=buttons(master.data,448,640),reports=[];
for(const[id,source]of Object.entries(sources)){
  await fs.copyFile(source,path.join(dir,`${id}-source.png`));
  const original=await sharp(source).ensureAlpha().raw().toBuffer({resolveWithObject:true}),srcButtons=buttons(original.data,original.info.width,original.info.height);
  const scale=(targetButtons[2][1]-targetButtons[0][1])/(srcButtons[2][1]-srcButtons[0][1]);
  const dx=Math.round(targetButtons[0][0]-srcButtons[0][0]*scale),dy=Math.round(targetButtons[0][1]-srcButtons[0][1]*scale);
  const w=Math.round(original.info.width*scale),h=Math.round(original.info.height*scale),pixels=await sharp(source).ensureAlpha().resize(w,h).raw().toBuffer(),data=Buffer.alloc(448*640*4);let clipped=0;
  for(let y=0;y<h;y++)for(let x=0;x<w;x++){const p=(y*w+x)*4,tx=x+dx,ty=y+dy;if(tx<0||tx>=448||ty<0||ty>=640){if(pixels[p+3]>8)clipped++;}else pixels.copy(data,(ty*448+tx)*4,p,p+4);}
  if(clipped)throw new Error(`${id}: registration clips ${clipped} pixels`);
  clean(data);
  await sharp(data,{raw:{width:448,height:640,channels:4}}).png().toFile(path.join(dir,`${id}-registered.png`));
  // Gaze changes only the upper silhouette. Keep the approved seated torso, limbs and tail exactly.
  // Waving keeps its generated arm construction, but its frontal face/hat is the approved master.
  const final=Buffer.from(data);
  if(id.startsWith('gaze'))for(let y=444;y<640;y++)master.data.copy(final,y*448*4,y*448*4,(y+1)*448*4);
  if(id.startsWith('waving')){
    const index=Number(id.split('-')[1]),occluder=[[298,399,38,49],[336,386,42,49],[277,386,45,49],null][index];
    for(let y=0;y<412;y++)for(let x=0;x<448;x++){
      const p=(y*448+x)*4;
      const distance=occluder?((x-occluder[0])/occluder[2])**2+((y-occluder[1])/occluder[3])**2:Infinity;
      let weight=Math.min(1,Math.max(0,(1-distance)*12));
      if(occluder){
        const ax=occluder[0],ay=occluder[1],bx=266,by=478,vx=bx-ax,vy=by-ay;
        const t=Math.min(1,Math.max(0,((x-ax)*vx+(y-ay)*vy)/(vx*vx+vy*vy)));
        const armDistance=Math.hypot(x-ax-t*vx,y-ay-t*vy);
        weight=Math.max(weight,Math.min(1,Math.max(0,(1-armDistance/48)*8)));
      }
      for(let c=0;c<4;c++)final[p+c]=Math.round(master.data[p+c]*(1-weight)+data[p+c]*weight);
    }
  }
  clean(final);const finalBounds=bounds(final,448,640);if(finalBounds[0]<8||finalBounds[1]<8||finalBounds[2]>440||finalBounds[3]>632)throw new Error(`${id}: unsafe bounds ${finalBounds}`);
  await sharp(final,{raw:{width:448,height:640,channels:4}}).png().toFile(path.join(dir,`${id}-character.png`));
  const direction=id.startsWith('gaze')?Number(id.split('-')[1]):null;
  let canonical=null;if(direction!==null){const b=await sharp(path.join(dir,`base-gaze-${direction}.png.clean.png`)).resize(448,640).ensureAlpha().raw().toBuffer();canonical={cell:[9+Math.floor(direction/8),direction%8],iris:blueFeatures(b,448,640),bounds:bounds(b,448,640)};}
  reports.push({id,source,scale,translation:[dx,dy],coat_hardware:buttons(final,448,640),bounds:finalBounds,iris:blueFeatures(final,448,640),canonical_original:canonical,locked_region:id.startsWith('gaze')?'y>=444 torso/paws/tail':'y<412 frontal head/hat',four_limbs:'review-required',registration_status:'candidate-review-required'});
}
await fs.writeFile(path.join(dir,'registration.json'),JSON.stringify({targetButtons,reports},null,2)+'\n');
console.log(JSON.stringify({registered:reports.length,targetButtons}));
