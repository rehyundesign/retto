(function(root){
const approved=typeof module!=='undefined'?require('./effects-scope-v9-locked.js'):root.JeanneLatestEffects;
const pendant=typeof module!=='undefined'?require('./checkmate-pendant-v9.js'):root.JeanneCheckmatePendant;
const art=typeof module!=='undefined'?require('./effect-art-v10.js'):root.JeanneArtV10;
const T=Math.PI*2,n=v=>Number(v).toFixed(2),w=v=>((v%1)+1)%1,inner=s=>s.replace(/^<svg[^>]*>/,'').replace(/<\/svg>$/,'');
const svg=s=>`<svg xmlns="http://www.w3.org/2000/svg" width="224" height="320" viewBox="0 0 224 320">${s}</svg>`;
function image(name,x,y,width,angle,o){const h=name==='wing'?width*.57:width,r=angle*Math.PI/180,ex=(Math.abs(Math.cos(r))*width+Math.abs(Math.sin(r))*h)/2,ey=(Math.abs(Math.sin(r))*width+Math.abs(Math.cos(r))*h)/2;x=Math.max(8+ex,Math.min(216-ex,x));y=Math.max(8+ey,Math.min(312-ey,y));return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)})" opacity="${n(o)}"><image href="${art[name]}" x="${n(-width/2)}" y="${n(-h/2)}" width="${n(width)}" height="${n(h)}"/></g>`}
function feather(x,y,angle,size,o){return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)}) scale(${n(size)})" opacity="${n(o)}"><path d="M0 10C-10 2-12-6-4-15L0-18C8-12 11-4 4 5Z" fill="#fffdf4" stroke="#f0cea7" stroke-width=".55"/><path d="M0 9V-12M0 1L-6-6M0-3L5-9" stroke="#d7b885" fill="none" stroke-width=".6"/></g>`}
function render(state,time,frame,attachment){
if(state==='sleeping'||state==='waving')return approved.render(state,time,frame,attachment);
const a=time*T/8,u=frame/16,g=Math.sin(Math.PI*u)**2,x=attachment?.x??98,y=attachment?.y??220;
let b='',f='';
if(state==='review'){
 const hit=Math.exp(-(((frame-8)/2.6)**2));b+=image('wing',112,y-31,145+hit*63,0,.18+hit*.8);
 f+=image('wing',112,y-31,145+hit*63,0,hit*.44);f+=inner(pendant.render(state,time,frame,attachment).front);
}else{
 const o=state==='failed'?.5:1;
 f+=`<defs><radialGradient id="rosario10"><stop stop-color="#fffef1" stop-opacity=".98"/><stop offset=".32" stop-color="#ffc3e4" stop-opacity=".72"/><stop offset="1" stop-color="#ffd7a2" stop-opacity="0"/></radialGradient></defs>`;
 if(attachment?.visible!==false)f+=`<circle cx="${n(x)}" cy="${n(y)}" r="${n(17+g*11)}" fill="url(#rosario10)" opacity="${n(o*(.6+.3*Math.sin(a)**2))}"/>`;
 if(state==='running'){
 b+=image('wing',112,y-30,152+g*56,0,.2+g*.8);f+=image('wing',112,y-30,152+g*56,0,g*.48);f+=image('ribbon',39,255-g*21,64,-40+g*25,.75*g);
 }else if(state==='jumping'){
 b+=image('wing',112,y-28,170+g*38,Math.sin(a)*3,.35+g*.65);f+=image('wing',112,y-28,170+g*38,Math.sin(a)*3,g*.42);
 for(let i=0;i<5;i++){const q=w(time/4+i/5);f+=feather(30+i*41,290-q*63,Math.sin(q*T)*35,.65+.25*g,Math.sin(q*Math.PI)*.9);}
 }else if(state==='waiting'){
 b+=image('wing',169,147,85+g*12,Math.sin(a)*7,.5+g*.45);
 for(let i=0;i<3;i++){const q=w(time/4+i/3);f+=feather(178+q*20,195+q*44,-30+q*40,.65,Math.sin(q*Math.PI)*.9);}
 }else if(state==='idle'){
 for(let i=0;i<3;i++){const q=w(time/8+i/3);f+=feather(i%2?184:30,227+q*62,15+Math.sin(q*T)*30,.65,Math.sin(q*Math.PI)*.8);}
 }else if(state==='failed'){
 for(let i=0;i<3;i++){const q=w(time/8+i/3);f+=feather(32+Math.sin(q*T)*8,211+q*76,10+q*85,.7,Math.sin(q*Math.PI)*.7);}
 b+=image('wing',112,249,115,0,.15+.18*g);
 }else if(state.startsWith('drag')){
 const left=state==='drag-left';b+=image('ribbon',left?178:46,258+Math.sin(a)*9,91,left?-65:65,.88);
 for(let i=0;i<3;i++){const q=w(time/4+i/3);f+=feather(left?186-q*27:38+q*27,268+Math.sin(q*T)*10,left?-55:55,.7,Math.sin(q*Math.PI)*.95);}
 }
}
// Quiet light remnants continue even when the main action pose is held.
for(let i=0;i<3;i++){const q=w(time/4+i/3),xx=31+i*79,yy=285-q*23;const glint=`<path d="M${n(xx-2)} ${n(yy)}h4M${n(xx)} ${n(yy-2)}v4" stroke="#fff1c2" stroke-width=".7" opacity="${n(Math.sin(q*Math.PI)*.55)}"/>`;b+=glint;f+=glint;}
return {back:svg(b),front:svg(f)};
}
root.JeanneLatestEffects={render};if(typeof module!=='undefined')module.exports=root.JeanneLatestEffects;
})(globalThis);
