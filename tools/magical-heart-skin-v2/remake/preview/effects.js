(function(root){
'use strict';
const cycles={idle:3.2,running:2.4,review:3.2,waiting:3.2,failed:3.2,waving:2.4,jumping:2.4,sleeping:6.4,'drag-right':1.6,'drag-left':1.6};
const descriptions={idle:'작은 하트의 느린 숨빛',running:'앞발로 모이는 실크와 충전 빛',review:'승인한 실크 흐름 · 펜던트 섬광',waiting:'펜던트의 두 번 반짝임 · 오른쪽 호출',failed:'아래로 흩어졌다 다시 모이는 빛',waving:'위로 퍼지는 하트와 실크 축하',jumping:'상승 실크 · 발 아래 착지 빛',sleeping:'진주 달 · 느린 꿈빛','drag-right':'왼쪽 뒤로 흐르는 실크','drag-left':'오른쪽 뒤로 흐르는 실크'};
let textures={};const tau=Math.PI*2,fade=p=>Math.sin(Math.PI*p)**2;
function setTextures(t){textures=t;}
function local(c,x,y,a,fn){c.save();c.translate(x,y);c.globalAlpha*=Math.max(0,Math.min(1,a));fn();c.restore();}
function glint(c,x,y,r,a){local(c,x,y,a,()=>{const g=c.createRadialGradient(0,0,0,0,0,r*2);g.addColorStop(0,'#fffbea');g.addColorStop(.18,'#ffe0ed');g.addColorStop(1,'#ffaad000');c.fillStyle=g;c.fillRect(-r*2,-r*2,r*4,r*4);c.strokeStyle='#fff7e7';c.lineWidth=.7;c.beginPath();c.moveTo(-r,0);c.lineTo(r,0);c.moveTo(0,-r*1.4);c.lineTo(0,r*1.4);c.stroke();});}
function motif(c,key,x,y,size,a,angle=0){const im=textures[key];if(!im)return;local(c,x,y,a,()=>{c.rotate(angle);c.drawImage(im,-size/2,-size/2,size,size);});}
function scene(c,side,x,y,angle,a){if(!textures.scene)return;local(c,x,y,a,()=>{c.translate(112,230);c.rotate(angle);c.translate(-112,-230);c.save();if(side){c.beginPath();c.rect(side==='left'?0:169,0,side==='left'?89:55,320);c.clip();}c.drawImage(textures.scene,0,0,224,320);c.restore();});}
function draw(c,state,time,front,options={}){
if(!(state in cycles))throw Error('Unknown effect target '+state);
let p=(Math.max(0,time)/cycles[state])%1;if(p<1e-9||p>1-1e-9)p=0;
const wave=Math.sin(tau*p),pulse=fade(p),j=options.jewel||(state==='review'?[95,206]:state==='waiting'?[102,200]:[112,204]);
c.save();c.beginPath();c.rect(6,6,212,308);c.clip();
if(front&&!state.startsWith('drag')&&state!=='sleeping'){c.beginPath();c.rect(0,0,224,320);c.rect(42,65,145,Math.min(184,j[1]-6)-65);c.clip('evenodd');}
if(!front){
 if(state==='review')scene(c,null,-6+1.6*wave,6+1.3*Math.cos(tau*p),.012*wave,.85+.15*pulse);
 else if(state==='idle')scene(c,'right',-3,3*wave,.015*wave,.35+.2*pulse);
 else if(state==='running'){scene(c,'left',3*wave,-4*pulse,.035*wave,.6+.35*pulse);scene(c,'right',-3*wave,-8*pulse,-.03*wave,.55+.35*pulse);}
 else if(state==='waiting')scene(c,'right',4*pulse,-3*wave,.025*wave,.6+.35*fade((p*2)%1));
 else if(state==='failed')scene(c,'left',-4*pulse,12*pulse,.07*pulse,.65-.25*pulse);
 else if(state==='waving'){scene(c,'left',-3*pulse,-20*pulse,-.06*pulse,.7+.3*pulse);scene(c,'right',3*pulse,-28*pulse,.05*pulse,.7+.3*pulse);}
 else if(state==='jumping'){scene(c,'left',0,-27*pulse,-.025*wave,.7+.25*pulse);scene(c,'right',0,-35*pulse,.025*wave,.6+.25*pulse);}
 else if(state==='sleeping')motif(c,'moon',172,177,48,.8+.12*pulse,.015*wave);
 else{const d=state==='drag-right'?1:-1;c.save();if(d<0){c.translate(224,0);c.scale(-1,1);}scene(c,'left',-4*pulse,4*wave,.045*wave,.85);c.restore();}
}else{
 if(state==='review'||state==='waiting'){const k=state==='review'?pulse:Math.pow(fade((p*2)%1),2);glint(c,...j,3+7*k,.6+.4*k);motif(c,'star',j[0]+7,j[1]-7,12,.7*k);}
 if(state==='running'){const s=options.spell||[112,250];for(let i=0;i<4;i++){const q=(p+i/4)%1,a=tau*(q+i/4),r=45*(1-q)+8;glint(c,s[0]+Math.cos(a)*r,s[1]+Math.sin(a)*r*.35,1.5+q*2,.75*fade(q));}glint(c,...s,4+4*pulse,.9);}
 else if(state==='jumping'){local(c,112,299,.6*pulse,()=>{c.beginPath();c.ellipse(0,0,16+58*p,3+8*p,0,0,tau);c.strokeStyle='#ffd6ec';c.shadowColor='#ffc1df';c.shadowBlur=7;c.lineWidth=1.3;c.stroke();});}
 else{const n=state==='idle'||state==='sleeping'?3:4;for(let i=0;i<n;i++){const q=(p+i/n)%1,side=i%2?1:-1;let x=112+side*88,y=245-57*q;
 if(state==='waiting'){x=184+20*q;y=225-26*q;}
 if(state==='waving')y=197-117*q;
 if(state==='failed')y=220+65*q;
 if(state==='sleeping'){x=35+i*56;y=207+8*Math.sin(tau*q);}
 if(state.startsWith('drag')){x=112-(state==='drag-right'?1:-1)*(49+51*q);y=265+7*Math.sin(tau*q);}
 glint(c,x,y,1.5+2*fade(q),.72*fade(q));}}
}
c.restore();}
const api={draw,cycles,descriptions,setTextures};root.MagicalHeartPreviewEffects=api;if(typeof module!=='undefined')module.exports=api;
})(typeof window!=='undefined'?window:globalThis);
