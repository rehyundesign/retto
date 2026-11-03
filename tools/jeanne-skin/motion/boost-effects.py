from pathlib import Path
p=Path(__file__).with_name('latest-effects.js');s=p.read_text().replace("'#edc477'","'#f3bc4f'").replace("'#dc4464'","'#ef315d'").replace('stroke-width=".8"','stroke-width="1.8"').replace('stroke-width=".35"','stroke-width=".8"').replace('stroke-width="1.1"','stroke-width="2"').replace('stroke-width="2.2"','stroke-width="4"')
s=s.replace('return {back:svg(b),front:svg(f)};', '''
 const calm=state==='sleeping'?.48:state==='idle'?.72:1,bright=.72+.23*Math.sin(a)**2;
 if(state!=='sleeping'){
 const cx=state==='drag-left'?189:35,cy=state==='jumping'?202:226;
 f+=seal(cx,cy,state==='idle'?16:21,Math.sin(a)*16+time*12,bright*calm,state==='failed');
 f+=`<circle cx="${n(cx)}" cy="${n(cy)}" r="4.5" fill="${pink}" stroke="#fff1c2" stroke-width="1.2" opacity="${n(bright)}"/>`;
 f+=ribbon(state==='drag-left'?`M207 278C216 224 208 181 191 ${n(166+Math.sin(a)*8)}`:`M17 278C8 224 16 181 33 ${n(166+Math.sin(a)*8)}`,.68*calm);
 for(let i=0;i<7;i++){let q=w(time/4+i/7),side=i%2?1:-1,xx=112+side*(83+Math.sin(q*T)*7),yy=170+q*114;
 f+=star(xx,yy,2.4+1.8*Math.sin(q*Math.PI),(.4+.55*Math.sin(q*Math.PI))*calm,i%3===0?pink:gold);}
 if(['waving','running','jumping'].includes(state)){
 const sy=state==='waving'?65:78;f+=heart(112,sy,.85);
 for(let sign of [-1,1])for(let i=0;i<3;i++)f+=feather(112+sign*(12+i*9),sy-4+i*4,sign*(45+i*15),.85);
 f+=star(112,sy-17,4,.65+.3*pulse);}
 if(state==='waiting')for(let i=0;i<2;i++){let q=w(time/3+i*.5);f+=`<path d="M173 ${n(198-q*12)}Q${n(199+q*10)} 214 180 ${n(235+q*12)}" fill="none" stroke="${gold}" stroke-width="1.8" opacity="${n(.8*(1-q))}"/>`;}
 }else{f+=feather(36,244+Math.sin(a)*7,35,.65);f+=star(190,202+Math.sin(a)*6,4,.65);f+=star(170,226+Math.sin(a+1)*5,3,.55);}
 if(attachment?.visible!==false){f+=star(x+4,y-4,4+2*pulse,.65+.3*pulse,'#fff9e2');for(let i=0;i<3;i++){let q=a+i*T/3;f+=star(x+Math.cos(q)*17,y+Math.sin(q)*12,2.1,.75*soft,i%2?pink:gold);}}
 return {back:svg(b),front:svg(f)};''')
p.write_text(s)
for name in ['state-effects-v2.html','state-motions-v1.html','latest-motion.html']:
 p=Path(__file__).with_name(name);p.write_text(p.read_text().replace('src="latest-effects.js"','src="latest-effects.js?v=3"'))
Path(__file__).with_name('state-effects-v3.html').write_text(Path(__file__).with_name('state-effects-v2.html').read_text())
