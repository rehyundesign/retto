from pathlib import Path
r=Path(__file__).parent;p=r/'latest-effects.js';s=p.read_text();start=s.index(' const calm=');end=s.index(' if(attachment?.visible!==false){f+=star',start)
s=s[:start]+'''
 const bright=.75+.2*Math.sin(a)**2;
 // Distinct feather trajectories; no shared side arc or floating crown.
 const count=state==='sleeping'?2:state==='idle'?3:state==='waving'?8:5;
 for(let i=0;i<count;i++){
 let q=w(time/(state==='sleeping'?8:4)+i/count),xx,yy,angle;
 if(state==='running'){xx=30+Math.sin(q*T)*10;yy=280-q*81;angle=25+q*70;}
 else if(state==='review'){xx=28+q*27;yy=257+Math.sin(q*Math.PI)*25;angle=70-q*45;}
 else if(state==='waiting'){xx=190+Math.sin(q*T)*9;yy=248-q*53;angle=-30+Math.sin(q*T)*25;}
 else if(state==='failed'){xx=27+q*17;yy=215+q*70;angle=25+q*95;}
 else if(state==='waving'){xx=i%2?189+Math.sin(q*T)*9:29+Math.sin(q*T)*9;yy=286-q*105;angle=(i%2?-1:1)*(20+q*90);}
 else if(state==='jumping'){xx=i%2?189:30;yy=293-q*105;angle=15+q*85;}
 else if(state.startsWith('drag')){xx=state==='drag-left'?190-q*40:30+q*40;yy=272+Math.sin(q*T)*11;angle=state==='drag-left'?-65:65;}
 else{xx=i%2?188:29;yy=245+q*45;angle=25+Math.sin(q*T)*30;}
 f+=feather(xx,yy,angle,(.25+.65*Math.sin(q*Math.PI))*(state==='sleeping'?.55:1));
 if(state!=='sleeping')f+=star(xx+8,yy-10,2.4,Math.sin(q*Math.PI)*.8);
 }
 if(state==='running')f+=seal(35,231,21,time*25,bright);
 if(state==='review')f+=seal(36,264,16,Math.sin(a)*15,.75);
 if(state==='failed')f+=seal(34,245,17,time*8,.6,true);
 if(state==='waving'){
 f+=ribbon(`M25 283C43 ${n(247+Math.sin(a)*9)} 169 301 198 257`,.88);
 }
''' +s[end:]
s=s.replace('stroke="${red}" stroke-width="4"','stroke="#bf1638" stroke-width="6"').replace('stroke="${gold}" stroke-width=".5"','stroke="#ffd87b" stroke-width="1"')
s=s.replace('M33 291C15 261 25 222 49','M33 291C22 274 30 253 49')
p.write_text(s)
for name in ['state-effects-v3.html','state-effects-v2.html','state-motions-v1.html','latest-motion.html']:
 p=r/name;p.write_text(p.read_text().replace('latest-effects.js?v=3','latest-effects.js?v=4'))
(r/'state-effects-v4.html').write_text((r/'state-effects-v3.html').read_text())
