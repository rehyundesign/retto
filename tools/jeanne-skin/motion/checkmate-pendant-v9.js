(function(root){
 const T=Math.PI*2,n=v=>Number(v).toFixed(2),w=v=>((v%1)+1)%1;
 const gold='#f3bc4f',red='#ef315d',pink='#ffc3df';
 const svg=s=>`<svg xmlns="http://www.w3.org/2000/svg" width="224" height="320" viewBox="0 0 224 320">${s}</svg>`;
 function star(x,y,r,o,c=gold){return `<path d="M${n(x)} ${n(y-r)}l${n(r*.22)} ${n(r*.78)} ${n(r*.78)} ${n(r*.22)}-${n(r*.78)} ${n(r*.22)}-${n(r*.22)} ${n(r*.78)}-${n(r*.22)}-${n(r*.78)}-${n(r*.78)}-${n(r*.22)} ${n(r*.78)}-${n(r*.22)}Z" fill="${c}" opacity="${n(o)}"/>`}
 function seal(x,y,r,angle,o,broken=false){return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)})" fill="none" stroke="${gold}" opacity="${n(o)}"><circle r="${n(r)}" stroke-width="1.8" ${broken?'stroke-dasharray="7 5"':''}/><circle r="${n(r*.78)}" stroke-width=".8" stroke-dasharray="2 3"/><path d="M0 -${n(r*.62)}V${n(r*.62)}M-${n(r*.4)} -${n(r*.2)}H${n(r*.4)}" stroke-width="2"/><path d="M0 -${n(r+3)}l3 3 -3 3 -3 -3Z M0 ${n(r+3)}l3 -3 -3 -3 -3 3Z" stroke-width=".6"/></g>`}
 function feather(x,y,angle,o){return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)})" opacity="${n(o)}"><path d="M0 10C-3 5 -8 1 -7 -4L-4 -3C-6 -7 -4 -11 -1 -14C3 -12 6 -7 5 -3L3 -2C5 2 3 6 0 10Z" fill="#fffdf6" stroke="#dccda5" stroke-width=".55"/><path d="M0 9Q-2 -1 -1 -11M-1 -4L-5 -7M-1 0L-5 -3M-1 3L2 0" fill="none" stroke="#c4a36c" stroke-width=".55"/></g>`}
 function heart(x,y,o){return `<path transform="translate(${n(x)} ${n(y)})" d="M0 4C-9 -2 -5 -8 0 -3C5 -8 9 -2 0 4Z" fill="${pink}" stroke="${red}" stroke-width=".8" opacity="${n(o)}"/>`}
 function ribbon(d,o){return `<g opacity="${n(o)}"><path d="${d}" fill="none" stroke="#92152c" stroke-width="7" stroke-linecap="butt"/><path d="${d}" fill="none" stroke="#dc2343" stroke-width="5.5" stroke-linecap="butt"/><path d="${d}" fill="none" stroke="#f65a64" stroke-width=".75" opacity=".75"/></g>`}
 function petal(x,y,angle,size,o){return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)}) scale(${n(size)})" opacity="${n(o)}"><path d="M-5 -3C-2 -8 5 -7 6 -1C5 4 0 7 -4 4C-2 1 -4 0 -5 -3Z" fill="#d5284b" stroke="#9d1c3b" stroke-width=".6"/><path d="M-3 -3Q2 -5 4 -1Q1 -2 -1 2" fill="none" stroke="#ff8f9e" stroke-width="1"/><path d="M-2 4Q1 2 4 0" fill="none" stroke="#9f203f" stroke-width=".6"/></g>`}
 function render(state,time,frame,attachment){
 const a=time*T/8,p=w(time/8),u=frame/16,action=Math.sin(Math.PI*u)**2;
 const x=attachment?.x??98,y=attachment?.y??220;
 let b='',f='';const soft=state==='sleeping'?.28:state==='failed'?.55:1;
 const pulse=(.5+.5*Math.sin(a*2))**2,glow=(.28+.4*pulse+.15*action)*soft;
 f+='<defs><radialGradient id="pendantLight"><stop stop-color="#fff9dc" stop-opacity=".95"/><stop offset=".32" stop-color="#ffb7dc" stop-opacity=".65"/><stop offset="1" stop-color="#ff93cd" stop-opacity="0"/></radialGradient></defs>';
 if(attachment?.visible!==false){f+=`<circle cx="${n(x)}" cy="${n(y)}" r="15" fill="url(#pendantLight)" opacity="${n(glow)}"/>`;f+=star(x+2,y-3,2+1.1*pulse,glow,'#fffdef');}
 if(attachment?.visible!==false){f+=star(x+4,y-4,4+2*pulse,.65+.3*pulse,'#fff9e2');for(let i=0;i<3;i++){let q=a+i*T/3;f+=star(x+Math.cos(q)*17,y+Math.sin(q)*12,2.1,.75*soft,i%2?pink:gold);}}

 // Rose petals from the manga covers; each gesture has its own trajectory.
 const petals={idle:4,running:10,review:9,waiting:5,failed:6,waving:14,jumping:9,'drag-left':8,'drag-right':8,sleeping:0}[state]??3;
 for(let i=0;i<petals;i++){
 const q=w(time/(state==='idle'?8:4)+i/petals),side=i%2?1:-1;
 let px,py,rot,opacity=.45+.5*Math.sin(q*Math.PI),size=.65+.28*Math.sin(q*Math.PI);
 if(state==='idle'){px=112+side*(83+Math.sin(q*T)*5);py=235+q*59;rot=q*120;}
 else if(state==='running'){px=112+Math.cos(q*T)*86;py=250+Math.sin(q*T)*40;rot=q*360;}
 else if(state==='review'){
 const release=Math.max(0,Math.min(1,(frame-7)/5));
 px=112+side*(52+release*33)+Math.sin(q*T)*4;py=258-release*36+Math.cos(q*T)*23;rot=release*120+q*180;opacity*=.3+.7*Math.sin(Math.PI*u)**2;
 }else if(state==='waiting'){px=190+Math.sin(q*T)*9;py=199+q*82;rot=25+q*180;}
 else if(state==='failed'){px=30+q*24;py=208+q*87;rot=q*160;opacity*=.7;}
 else if(state==='waving'){px=112+side*(72+Math.sin(q*Math.PI)*16);py=182+q*108;rot=q*280;size*=1.15;}
 else if(state==='jumping'){px=112+side*(81+Math.sin(q*T)*5);py=295-q*99;rot=q*220;}
 else{const left=state==='drag-left';px=left?193-q*51:31+q*51;py=264+Math.sin(q*T)*21;rot=(left?-1:1)*q*190;}
 f+=petal(px,py,rot,size,opacity);
 }
 if(state==='running'){
 for(let i=0;i<3;i++){let q=w(time/3+i/3);f+=feather(192+Math.sin(q*T)*6,278-q*75,-35+q*60,Math.sin(q*Math.PI)*.9);}
 }else if(state==='waiting'){
 for(let i=0;i<3;i++){let q=w(time/4+i/3);f+=feather(176+q*24,173+q*36,-45+q*70,.8*Math.sin(q*Math.PI));}
 }else if(state==='waving'){
 for(let i=0;i<4;i++){let q=w(time/3+i/4);f+=feather(112+(i%2?1:-1)*(72+q*12),269-q*74,(i%2?-1:1)*q*100,.9*Math.sin(q*Math.PI));}
 }
 // Checkmate release follows the Rosario gesture, peaking on drawing 8.
 if(state==='review'&&attachment?.visible!==false){
 const hit=Math.exp(-(((frame-8)/1.6)**2)),spark=hit*(.84+.16*Math.sin(time*25)**2);
 f+=`<defs><radialGradient id="checkmateFlash"><stop stop-color="#ffffff"/><stop offset=".2" stop-color="#fffbe7" stop-opacity=".98"/><stop offset=".48" stop-color="#ffd0e2" stop-opacity=".65"/><stop offset="1" stop-color="#f3bd72" stop-opacity="0"/></radialGradient></defs>`;
 f+=`<circle cx="${n(x)}" cy="${n(y)}" r="${n(20+hit*23)}" fill="url(#checkmateFlash)" opacity="${n(spark)}"/>`;
 for(let i=0;i<12;i++){let q=i*T/12+.08*Math.sin(a),dx=Math.cos(q),dy=Math.sin(q),len=dy<-.5?23:39;
 f+=`<path d="M${n(x+dx*7)} ${n(y+dy*7)}L${n(x+dx*(len*hit+9))} ${n(y+dy*(len*hit+9))}" stroke="${i%2?'#ffd781':'#fffdf1'}" stroke-width="${i%3===0?2.4:1}" opacity="${n(spark*.92)}"/>`;}
 f+=star(x,y,7+hit*17,spark,'#fffef2');
 const wave=Math.max(0,Math.min(1,(frame-7)/5));
 if(frame>=7&&frame<=12)f+=`<ellipse cx="${n(x)}" cy="${n(y)}" rx="${n(12+wave*36)}" ry="${n(7+wave*24)}" fill="none" stroke="#ffe0a0" stroke-width="1.7" opacity="${n((1-wave)*.8)}"/>`;
 }
 return {back:svg(b),front:svg(f)};
 }
 root.JeanneCheckmatePendant={render};if(typeof module!=='undefined')module.exports=root.JeanneCheckmatePendant;
})(typeof globalThis!=='undefined'?globalThis:this);
