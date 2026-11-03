// 승인한 캐릭터를 보존하며 독립 중간 자세로 16컷을 구성한다. 기존 제작 파일은 덮어쓰지 않는다.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {festiveEffects} from './festive-effects.mjs';
const require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-smooth16'),old=path.join(root,'gen-production'),CW=448,CH=640;
const map=JSON.parse(await fs.readFile(path.join(root,'production-map.json'))),jobs=[...JSON.parse(await fs.readFile(path.join(root,'smooth16-jobs.json'))),...JSON.parse(await fs.readFile(path.join(root,'gait16-jobs.json'))),...JSON.parse(await fs.readFile(path.join(root,'stride16-jobs.json')))],report=[];
const hash=b=>createHash('sha256').update(b).digest('hex');
const originalHashes={};for(const g of map.groups)for(let i=0;i<g.frames;i++){const id=`${g.id}-${i}`;originalHashes[id]=hash(await fs.readFile(path.join(old,`${id}-character.png`)));}
const clean=d=>{for(let p=0;p<d.length;p+=4)if(!d[p+3])d.fill(0,p,p+4);return d;};
const png=d=>sharp(d,{raw:{width:CW,height:CH,channels:4}}).png().toBuffer();
function bounds(d,w=CW,h=CH){let x0=w,y0=h,x1=-1,y1=-1;for(let y=0;y<h;y++)for(let x=0;x<w;x++)if(d[(y*w+x)*4+3]>8){x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);}return [x0,y0,x1+1,y1+1];}
function eyes(d,w,h){const points=[];for(let y=0;y<h*.75;y++)for(let x=0;x<w;x++){const p=(y*w+x)*4;if(d[p+3]>220&&d[p+2]>55&&d[p+2]>d[p]*1.12&&d[p+2]>d[p+1]*1.03)points.push([x,y]);}if(points.length<12)return null;let c=[[Math.min(...points.map(p=>p[0])),points[0][1]],[Math.max(...points.map(p=>p[0])),points[0][1]]];for(let n=0;n<20;n++){const sums=[[0,0,0],[0,0,0]];for(const p of points){const a=Math.hypot(p[0]-c[0][0],p[1]-c[0][1])<Math.hypot(p[0]-c[1][0],p[1]-c[1][1])?0:1;sums[a][0]+=p[0];sums[a][1]+=p[1];sums[a][2]++;}if(sums.some(s=>!s[2]))return null;c=sums.map(s=>[s[0]/s[2],s[1]/s[2]]);}return {gap:Math.hypot(c[1][0]-c[0][0],c[1][1]-c[0][1]),center:[(c[0][0]+c[1][0])/2,(c[0][1]+c[1][1])/2]};}
function allowed(group,x,y,gait=false){
 if(gait)return y>410 && !(x<145&&y<480) && ((x-334)/100)**2+((y-357)/121)**2>1;
 if(group==='idle')return (x>112&&x<184&&y>282&&y<341)||(x>186&&x<268&&y>282&&y<341);
 if(group==='moveRight')return y>430 && ((x-334)/100)**2+((y-357)/121)**2>1;
 if(group==='waving')return x>222&&x<405&&y>335&&y<568;
 if(group==='waiting')return x>238&&x<405&&y>337&&y<535;
 if(group==='thinking')return x>80&&x<345&&y>382&&y<608;
 if(group==='review')return x<245&&y>399;
 if(group==='failed')return x>70&&x<325&&y>401;
 if(group==='sleeping')return x>197&&x<347&&y>450&&y<580;
 if(group==='jumping')return y>420;
 return false;
}
const registered=new Map();
const strideMaster=await sharp(path.join(dir,'moveRight-stride-00-source.png')).ensureAlpha().raw().toBuffer({resolveWithObject:true});
const strideReference=await sharp(path.join(old,'moveRight-0-character.png')).ensureAlpha().raw().toBuffer();
const strideEyes=eyes(strideMaster.data,strideMaster.info.width,strideMaster.info.height),referenceEyes=eyes(strideReference,CW,CH);
const strideBaseScale=referenceEyes.gap/strideEyes.gap;
let strideScale=strideBaseScale;
// Fit the whole pose family around one head anchor; never push a single wide frame sideways.
for(const j of jobs.filter(j=>j.stride)){
 const source=path.join(dir,`${j.id}-source.png`);if(!await fs.stat(source).catch(()=>null))continue;
 const {data,info}=await sharp(source).ensureAlpha().raw().toBuffer({resolveWithObject:true}),b=bounds(data,info.width,info.height),e=eyes(data,info.width,info.height),ratio=strideMaster.info.width/info.width;
 if(!e)throw new Error(`${j.id}: missing shared-profile landmarks`);
 const left=(e.center[0]-b[0])*ratio,right=(b[2]-e.center[0])*ratio;
 strideScale=Math.min(strideScale,(referenceEyes.center[0]-13)/left,(CW-13-referenceEyes.center[0])/right,(CH-24)/((b[3]-b[1])*ratio));
}
if(strideScale<strideBaseScale*.97)throw new Error('Stride source exceeds the shared profile by more than 3%; regenerate the offending pose');
async function registerStride(j){
 const source=path.join(dir,`${j.id}-source.png`),{data,info}=await sharp(source).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const resolutionRatio=strideMaster.info.width/info.width,scale=strideScale*resolutionRatio,sb=bounds(data,info.width,info.height),se=eyes(data,info.width,info.height);
 if(!se)throw new Error(`${j.id}: no eye landmarks for shared registration`);
 if((sb[2]-sb[0])*scale>CW-24||(sb[3]-sb[1])*scale>CH-24)throw new Error(`${j.id}: whole stride exceeds shared profile; regenerate the source`);
 const wantedX=Math.round(referenceEyes.center[0]-se.center[0]*scale);
 const dx=Math.max(Math.ceil(12-sb[0]*scale),Math.min(wantedX,Math.floor(436-sb[2]*scale))),dy=Math.floor(620-sb[3]*scale);
 const w=Math.round(info.width*scale),h=Math.round(info.height*scale),resized=await sharp(data,{raw:{width:info.width,height:info.height,channels:4}}).resize(w,h).raw().toBuffer(),final=Buffer.alloc(CW*CH*4);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){const tx=x+dx,ty=y+dy,p=(y*w+x)*4;if(tx>=0&&tx<CW&&ty>=0&&ty<CH)resized.copy(final,(ty*CW+tx)*4,p,p+4);else if(resized[p+3]>8)throw new Error(`${j.id}: clipped whole stride`);}
 const edgeSource=Buffer.from(final);let matteRemoved=0;
 for(let y=2;y<CH-2;y++)for(let x=2;x<CW-2;x++){
  const p=(y*CW+x)*4;if(!final[p+3])continue;
  const r=final[p],g=final[p+1],b=final[p+2],matte=(r>190&&g>145&&b<100)||(g>170&&g>r*1.35&&g>b*1.5)||(r>200&&b>130&&g<90);
  if(matte&&[[-2,0],[2,0],[0,-2],[0,2]].some(([ox,oy])=>edgeSource[((y+oy)*CW+x+ox)*4+3]<8)){final.fill(0,p,p+4);matteRemoved++;}
 }
 // Independent whole-character sources retain their anatomy; only disconnected generator debris is removed.
 const labels=new Uint8Array(CW*CH),components=[];
 for(let q=0;q<labels.length;q++){if(labels[q]||!final[q*4+3])continue;const pixels=[q];labels[q]=1;for(let at=0;at<pixels.length;at++){const k=pixels[at],x=k%CW,y=Math.floor(k/CW);for(let oy=-1;oy<=1;oy++)for(let ox=-1;ox<=1;ox++){const nx=x+ox,ny=y+oy;if(nx<0||nx>=CW||ny<0||ny>=CH)continue;const n=ny*CW+nx;if(!labels[n]&&final[n*4+3]){labels[n]=1;pixels.push(n);}}}components.push(pixels);}
 const main=components.reduce((a,b)=>a.length>b.length?a:b,[]);let removed=0;for(const c of components)if(c!==main){for(const q of c)final.fill(0,q*4,q*4+4);removed+=c.length;}
 clean(final);const b=bounds(final),e=eyes(final,CW,CH);
 if(b[0]<10||b[1]<10||b[2]>438||b[3]>622)throw new Error(`${j.id}: unsafe registered stride ${b}`);
 await fs.writeFile(path.join(dir,`${j.id}-registered.png`),await png(final));registered.set(j.id,final);
 report.push({id:j.id,source,whole_pose:true,registration_mode:'shared scale, head center x, contact baseline',shared_scale:strideScale,resolution_ratio:resolutionRatio,scale,translation:[dx,dy],bounds:b,eye_gap:e?.gap,eye_center:e?.center,baseline:620,matte_removed:matteRemoved,isolated_pixels_removed:removed,protected_region_check:'not applied: independent full-body pose',anatomy:'pending visual review'});
}
for(const j of jobs){
 const allow=(x,y)=>allowed(j.group,x,y,j.id.includes('-gait-'));
 if(process.argv.includes("--register-only") && !await fs.stat(path.join(dir,`${j.id}-source.png`)).catch(()=>null))continue;
 if(j.stride){await registerStride(j);continue;}
 const reference=await sharp(path.join(old,`${j.canonical_pose??`${j.group}-0`}-character.png`)).ensureAlpha().raw().toBuffer(),source=path.join(dir,`${j.id}-source.png`);
 const {data,info}=await sharp(source).ensureAlpha().raw().toBuffer({resolveWithObject:true});const re=eyes(reference,CW,CH),se=eyes(data,info.width,info.height),rb=bounds(reference),sb=bounds(data,info.width,info.height);
 let scale,dx,dy;
 if(re&&se&&j.group!=='sleeping'){scale=re.gap/se.gap;dx=Math.round(re.center[0]-se.center[0]*scale);dy=Math.round(re.center[1]-se.center[1]*scale);}
 else {scale=(rb[2]-rb[0])/(sb[2]-sb[0]);dx=Math.round(rb[0]-sb[0]*scale);dy=Math.round(rb[3]-sb[3]*scale);}
 // Keep generated pose material inside the approved cell; the protected character is restored below.
 const fit=Math.min((CW-20)/(sb[2]-sb[0]),(CH-20)/(sb[3]-sb[1]));
 if(scale>fit){scale=fit;if(re&&se){dx=Math.round(re.center[0]-se.center[0]*scale);dy=Math.round(re.center[1]-se.center[1]*scale);}else{dx=Math.round((rb[0]+rb[2])/2-(sb[0]+sb[2])/2*scale);dy=Math.round(rb[3]-sb[3]*scale);}}
 dy=Math.min(dy,Math.floor(628-sb[3]*scale));
 dx=Math.max(Math.ceil(10-sb[0]*scale),Math.min(dx,Math.floor(438-sb[2]*scale)));
 if(!Number.isFinite(scale)||scale<.08||scale>1.5)throw new Error(`Unstable registration: ${j.id} ${scale}`);
 const w=Math.round(info.width*scale),h=Math.round(info.height*scale),resized=await sharp(source).ensureAlpha().resize(w,h).raw().toBuffer(),placed=Buffer.alloc(CW*CH*4);let clipped=0;
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){const p=(y*w+x)*4,tx=x+dx,ty=y+dy;if(tx>=0&&tx<CW&&ty>=0&&ty<CH)resized.copy(placed,(ty*CW+tx)*4,p,p+4);else if(resized[p+3]>8)clipped++;}
 if(clipped>60)throw new Error(`${j.id}: registration clips ${clipped}`);
 const final=Buffer.from(reference);let changed=0,lockedChanges=0;
 for(let y=0;y<CH;y++)for(let x=0;x<CW;x++){const p=(y*CW+x)*4;if(allow(x,y)){let edge=12;
 for(let step=1;step<=12;step++)if(!allow(x-step,y)||!allow(x+step,y)||!allow(x,y-step)||!allow(x,y+step)){edge=step;break;}
 const weight=Math.min(1,edge/12);
 const alpha=reference[p+3]*(1-weight)+placed[p+3]*weight;
 for(let c=0;c<3;c++)final[p+c]=alpha?Math.round((reference[p+c]*reference[p+3]*(1-weight)+placed[p+c]*placed[p+3]*weight)/alpha):0;
 final[p+3]=Math.round(alpha);
 if(!reference.subarray(p,p+4).equals(final.subarray(p,p+4)))changed++;}else if(!reference.subarray(p,p+4).equals(final.subarray(p,p+4)))lockedChanges++;}
 if(j.whole_pose){placed.copy(final);changed=1;lockedChanges=0;}
 // Remove coloured cutout matte only at generated transparent edges, keeping original protected pixels.
 const alphaSnapshot=Buffer.from(final);let matteRemoved=0;
 for(let y=2;y<CH-2;y++)for(let x=2;x<CW-2;x++){
  const p=(y*CW+x)*4;if(!allow(x,y)||!final[p+3])continue;
  const bad=(final[p]>205&&final[p+1]>165&&final[p+2]<60)||(final[p]>225&&final[p+1]<45&&final[p+2]<45);
  if(!bad)continue;let edge=false;for(const [dx,dy]of [[-2,0],[2,0],[0,-2],[0,2]])if(alphaSnapshot[((y+dy)*CW+x+dx)*4+3]<8)edge=true;
  if(edge){final.fill(0,p,p+4);matteRemoved++;}
 }
 // Rejecting/discarding small isolated generated fragments does not remove attached limbs.
 const labels=new Int32Array(CW*CH),components=[],componentThreshold=j.id.includes('-gait-')?0:8;let label=0;
 for(let q=0;q<labels.length;q++){if(labels[q]||final[q*4+3]<=componentThreshold)continue;label++;const pixels=[q];labels[q]=label;
 for(let cursor=0;cursor<pixels.length;cursor++){const at=pixels[cursor],x=at%CW,y=Math.floor(at/CW);for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){const nx=x+dx,ny=y+dy;if(nx<0||nx>=CW||ny<0||ny>=CH)continue;const next=ny*CW+nx;if(!labels[next]&&final[next*4+3]>componentThreshold){labels[next]=label;pixels.push(next);}}}components.push(pixels);}
 const main=components.reduce((best,c)=>c.length>best.length?c:best,[]);let fragmentsRemoved=0;
 for(const c of components){if(c===main||(c.length>1200&&!j.id.includes('-gait-'))||c.some(q=>!allow(q%CW,Math.floor(q/CW))))continue;for(const q of c){final.fill(0,q*4,q*4+4);fragmentsRemoved++;}}
 clean(final);const b=bounds(final);if(b[0]<8||b[1]<8||b[2]>440||b[3]>632)throw new Error(`${j.id}: unsafe character bounds ${b}`);
 if((changed<15&&!j.whole_pose)||lockedChanges)throw new Error(`${j.id}: no pose change or protected-region drift`);
 const dest=path.join(dir,`${j.id}-registered.png`);await fs.writeFile(dest,await png(final));registered.set(j.id,final);
 report.push({id:j.id,source,reference:j.reference,scale,translation:[dx,dy],bounds:b,changed_pixels:changed,protected_pixel_changes:lockedChanges,clipped_source_pixels:clipped,matte_removed:matteRemoved,isolated_pixels_removed:fragmentsRemoved,anatomy:'pending visual review',whole_pose:!!j.whole_pose,protected_region_check:j.whole_pose?'not applicable to complete new takeoff pose':'outside declared mask'});
}
await fs.writeFile(path.join(dir,'registration.json'),JSON.stringify(report,null,2));
if(process.argv.includes('--register-only')){console.log(JSON.stringify({registered:report.length}));process.exit(0);}
const o=(id,n)=>`${id}-${n}`,n=(id,i)=>`${id}-new-${i}`;
const seq={
 moveRight:Array.from({length:16},(_,i)=>`moveRight-stride-${String(i).padStart(2,'0')}`),
 idle:[0,0,0,0,0,n('idle',0),3,n('idle',1),4,n('idle',1),3,n('idle',0),0,0,0,0].map(v=>typeof v==='number'?o('idle',v):v),
 waving:[o('waving',3),n('waving',5),n('waving',3),n('waving',4),o('waving',0),n('waving',1),n('waving',2),o('waving',1),n('waving',2),n('waving',1),o('waving',0),n('waving',4),n('waving',3),n('waving',5),o('waving',3),o('waving',3)],
 waiting:[0,n('waiting',0),n('waiting',1),1,n('waiting',1),n('waiting',0),0,n('waiting',2),n('waiting',3),3,n('waiting',3),n('waiting',2),0,0,0,0].map(v=>typeof v==='number'?o('waiting',v):v),
 thinking:[0,n('thinking',0),n('thinking',1),1,n('thinking',1),n('thinking',0),0,n('thinking',2),n('thinking',3),2,2,n('thinking',3),n('thinking',2),0,0,0].map(v=>typeof v==='number'?o('thinking',v):v),
 review:[0,n('review',0),n('review',1),1,n('review',2),n('review',3),2,2,2,n('review',3),n('review',2),1,n('review',1),n('review',0),0,0].map(v=>typeof v==='number'?o('review',v):v),
 failed:[0,n('failed',0),n('failed',1),1,1,n('failed',1),n('failed',0),0,n('failed',2),n('failed',3),4,4,n('failed',3),n('failed',2),0,0].map(v=>typeof v==='number'?o('failed',v):v),
 sleeping:[0,n('sleeping',0),1,n('sleeping',1),2,2,2,2,2,n('sleeping',1),1,n('sleeping',0),0,0,0,0].map(v=>typeof v==='number'?o('sleeping',v):v),
 jumping:[n('jumping',0),o('jumping',0),n('jumping',3),n('jumping',4),n('jumping',4),n('jumping',5),n('jumping',2),o('jumping',2),n('jumping',2),o('jumping',2),n('jumping',2),n('jumping',5),n('jumping',4),n('jumping',4),n('jumping',3),n('jumping',0)]
};
const timing=JSON.parse(await fs.readFile(path.resolve(root,'../../assets/christmas-16-timing.json')));
const cells=[],groups=[],attachments={};
for(const g of map.groups){const sequence=seq[g.id]??seq.moveRight;if(sequence.length!==16)throw new Error('Invalid sequence');const ext={...g,frames:16,interval:timing.cycle_seconds[g.row]/16,effect_period:timing.effect_periods[g.id],source_directory:'gen-smooth16',sources:sequence};delete ext.keyframes;delete ext.pose_sequence;
 const cycle=timing.cycle_seconds[g.row],isGesture=!['moveRight','moveLeft','sleeping'].includes(g.id);
 const holds=sequence.map((source,i)=>g.id==='jumping'?[0,8].includes(i):source===sequence[(i+15)%16]||sequence[(i+15)%16]===sequence[(i+1)%16]||i===0);
 const moving=isGesture?(g.id==='idle'?.055:g.id==='jumping'?.065:.085):cycle/16;
 const holdCount=holds.filter(Boolean).length;
 ext.frame_durations=holds.map(hold=>isGesture&&hold?(cycle-moving*(16-holdCount))/holdCount:moving);
 timing.frame_seconds??={};timing.frame_seconds[g.row]=ext.frame_durations;

 const frames=[];for(let i=0;i<16;i++){
 let char=registered.has(sequence[i])?Buffer.from(registered.get(sequence[i])):await sharp(path.join(old,`${sequence[i]}-character.png`)).ensureAlpha().raw().toBuffer();
 if(g.id==='moveLeft')char=await sharp(char,{raw:{width:CW,height:CH,channels:4}}).flop().raw().toBuffer();
 if(g.id==='jumping'){
  const b=bounds(char),master=await sharp(path.join(old,'jumping-0-character.png')).ensureAlpha().raw().toBuffer(),center=eyes(char,CW,CH)?.center[1],groundCenter=eyes(master,CW,CH).center[1];
  const elevation=[0,0,12,30,60,85,100,110,115,110,100,85,60,30,12,0][i];
  const wanted=Math.round(groundCenter-elevation-center),shift=Math.max(8-b[1],Math.min(628-b[3],wanted)),translated=Buffer.alloc(char.length);
  for(let y=0;y<CH;y++){const ty=y+shift;if(ty>=0&&ty<CH)char.copy(translated,ty*CW*4,y*CW*4,(y+1)*CW*4);}char=translated;
 }
 clean(char);const b=bounds(char);if(b[0]<8||b[1]<8||b[2]>440||b[3]>632)throw new Error(`Unsafe final ${g.id}-${i}: ${b}`);
 await fs.writeFile(path.join(dir,`${g.id}-${i}-character.png`),await png(char));frames.push(char);cells.push({id:`${g.id}-${i}`,row:g.row,column:i,source:sequence[i],bounds:b});}
 // Keep effect attachment metadata with the same cells used by native and web renderers.
 ext.effect_anchors=frames.map((d,i)=>{
 const source=sequence[i],oldIndex=source.includes('-new-')?0:Number(source.split('-').at(-1)),key=g.pose_sequence?.[oldIndex]??0;
 if(g.id==='review'||g.id==='waiting'){
  const x0=g.id==='review'?25:280,x1=g.id==='review'?123:395,y0=g.id==='review'?420:396,y1=g.id==='review'?537:501,rows=[];
  for(let y=y0;y<y1;y++){const xs=[];for(let x=x0;x<x1;x++){const p=(y*CW+x)*4;if(d[p+3]>200&&d[p]>145&&d[p+1]>85&&d[p+2]<d[p]*.64&&d[p+1]>d[p+2]*1.25)xs.push(x);}rows.push({y,xs});}
  const max=Math.max(...rows.map(r=>r.xs.length)),selected=rows.filter(r=>r.xs.length>max*.6),points=selected.flatMap(r=>r.xs.map(x=>[x,r.y]));
  if(points.length>20)return [[points.reduce((s,p)=>s+p[0],0)/points.length,points.reduce((s,p)=>s+p[1],0)/points.length]];
 }
 if(g.id==='review')return [[77,key===2?468:494]];
 if(g.id==='waiting'){const delta=source.includes('-new-')?[-4,-8,4,8][Number(source.split('-').at(-1))]:0;return [[(key===1?308:key===2?355:329)+delta,key===1?454:438]];}
 if(g.id==='failed'&&source.includes('-new-')){const k=Number(source.split('-').at(-1));return [[[126,555],[173,574],[195,615],[217,608],[269,597]],[[144,515],[158,550],[182,598],[262,584],[159,530]],[[290,555],[237,585],[166,598],[201,604],[259,599]],[[290,450],[237,580],[166,598],[201,604],[259,599]]][k];}
 if(g.id==='failed')return key===1?[[144,475],[158,523],[182,578],[262,584],[159,490]]:key===2?[[290,397],[237,571],[166,598],[201,604],[259,599]]:[[126,593],[173,608],[195,615],[217,608],[269,597]];
 return [];});
 attachments[g.id==='thinking'?'running':g.id]=ext.effect_anchors;groups.push(ext);
 for(let i=0;i<16;i++){const back=await sharp(Buffer.from(festiveEffects(ext,ext.frame_durations.slice(0,i).reduce((a,b)=>a+b,0),false,i))).png().toBuffer(),front=await sharp(Buffer.from(festiveEffects(ext,ext.frame_durations.slice(0,i).reduce((a,b)=>a+b,0),true,i))).png().toBuffer();await sharp(frames[i],{raw:{width:CW,height:CH,channels:4}}).composite([{input:back,blend:'dest-over'},{input:front}]).png().toFile(path.join(dir,`${g.id}-${i}-complete.png`));}
}
const gazeMaster=await sharp(path.join(old,'idle-0-character.png')).ensureAlpha().raw().toBuffer();
for(const gaze of map.gaze){
 const file=`${gaze.id}-character.png`,source=await sharp(path.join(old,`${gaze.id}-registered.png`)).ensureAlpha().raw().toBuffer(),final=Buffer.from(gazeMaster);
 // Assemble the coherent generated head/neck over the locked body along a curved collar boundary.
 // The tail is always the master, rather than half generated and half master at a horizontal cut.
 for(let y=0;y<CH;y++)for(let x=0;x<CW;x++){
  const at=(y*CW+x)*4,boundary=460-.22*Math.abs(x-184),distance=boundary-y;
  let weight=Math.max(0,Math.min(1,(distance+12)/24));
  if(x>300&&y>405)weight=0;
  if(weight>0&&weight<1&&(source[at+3]<240||gazeMaster[at+3]<240))weight=distance>0?1:0;
  const alpha=source[at+3]*weight+gazeMaster[at+3]*(1-weight);
  for(let c=0;c<3;c++)final[at+c]=alpha?Math.round((source[at+c]*source[at+3]*weight+gazeMaster[at+c]*gazeMaster[at+3]*(1-weight))/alpha):0;
  final[at+3]=Math.round(alpha);
 }
 clean(final);await fs.writeFile(path.join(dir,file),await png(final));cells.push({id:gaze.id,row:gaze.row,column:gaze.column,source:`${gaze.id}-registered.png`});
}
const layers=await Promise.all(cells.map(async c=>({input:await fs.readFile(path.join(dir,`${c.id}-character.png`)),left:c.column*CW,top:c.row*CH})));
const atlas=path.join(dir,'character-atlas.png');await sharp({create:{width:CW*16,height:CH*12,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite(layers).png().toFile(atlas);
const output=path.resolve(root,'../../assets/spritesheet-christmas-16-character.webp');execFileSync('cwebp',['-quiet','-lossless','-exact',atlas,'-o',output]);
await fs.writeFile(path.resolve(root,'../../assets/christmas-16-attachments.json'),JSON.stringify(attachments));
await fs.writeFile(path.resolve(root,'../../assets/christmas-16-timing.json'),JSON.stringify(timing,null,2)+'\n');
await fs.writeFile(path.join(root,'smooth16-map.json'),JSON.stringify({version:16,groups,gaze:map.gaze,columns:16,rows:12,mapped_cells:176},null,2)+'\n');
for(const [id,h]of Object.entries(originalHashes))if(hash(await fs.readFile(path.join(old,`${id}-character.png`)))!==h)throw new Error(`Approved source changed: ${id}`);
await fs.writeFile(path.join(dir,'validation.json'),JSON.stringify({mapped_cells:cells.length,new_independent_poses:report.length,approved_character_changes:0,registration:report,cells,visual_review:'pending'},null,2)+'\n');
console.log(JSON.stringify({mapped_cells:cells.length,new_independent_poses:report.length,atlas:output}));

// Apply the approved scoped accessory repair after the original gesture assembly.
if(await fs.stat(path.join(root,'gen-secondary/generated-sources.json')).catch(()=>null))execFileSync(process.execPath,[path.join(root,'secondary-motion.mjs')],{stdio:'inherit',env:process.env});
