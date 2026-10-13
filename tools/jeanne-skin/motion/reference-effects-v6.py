from pathlib import Path
r=Path(__file__).parent;p=r/'latest-effects.js';s=p.read_text()
idx=s.index(' function render(')
s=s[:idx]+''' function petal(x,y,angle,size,o){return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)}) scale(${n(size)})" opacity="${n(o)}"><path d="M-5 -3C-2 -8 5 -7 6 -1C5 4 0 7 -4 4C-2 1 -4 0 -5 -3Z" fill="#d5284b" stroke="#9d1c3b" stroke-width=".6"/><path d="M-3 -3Q2 -5 4 -1Q1 -2 -1 2" fill="none" stroke="#ff8f9e" stroke-width="1"/><path d="M-2 4Q1 2 4 0" fill="none" stroke="#9f203f" stroke-width=".6"/></g>`}
''' +s[idx:]
idx=s.index(' // Checkmate release')
s=s[:idx]+'''
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
''' +s[idx:]
s=s.replace('stop-color="#ffdd88"','stop-color="#ffd0e2"').replace('stop-color="#ffd069"','stop-color="#f3bd72"')
p.write_text(s)
for name in ['state-effects-v5.html','state-motions-v1.html','latest-motion.html']:
 p=r/name;p.write_text(p.read_text().replace('latest-effects.js?v=5','latest-effects.js?v=6'))
(r/'state-effects-v6.html').write_text((r/'state-effects-v5.html').read_text())
