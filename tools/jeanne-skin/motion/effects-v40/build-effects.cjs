const fs=require('fs'),path=require('path');
const sharp=require('/Users/luxia/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root=__dirname,base=path.resolve(root,'../effects-v36'),W=448,H=640,TAU=Math.PI*2;
const targets=new Set(['running']);
const prevRoot=path.resolve(root,'../effects-v39');
const relative=f=>path.relative(root,path.resolve(prevRoot,f));
const previous=JSON.parse(fs.readFileSync(path.join(prevRoot,'manifest.json')));
const states=JSON.parse(fs.readFileSync(path.join(base,'state-effect-direction.json'))).states;
const lock=JSON.parse(fs.readFileSync(path.join(base,'approved-motion-lock.json')));
const names={idle:'기본 대기',running:'작업 · 봉인',review:'검토',waiting:'입력 대기',failed:'오류',waving:'완료 · 승리 인사',jumping:'점프',sleeping:'수면','drag-right':'오른쪽 이동','drag-left':'왼쪽 이동'};
let feather,ribbon,ribbonArc,wingFan,magicSeal;
const n=v=>Number(v.toFixed(3)),sin=t=>Math.sin(TAU*t),cos=t=>Math.cos(TAU*t),fract=t=>t-Math.floor(t);
function star(x,y,r,a=1){r*=1.35;return `<g opacity="${n(a)}" transform="translate(${n(x)} ${n(y)})"><path d="M0 ${-r} Q${r*.2} ${-r*.2} ${r} 0 Q${r*.2} ${r*.2} 0 ${r} Q${-r*.2} ${r*.2} ${-r} 0 Q${-r*.2} ${-r*.2} 0 ${-r}Z" fill="url(#star)"/><circle r="${r*.13}" fill="#fffde5"/></g>`;}
function glow(x,y,r,a=1){return `<circle cx="${n(x)}" cy="${n(y)}" r="${n(r)}" fill="url(#glow)" opacity="${n(a)}"/>`;}
function fthr(x,y,size,angle,a=1){size*=2.15;x=Math.max(size*.64,Math.min(W-size*.64,x));y=Math.max(size*.64,Math.min(H-size*.64,y));return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)})" opacity="${n(a)}"><ellipse rx="${size*.55}" ry="${size*.62}" fill="url(#featherGlow)" opacity=".8"/><image xlink:href="${feather}" x="${-size*.24}" y="${-size*.5}" width="${size*.48}" height="${size}" preserveAspectRatio="none"/></g>`;}
function silk(x,y,size,angle,a=1,flip=1,flat=false){const w=size*(flat?1.8:1.1),h=size*(flat?.36:1);return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)}) scale(${flip} 1)" opacity="${n(a)}"><image xlink:href="${ribbon}" x="${-w*.5}" y="${-h*.5}" width="${w}" height="${h}" preserveAspectRatio="none"/></g>`;}
function petal(x,y,size,angle,a=1){return `<g opacity="${n(a)}" transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)})"><path d="M0 ${-size} C${size*1.4} ${-size*.5} ${size*.65} ${size*.8} 0 ${size} C${-size*.8} ${size*.3} ${-size*.9} ${-size*.8} 0 ${-size}Z" fill="url(#petal)" stroke="#f8b0ad" stroke-width=".65"/></g>`;}
function arc(x,y,w,angle,a=1){return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)})" opacity="${n(a)}"><image xlink:href="${ribbonArc}" x="${-w/2}" y="${-w/6}" width="${w}" height="${w/3}"/></g>`;}
function fan(x,y,w,a=1,angle=0){return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)})" opacity="${n(a)}"><image xlink:href="${wingFan}" x="${-w/2}" y="${-w/6}" width="${w}" height="${w/3}"/></g>`;}
function svg(body){return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="448" height="640" viewBox="0 0 448 640"><defs><filter id="softRay" x="-25%" y="-25%" width="150%" height="150%"><feGaussianBlur stdDeviation="1.8"/></filter><radialGradient id="backRay" gradientUnits="userSpaceOnUse" cx="218" cy="400" r="310"><stop stop-color="#fffef2"/><stop offset=".44" stop-color="#fffce7" stop-opacity=".98"/><stop offset=".75" stop-color="#ffe6a1" stop-opacity=".8"/><stop offset="1" stop-color="#fff4d5" stop-opacity="0"/></radialGradient><radialGradient id="glow"><stop stop-color="#fffad6" stop-opacity=".95"/><stop offset=".18" stop-color="#ffdf8b" stop-opacity=".7"/><stop offset=".5" stop-color="#ff9abc" stop-opacity=".25"/><stop offset="1" stop-color="#ff9abc" stop-opacity="0"/></radialGradient><radialGradient id="featherGlow"><stop stop-color="#fffce6" stop-opacity=".65"/><stop offset=".35" stop-color="#ffe7ea" stop-opacity=".5"/><stop offset=".64" stop-color="#f799bc" stop-opacity=".22"/><stop offset="1" stop-color="#f799bc" stop-opacity="0"/></radialGradient><radialGradient id="star"><stop stop-color="#fffef0"/><stop offset=".45" stop-color="#fff5bd"/><stop offset="1" stop-color="#e9ae4b" stop-opacity=".2"/></radialGradient><linearGradient id="petal" x2="1" y2="1"><stop stop-color="#fff1e5"/><stop offset=".4" stop-color="#e56c77"/><stop offset="1" stop-color="#b92746"/></linearGradient></defs>${body}</svg>`;}
function draw(id,t,front){
 let b='',p=fract(t),q=sin(t),strong=['running','waving'].includes(id),drag=id.startsWith('drag'),sleep=id==='sleeping';
 // Each state has its own trajectory. The face's central region stays clear.
 if(id==='idle'){
   for(let j=0;j<(front?2:4);j++){let u=fract(p+j*.237),side=j%2?1:-1,x=224+side*(160+sin(u)*12),y=530-u*175;b+=fthr(x,y,29+j%2*5,side*(15+sin(u)*20),Math.sin(Math.PI*u)*.68);}
   if(front)for(let j=0;j<4;j++){let u=fract(p+j*.23);b+=star(j%2?393:51,380+u*135,3.5,Math.sin(Math.PI*u)*.55);}
 }else if(id==='running'){
   if(front)b+=sealingFlash(p);
   else b+=backRadiance(p);
   b+=checkmateAmbient(p,front);
 }else if(id==='review'){
   for(let j=0;j<(front?2:5);j++){let u=fract(p+j*.19),side=j%2?1:-1;b+=fthr(218+side*(115+u*65),451-u*67,30+u*8,side*(35+u*55),Math.sin(Math.PI*u)*.85);}
   if(front)for(let j=0;j<8;j++){let a=j*TAU/8+p*TAU;b+=star(218+cos(a/TAU)*74,439+sin(a/TAU)*47,3.5,.25+.5*Math.pow(sin(p+j*.07),2));}
 }else if(id==='waiting'){
   for(let j=0;j<(front?2:5);j++){let u=fract(p+j*.181);b+=fthr(345+sin(u+j*.1)*30-u*55,318+u*140,25+j%2*8,-35+u*90,Math.sin(Math.PI*u)*.85);}
   if(!front)b+=silk(74,457+sin(p)*7,68,-28+sin(p)*8,.65);
   if(front)for(let j=0;j<6;j++){let u=fract(p+j*.16);b+=star(344-u*110,350+u*102,2+sin(u)*2,Math.sin(Math.PI*u)*.8);}
 }else if(id==='failed'){
   if(!front)b+=silk(79+sin(p)*8,499+sin(p)*10,97,15+sin(p)*22,.75);
   for(let j=0;j<(front?3:5);j++){let u=fract(p+j*.173);b+=fthr(55+j*75+sin(u)*13,370+u*182,27+j%2*10,-60+u*150,Math.sin(Math.PI*u)*.85);}
   if(front)for(let j=0;j<5;j++)b+=star(42+j*87,537+sin(p+j*.2)*11,3,.2+.4*Math.pow(sin(p+j*.2),2));
 }else if(id==='waving'){
   const gesture=Math.exp(-Math.pow((fract(p*2)-.43)/.22,2));
   if(front)b+=arc(224+sin(p)*9,482+cos(p)*7,276+gesture*67,-12+gesture*23,.5+gesture*.42);
   if(!front){b+=fan(224,416+sin(p)*4,350+gesture*58,.25+gesture*.6,sin(p)*3);b+=arc(224,434+cos(p)*7,390,-9+sin(p)*7,.35+gesture*.5);}
   for(let j=0;j<(front?5:9);j++){let u=fract(p+j*.113),side=j%2?1:-1,x=224+side*(110+u*80),y=532-u*260;b+=fthr(x+sin(u)*14,y,35+j%3*7,side*(25+u*90),Math.sin(Math.PI*u)*.92);}
   if(front)for(let j=0;j<9;j++){let u=fract(p+j*.109);b+=petal(25+j*49+sin(u)*13,300+u*280,4+j%3,u*270,Math.sin(Math.PI*u)*.9);b+=star(35+j*46,390+sin(p+j*.11)*100,4+2*Math.pow(sin(p+j*.1),2),.7);}
 }else if(id==='jumping'){
   for(let j=0;j<(front?1:4);j++){let u=fract(p+j*.223);b+=fthr(62+j*99+sin(u)*15,560-u*205,24+j%2*6,30+u*130,Math.sin(Math.PI*u)*.72);}
   if(front){let land=Math.pow(Math.max(0,cos(p)),10);for(let j=0;j<4;j++)b+=star(150+j*45,570+sin(p+j*.2)*6,3.5,land*.7);}
 }else if(sleep){
   for(let j=0;j<(front?2:5);j++){let u=fract(p+j*.391),x=front?(j?368:70):50+j*79;b+=fthr(x+sin(u)*9,316+u*112,23+j%2*6,-40+sin(u)*24,Math.sin(Math.PI*u)*.68);}
   if(front)for(let j=0;j<5;j++)b+=star(51+j*82,343+sin(p+j*.17)*11,2.6,.2+.3*Math.pow(sin(p+j*.17),2));
 }else if(drag){
   let right=id==='drag-right',sx=right?66:382,sign=right?-1:1;
   if(!front)b+=arc(sx,442+sin(p)*7,112,sign*(20+sin(p)*10),.64);
   for(let j=0;j<(front?1:4);j++){let u=fract(p+j*.227);b+=fthr(sx+sign*u*35,383+j*33+sin(u)*15,23+j%2*7,sign*(15+u*60),Math.sin(Math.PI*u)*.75);}
   if(front)for(let j=0;j<3;j++)b+=star(sx+sign*j*12,418+j*43+sin(p+j*.3)*8,3,.2+.4*Math.pow(sin(p+j*.2),2));
 }
 if(front&&!sleep&&!drag&&id!=='idle'&&id!=='running'){for(let j=0;j<(strong?15:7);j++){let u=fract(p+j*.137),side=j%2?1:-1,x=224+side*(156+sin(u+j*.1)*27),y=350+u*215;b+=star(x,y,strong?5+j%3:3.4+j%2,Math.sin(Math.PI*u)*.8);}}
 return svg(b);
}


function backRadiance(p){
 const phase=fract(p*2),u=(phase-.27)/.5,flare=u>=0&&u<=1?Math.pow(Math.sin(Math.PI*u),.85):0;
 const opening=1-Math.pow(1-Math.max(0,Math.min(1,u*2)),3),d=400+flare*12,x=224,y=350;
 let b=glow(x,y,198,.07+flare*.17);
 b+=`<g transform="translate(${x} ${y}) rotate(${n(sin(p)*2.5)})">`;
 if(flare>.01)b+=`<image xlink:href="${magicSeal}" x="${-d/2}" y="${-d/2}" width="${d}" height="${d}" opacity="${n(flare*.35)}" filter="url(#softRay)"/>`;
 b+=`<image xlink:href="${magicSeal}" x="${-d/2}" y="${-d/2}" width="${d}" height="${d}" opacity="${n(.48+flare*.49)}"/></g>`;
 // Retain the approved short outward feather release around the seal.
 if(flare>0)for(let j=0;j<6;j++){const side=j%2?1:-1,distance=95+opening*(57+j%3*18);b+=fthr(218+side*distance,420-(j%3)*55-opening*25,28+j%2*5,side*(-25+j%3*22),flare*.8);}
 return b;
}

function checkmateAmbient(p,front){
 let b='';
 // Separate drifting paths, no circular ribbon/orbit; most particles remain behind Retto.
 for(let j=0;j<(front?1:5);j++){
  const u=fract(p+j*.193+(front?.37:0)),side=j%2?1:-1;
  const x=front?382+sin(u)*11:224+side*(170+sin(u+j*.13)*12);
  const y=front?534-u*172:508-u*292;
  const a=Math.pow(Math.sin(Math.PI*u),1.25)*(front?.46:.65);
  b+=fthr(x,y,front?19:22+j%2*3,side*(-24+sin(u)*24),a);
 }
 for(let j=0;j<(front?4:10);j++){
  const u=fract(p+j*.097+(front?.31:0)),side=j%2?1:-1;
  const x=224+side*(163+sin(u+j*.08)*21),y=539-u*316;
  const a=Math.sin(Math.PI*u)*(.22+.7*Math.pow(Math.max(0,sin(u*3+j*.17)),5));
  b+=star(x,y,2.2+j%3*1.05,a*(front?.8:1));
  if(!front&&j%3===0)b+=glow(x,y,9,a*.28);
 }
 return b;
}

function sealingFlash(p){
 const s=previous.states.find(s=>s.id==='running'),phase=fract(p*2);let q=phase*s.cycle,i=0;
 for(i=0;i<s.times.length-1;i++){if(q<s.times[i])break;q-=s.times[i];}
 const [x,y]=s.anchors[i],u=(phase-.33)/.29;if(u<0||u>1)return '';
 const flash=Math.exp(-Math.pow((u-.24)/.15,2)),spread=1-Math.pow(1-u,3),fade=Math.pow(1-u,1.5);
 let b=glow(x,y,34+spread*94,flash*.95)+star(x,y,12+flash*27,flash);
 // Wide tapered manga light wedges. Horizontal/downward rays keep the eyes clear.
 for(let j=0;j<9;j++){
  const a=(12+j*21)*Math.PI/180,dx=Math.cos(a),dy=Math.sin(a),reach=24+spread*(55+j%3*22),w=(2.6+flash*3.8)*fade,px=-dy,py=dx;
  b+=`<path d="M${n(x+dx*12+px*w)} ${n(y+dy*12+py*w)} Q${n(x+dx*reach*.65+px*w)} ${n(y+dy*reach*.65+py*w)} ${n(x+dx*reach)} ${n(y+dy*reach)} Q${n(x+dx*reach*.65-px*w)} ${n(y+dy*reach*.65-py*w)} ${n(x+dx*12-px*w)} ${n(y+dy*12-py*w)}Z" fill="url(#star)" opacity="${n(fade*.88)}"/>`;
  b+=star(x+dx*reach,y+dy*reach,3+fade*3,fade);
 }
 return b;
}

async function main(){
 const data=async f=>'data:image/png;base64,'+(await sharp(path.join(base,f)).rotate(f.startsWith('feather')?-45:0,{background:'#00000000'}).trim({background:'#00000000',threshold:5}).resize({width:256,height:256,fit:'inside'}).png().toBuffer()).toString('base64');
 magicSeal='data:image/png;base64,'+(await sharp(path.join(root,'magic-seal-source.png')).trim({background:'#00000000',threshold:5}).resize({width:512,height:512,fit:'inside'}).png().toBuffer()).toString('base64');
 feather=await data('feather-source.png');ribbon=await data('ribbon-source.png');ribbonArc=await data('ribbon-arc-source.png');wingFan=await data('wing-fan-source.png');
 const manifest={...previous,version:40,states:[]};
 for(const s of states){
  const src=lock.states.find(x=>x.id===s.id),old=previous.states.find(x=>x.id===s.id);
  if(!targets.has(s.id)){manifest.states.push({...old,characters:old.characters.map(relative),effects:old.effects.map(e=>({back:relative(e.back),front:relative(e.front)})),exportBase:relative(old.exportBase||'exports')});continue;}
  const period=s.cycle*2,count=Math.round(period*20),dir=path.join(root,'effects',s.id);fs.mkdirSync(dir,{recursive:true});
  for(let i=0;i<count;i++){
   for(const layer of ['back','front'])await sharp(Buffer.from(draw(s.id,i/count,layer==='front'))).png().toFile(path.join(dir,`${layer}-${String(i).padStart(3,'0')}.png`));
  }
  manifest.states.push({...src,ready:true,anchors:old.anchors,exportBase:'exports',name:names[s.id],characters:src.files.map((_,i)=>`../effects-v36/characters/${s.id}/${String(i).padStart(2,'0')}.png`),effectCycle:period,effectInterval:.05,effects:Array.from({length:count},(_,i)=>({back:`effects/${s.id}/back-${String(i).padStart(3,'0')}.png`,front:`effects/${s.id}/front-${String(i).padStart(3,'0')}.png`}))});
  console.log(s.id,count,'effect samples per layer');
 }
 fs.mkdirSync(path.join(root,'glow'),{recursive:true});
 for(let i=0;i<40;i++){let t=i/40,a=.35+.65*Math.pow(Math.max(0,sin(t)),3),b=glow(80,80,38,a)+star(80,80,9+a*12,a)+star(80,80,6+a*8,a);await sharp(Buffer.from(svg(b).replace('width="448" height="640" viewBox="0 0 448 640"','width="160" height="160" viewBox="0 0 160 160"'))).png().toFile(path.join(root,'glow',`${String(i).padStart(2,'0')}.png`));}
 fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(manifest,null,2));
}
main().catch(e=>{console.error(e);process.exitCode=1;});
