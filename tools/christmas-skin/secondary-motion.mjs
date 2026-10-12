// Independently drawn ear and cap-tip poses over the locked approved character cells.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
const root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-secondary'),before=path.join(dir,'before'),production=path.join(root,'gen-smooth16'),W=448,H=640;
const require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const phases=['rest','right-mid','right','left-mid','left'];
const earPhases=[0,0,0,0,0,1,2,1,0,3,4,3,0,0,0,0];
// Use one coherently drawn upper pose so ears and cap fabric never have an internal cut.
const pomPhases=[...earPhases];
const hash=data=>createHash('sha256').update(data).digest('hex');
function eyeProfile(data,w,h){
 const points=[];for(let y=0;y<h*.75;y++)for(let x=0;x<w;x++){const p=(y*w+x)*4;if(data[p+3]>220&&data[p+2]>55&&data[p+2]>data[p]*1.12&&data[p+2]>data[p+1]*1.03)points.push([x,y]);}
 if(points.length<12)throw new Error('Eye registration landmarks missing');
 let c=[[Math.min(...points.map(p=>p[0])),points[0][1]],[Math.max(...points.map(p=>p[0])),points[0][1]]];
 for(let n=0;n<20;n++){const sum=[[0,0,0],[0,0,0]];for(const p of points){const a=Math.hypot(p[0]-c[0][0],p[1]-c[0][1])<Math.hypot(p[0]-c[1][0],p[1]-c[1][1])?0:1;sum[a][0]+=p[0];sum[a][1]+=p[1];sum[a][2]++;}if(sum.some(s=>!s[2]))throw new Error('Eye cluster missing');c=sum.map(s=>[s[0]/s[2],s[1]/s[2]]);}
 return {gap:Math.hypot(c[1][0]-c[0][0],c[1][1]-c[0][1]),center:[(c[0][0]+c[1][0])/2,(c[0][1]+c[1][1])/2]};
}
function polygon(x,y,points){let inside=false;for(let i=0,j=points.length-1;i<points.length;j=i++){const a=points[i],b=points[j];if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])inside=!inside;}return inside;}
const frontBoundaries=new Map();
function allowed(profile,x,y,layer){
 if(x<55||x>=414||y<135)return false;
 if(x<302)return y<frontBoundaries.get(profile)[x];
 return y<(profile==='idle'?365:407);
}
function clean(data){for(let p=0;p<data.length;p+=4)if(!data[p+3])data.fill(0,p,p+4);return data;}
function cleanFragments(data){
 const visited=new Uint8Array(W*H);let removed=0;
 for(let start=0;start<visited.length;start++){
  if(visited[start]||data[start*4+3]<=8)continue;const queue=[start];visited[start]=1;
  for(let q=0;q<queue.length;q++){const n=queue[q],x=n%W,y=Math.floor(n/W);for(const [dx,dy]of [[-1,0],[1,0],[0,-1],[0,1],[-1,-1],[1,-1],[-1,1],[1,1]]){const nx=x+dx,ny=y+dy;if(nx<0||nx>=W||ny<0||ny>=H)continue;const z=ny*W+nx;if(!visited[z]&&data[z*4+3]>8){visited[z]=1;queue.push(z);}}}
  if(queue.length<100){for(const n of queue)data.fill(0,n*4,n*4+4);removed+=queue.length;}
 }
 return removed;
}
await fs.mkdir(path.join(dir,'registered'),{recursive:true});
const raw=async file=>sharp(file).ensureAlpha().raw().toBuffer();
const layers=new Map(),registration=[];
for(const profile of ['idle','thinking']){
 const base=await raw(path.join(before,`${profile}-0-character.png`)),target=eyeProfile(base,W,H);layers.set(`${profile}-rest`,base);
 const boundary=Array.from({length:W},(_,x)=>profile==='idle'
  ?235+.0042*(x-184)**2
  :267+.0043*(x-178)**2+.15*(x-178));
 frontBoundaries.set(profile,boundary);

 for(const phase of phases.slice(1)){
  const source=path.join(dir,'sources',`${profile}-${phase}.png`),{data,info}=await sharp(source).ensureAlpha().raw().toBuffer({resolveWithObject:true}),eyes=eyeProfile(data,info.width,info.height),scale=target.gap/eyes.gap;
  const width=Math.round(info.width*scale),height=Math.round(info.height*scale),resized=await sharp(data,{raw:info}).resize(width,height).raw().toBuffer(),found=eyeProfile(resized,width,height),dx=Math.round(target.center[0]-found.center[0]),dy=Math.round(target.center[1]-found.center[1]),final=Buffer.alloc(W*H*4);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){const tx=x+dx,ty=y+dy;if(tx>=0&&tx<W&&ty>=0&&ty<H)resized.copy(final,(ty*W+tx)*4,(y*width+x)*4,(y*width+x)*4+4);}
  let matte=0;for(let i=0;i<final.length;i+=4){const [r,g,b,a]=final.subarray(i,i+4);if(a>0&&a<250&&((g>r*1.08&&g>b*1.2)||(r>100&&g>100&&b<Math.min(r,g)*.55)||(r>b*1.2&&g<Math.min(r,b)*.65))){final.fill(0,i,i+4);matte++;}}
  const fragments=cleanFragments(final);clean(final);layers.set(`${profile}-${phase}`,final);await sharp(final,{raw:{width:W,height:H,channels:4}}).png().toFile(path.join(dir,'registered',`${profile}-${phase}.png`));registration.push({profile,phase,scale,translation:[dx,dy],matte,fragments,scope:'coherent hat and ear layer behind locked original brim/face; generated face/body discarded'});
 }
}
const report=[];
for(const group of ['idle','waving','thinking']){
 const profile=group==='thinking'?'thinking':'idle',canonical=layers.get(`${profile}-rest`);
 for(let frame=0;frame<16;frame++){
  const base=await raw(path.join(before,`${group}-${frame}-character.png`)),final=Buffer.from(base),ear=layers.get(`${profile}-${phases[earPhases[frame]]}`),pom=layers.get(`${profile}-${phases[pomPhases[frame]]}`);let changed=0;
  for(const [kind,source,key]of [['upper',ear,earPhases[frame]]]){
   if(key===0)continue;
   for(let y=0;y<H;y++)for(let x=0;x<W;x++){
    if(!allowed(profile,x,y,kind))continue;const p=(y*W+x)*4;
    const faceTop=profile==='idle'?275:310,faceY=profile==='idle'?342:370;
    const pomCenter=profile==='idle'?[330,315]:[341,347];
    const oldPomShadow=x>=292&&Math.hypot(x-pomCenter[0],y-pomCenter[1])<44&&base[p]-base[p+1]>12&&base[p+1]-base[p+2]>10;
    if(!oldPomShadow&&y>=faceTop&&((x-184)/120)**2+((y-faceY)/110)**2<=1)continue;
    // Keep the already-approved raised paw in front of the cap end.
    if(group==='waving'&&!oldPomShadow&&y>=335&&base[p+3]>0&&Math.max(...base.subarray(p,p+4).map((v,i)=>Math.abs(v-canonical[p+i])))>0)continue;
    const distance=x<302?frontBoundaries.get(profile)[x]-y:8;
    let weight=Math.min(1,Math.max(0,distance/4));
    if(weight<1&&(source[p+3]<230||base[p+3]<230))weight=distance>2?1:0;
    const alpha=source[p+3]*weight+base[p+3]*(1-weight);
    for(let channel=0;channel<3;channel++)final[p+channel]=alpha?Math.round((source[p+channel]*source[p+3]*weight+base[p+channel]*base[p+3]*(1-weight))/alpha):0;
    final[p+3]=Math.round(alpha);
   }
  }
  const cleaned=Buffer.from(final);cleanFragments(cleaned);
  for(let y=0;y<H;y++)for(let x=0;x<W;x++){
   if(allowed(profile,x,y,'upper')){const at=(y*W+x)*4;cleaned.copy(final,at,at,at+4);}
  }
  clean(final);let protectedChanges=0;
  for(let y=0;y<H;y++)for(let x=0;x<W;x++){
   const p=(y*W+x)*4;if(!final.subarray(p,p+4).equals(base.subarray(p,p+4))){changed++;if(!allowed(profile,x,y,'ears')&&!allowed(profile,x,y,'pom'))protectedChanges++;}
  }
  if(protectedChanges)throw new Error(`Protected face/body changed: ${group}-${frame}`);
  const output=path.join(production,`${group}-${frame}-character.png`);await sharp(final,{raw:{width:W,height:H,channels:4}}).png().toFile(output);
  report.push({group,frame,profile,ear_phase:phases[earPhases[frame]],pom_phase:phases[pomPhases[frame]],changed_pixels:changed,protected_pixel_changes:protectedChanges,protected_regions:'eyes, muzzle, face, torso, paws, costume, tail outside declared ear/cap-end repair masks',body_and_foot_baseline:'unchanged pixels below mask',anatomy:'four original limbs retained; visual occlusion review required'});
 }
}
const validation=JSON.parse(await fs.readFile(path.join(production,'validation.json')));
// Preserve the approved encoded RGBA everywhere outside the independently edited accessory pixels.
const originalAtlas=await sharp(path.join(before,'spritesheet-christmas-16-character.webp')).ensureAlpha().raw().toBuffer({resolveWithObject:true});
for(const cell of validation.cells){
 if(!['idle','waving','thinking'].includes(cell.id.split('-')[0]))continue;
 const current=await raw(path.join(production,`${cell.id}-character.png`)),base=await raw(path.join(before,`${cell.id}-character.png`));
 for(let y=0;y<H;y++)for(let x=0;x<W;x++){
  const at=(y*W+x)*4;
  if(current.readUInt32LE(at)!==base.readUInt32LE(at))current.copy(originalAtlas.data,((cell.row*H+y)*originalAtlas.info.width+cell.column*W+x)*4,at,at+4);
 }
}
const atlas=path.join(dir,'character-atlas.png');await sharp(originalAtlas.data,{raw:originalAtlas.info}).png().toFile(atlas);
execFileSync('cwebp',['-quiet','-lossless','-exact',atlas,'-o',path.resolve(root,'../../assets/spritesheet-christmas-16-character.webp')]);
const oldHashes=JSON.parse(await fs.readFile(path.join(before,'hashes.json')));let unchanged=0;
for(const [file,value]of Object.entries(oldHashes)){if(!file.endsWith('-character.png')||/\/(idle|waving|thinking)-\d+-character.png$/.test(file))continue;if(hash(await fs.readFile(file))!==value)throw new Error(`Out of scope cell changed: ${file}`);unchanged++;}
await fs.writeFile(path.join(dir,'validation.json'),JSON.stringify({cells:report,registration,ear_phases:earPhases,pom_phases:pomPhases,untouched_cells:unchanged,actual_changed_cells:report.filter(c=>c.changed_pixels>0).length,visual_review:'pending white/dark 1x; no full-original identity landmark claim'},null,2)+'\n');
const configPath=path.join(root,'smooth16-map.json'),config=JSON.parse(await fs.readFile(configPath));
for(const group of config.groups)if(['idle','waving','thinking'].includes(group.id))group.secondary_motion={profile:group.id==='thinking'?'thinking':'idle',source_directory:'gen-secondary/registered',pose_phases:earPhases,mode:'independently drawn coherent ear/cap layer behind original face and foreground paws'};
await fs.writeFile(configPath,JSON.stringify(config,null,2)+'\n');
console.log(JSON.stringify({target_cells:report.length,actual_changed_cells:report.filter(c=>c.changed_pixels>0).length,untouched_cells:unchanged,protected_pixel_changes:0}));
