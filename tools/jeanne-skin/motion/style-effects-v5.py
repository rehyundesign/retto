from pathlib import Path
r=Path(__file__).parent;p=r/'latest-effects.js';s=p.read_text()
a=s.index(' function feather(');b=s.index(' function heart(',a)
s=s[:a]+''' function feather(x,y,angle,o){return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)})" opacity="${n(o)}"><path d="M0 10C-3 5 -8 1 -7 -4L-4 -3C-6 -7 -4 -11 -1 -14C3 -12 6 -7 5 -3L3 -2C5 2 3 6 0 10Z" fill="#fffdf6" stroke="#dccda5" stroke-width=".55"/><path d="M0 9Q-2 -1 -1 -11M-1 -4L-5 -7M-1 0L-5 -3M-1 3L2 0" fill="none" stroke="#c4a36c" stroke-width=".55"/></g>`}
''' +s[b:]
a=s.index(' function ribbon(');b=s.index(' function render(',a)
s=s[:a]+''' function ribbon(d,o){return `<g opacity="${n(o)}"><path d="${d}" fill="none" stroke="#92152c" stroke-width="7" stroke-linecap="butt"/><path d="${d}" fill="none" stroke="#dc2343" stroke-width="5.5" stroke-linecap="butt"/><path d="${d}" fill="none" stroke="#f65a64" stroke-width=".75" opacity=".75"/></g>`}
''' +s[b:]
s=s.replace(' const yy=lower-12+24*w(time/3);f+=`<path d="M${n(x-55)} ${n(yy)}h30" stroke="#fff4c7" stroke-width=".6" opacity=".55"/>`;','')
needle=' return {back:svg(b),front:svg(f)};'
s=s.replace(needle,''' // Checkmate release follows the Rosario gesture, peaking on drawing 8.
 if(state==='review'&&attachment?.visible!==false){
 const hit=Math.exp(-(((frame-8)/1.6)**2)),spark=hit*(.84+.16*Math.sin(time*25)**2);
 f+=`<defs><radialGradient id="checkmateFlash"><stop stop-color="#ffffff"/><stop offset=".2" stop-color="#fffbe7" stop-opacity=".98"/><stop offset=".48" stop-color="#ffdd88" stop-opacity=".65"/><stop offset="1" stop-color="#ffd069" stop-opacity="0"/></radialGradient></defs>`;
 f+=`<circle cx="${n(x)}" cy="${n(y)}" r="${n(20+hit*23)}" fill="url(#checkmateFlash)" opacity="${n(spark)}"/>`;
 for(let i=0;i<12;i++){let q=i*T/12+.08*Math.sin(a),dx=Math.cos(q),dy=Math.sin(q),len=dy<-.5?23:39;
 f+=`<path d="M${n(x+dx*7)} ${n(y+dy*7)}L${n(x+dx*(len*hit+9))} ${n(y+dy*(len*hit+9))}" stroke="${i%2?'#ffd781':'#fffdf1'}" stroke-width="${i%3===0?2.4:1}" opacity="${n(spark*.92)}"/>`;}
 f+=star(x,y,7+hit*17,spark,'#fffef2');
 const wave=Math.max(0,Math.min(1,(frame-7)/5));
 if(frame>=7&&frame<=12)f+=`<ellipse cx="${n(x)}" cy="${n(y)}" rx="${n(12+wave*36)}" ry="${n(7+wave*24)}" fill="none" stroke="#ffe0a0" stroke-width="1.7" opacity="${n((1-wave)*.8)}"/>`;
 }
''' +needle)
p.write_text(s)
for name in ['state-effects-v4.html','state-motions-v1.html','latest-motion.html']:
 p=r/name;p.write_text(p.read_text().replace('latest-effects.js?v=4','latest-effects.js?v=5'))
(r/'state-effects-v5.html').write_text((r/'state-effects-v4.html').read_text())
