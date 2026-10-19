(function(root){
'use strict';let textures={};const cycle=3.2;
function setTextures(t){textures=t;}
const smooth=v=>{v=Math.max(0,Math.min(1,v));return v*v*v*(v*(v*6-15)+10);};
function gesture(p){return smooth((p-.16)/.27)*(1-smooth((p-.52)/.42));}
function glow(c,x,y,r,a){c.save();c.globalAlpha*=Math.max(0,a);const g=c.createRadialGradient(x,y,0,x,y,r);g.addColorStop(0,'#fffbea');g.addColorStop(.16,'#ffe7ef');g.addColorStop(.48,'#ffc5e28c');g.addColorStop(1,'#ffc5e200');c.fillStyle=g;c.fillRect(x-r,y-r,r*2,r*2);c.restore();}
function point(u){const a=[95,206],b=[10,207],d=[12,259],e=[70,299],v=1-u;return [v*v*v*a[0]+3*v*v*u*b[0]+3*v*u*u*d[0]+u*u*u*e[0],v*v*v*a[1]+3*v*v*u*b[1]+3*v*u*u*d[1]+u*u*u*e[1]];}
function draw(c,state,time,front,options={}){
const t=Math.max(0,time),p=(t%cycle)/cycle,j=options.jewel||[95,206],power=gesture(p);
c.save();c.beginPath();c.rect(6,6,212,308);c.clip();
if(!front){
 // Artwork stays registered. Only light travels through its silk silhouette.
 if(textures.scene){c.save();c.globalAlpha*=.66+.12*power;c.drawImage(textures.scene,-6,6,224,320);c.restore();}
 for(let k=0;k<3;k++){const q=(p-.18-k*.065)/.72;if(q>0&&q<1){const pos=point(smooth(q));glow(c,pos[0],pos[1],5+3*Math.sin(Math.PI*q),.52*Math.sin(Math.PI*q)**2);}}
 // Delayed right-side response, separate from the pendant contact.
 const response=smooth((p-.37)/.19)*(1-smooth((p-.66)/.28));glow(c,202,245,9,.3*response);
}else{
 c.beginPath();c.rect(0,0,224,320);c.rect(42,65,145,119);c.clip('evenodd');
 glow(c,j[0],j[1],8+5*power,.85*power);
 c.save();c.globalAlpha*=.7*power;c.strokeStyle='#fff8e9';c.lineWidth=.65;c.lineCap='round';c.beginPath();c.moveTo(j[0]-7,j[1]);c.lineTo(j[0]+7,j[1]);c.moveTo(j[0],j[1]-10);c.lineTo(j[0],j[1]+10);c.stroke();c.restore();
 for(const [x,y,delay] of [[19,231,.08],[29,269,.2],[195,237,.24]]){const sparkle=gesture((p-delay+1)%1);glow(c,x,y,3,.36*sparkle);}
}
c.restore();}
const api={draw,setTextures,cycles:{review:cycle}};root.MagicalHeartPreviewEffects=api;if(typeof module!=='undefined')module.exports=api;
})(typeof window!=='undefined'?window:globalThis);
