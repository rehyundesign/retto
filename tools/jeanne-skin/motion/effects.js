(function (root) {
  'use strict';
  const TAU = Math.PI * 2;
  const wrap = x => ((x % 1) + 1) % 1;
  const n = x => Number(x).toFixed(2);
  const svg = body => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 224 320">' + body + '</svg>';
  function star(x, y, size, opacity) {
    return `<path d="M${n(x)},${n(y-size)} Q${n(x+size*.18)},${n(y-size*.18)} ${n(x+size)},${n(y)} Q${n(x+size*.18)},${n(y+size*.18)} ${n(x)},${n(y+size)} Q${n(x-size*.18)},${n(y+size*.18)} ${n(x-size)},${n(y)} Q${n(x-size*.18)},${n(y-size*.18)} ${n(x)},${n(y-size)}" fill="#ffe39b" stroke="#d99b36" stroke-width=".35" opacity="${n(opacity)}"/>`;
  }
  function seal(x, y, r, phase, opacity, broken) {
    const arcs = broken ? `<path d="M${n(x-r)},${n(y)} A${r},${r} 0 0 1 ${n(x)},${n(y-r)} M${n(x+r)},${n(y)} A${r},${r} 0 0 1 ${n(x)},${n(y+r)}"/>` : `<circle cx="${n(x)}" cy="${n(y)}" r="${n(r)}"/>`;
    return `<g fill="none" stroke="#eac56d" stroke-width="1" opacity="${n(opacity)}" transform="rotate(${n(phase*25)} ${n(x)} ${n(y)})">${arcs}<path d="M${n(x)},${n(y-r-2)} V${n(y+r+2)} M${n(x-r-2)},${n(y)} H${n(x+r+2)}"/></g>`;
  }
  function feather(x,y,angle,opacity) {
    return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)})" opacity="${n(opacity)}"><path d="M0,-7 C8,-5 6,5 0,8 C-5,4 -6,-4 0,-7Z" fill="#fff7ea" stroke="#d7c5aa" stroke-width=".35"/><path d="M0,-5 V8 M0,-1 L3,-3 M0,3 L-3,1" fill="none" stroke="#cbb795" stroke-width=".3"/></g>`;
  }
  function ribbon(phase, direction, opacity) {
    const d = direction || 1, offset = Math.sin(phase*TAU)*3;
    const x1=d===1?45:179,x2=d===1?128:96,x3=d===1?174:50;
    return `<path d="M${x1},${n(255+offset)} C${n(x1+d*24)},${n(273-offset)} ${x2},${n(266+offset)} ${x3},${n(253-offset)}" fill="none" stroke="#c62943" stroke-width="3.3" opacity="${n(opacity)}"/><path d="M${x1},${n(254.4+offset)} C${n(x1+d*24)},${n(272.4-offset)} ${x2},${n(265.4+offset)} ${x3},${n(252.4-offset)}" fill="none" stroke="#f0c679" stroke-width=".55" opacity="${n(opacity*.75)}"/>`;
  }
  function render(state,time,frame) {
    const phase=wrap(time/8),a=phase*TAU,pulse=.65+.25*Math.sin(a);
    let back='',front='',dir=state==='drag-left'?-1:1;
    if (state==='running') {
      const x=104+Math.cos(a)*14,y=175+Math.sin(a)*7;
      front+=seal(x,y,7,a,pulse,false)+star(98,178,3,pulse);
      back+=`<path d="M172,112 Q${n(145+Math.sin(a)*5)},150 102,178" fill="none" stroke="#edce80" stroke-width=".7" opacity="${n(pulse*.55)}"/>`;
    } else if(state==='review') front+=seal(58,145,8,a,pulse,false);
    else if(state==='waiting') {
      const radius=4+wrap(phase*2)*9;
      front+=seal(104,177,radius,0,1-wrap(phase*2),false);
    } else if(state==='failed') {
      const q=wrap(phase*2);
      front+=seal(52-q*5,208-q*4,6+q*3,a,(1-q)*.6,true);
    } else if(state==='waving') {
      front+=seal(61,150,7,a,pulse,false)+star(169,118,4,pulse);
    } else if(state==='jumping') {
      const landing=Math.max(0,Math.sin((frame/16)*TAU-Math.PI/2));
      back+=`<ellipse cx="100" cy="281" rx="${n(13+landing*12)}" ry="${n(3+landing*2)}" fill="none" stroke="#e8c56e" stroke-width=".8" opacity="${n(landing*.7)}"/>`;
    } else if(state==='sleeping') {
      front+=`<path d="M173,190 A7,7 0 1 0 181,200 A6,6 0 0 1 173,190Z" fill="#efd893" opacity=".55"/>`;
    } else if(state==='idle') front+=seal(72,183,4,a,pulse*.7,false);
    if(state!=='sleeping') back+=ribbon(phase,dir,state==='idle'?.4:.65);
    for(let i=0;i<2;i++) {
      const q=wrap(phase+i*.47),x=state.startsWith('drag')?(dir===1?40-q*13:180+q*13):36+i*142+Math.sin(q*TAU)*4;
      const y=state==='sleeping'?233+Math.sin(q*TAU)*7:269-q*36;
      back+=feather(x,y,Math.sin(q*TAU)*22,.25+.35*Math.sin(q*Math.PI));
    }
    for(let i=0;i<3;i++) {
      const q=wrap(phase+i*.31),x=48+i*56+Math.sin(q*TAU)*4,y=(state==='sleeping'?248:242)-Math.sin(q*TAU)*5;
      front+=star(x,y,1.4+Math.sin(q*Math.PI),state==='sleeping'?.25:.25+.4*Math.sin(q*Math.PI));
    }
    return {back:svg(back),front:svg(front)};
  }
  root.JeanneEffects={render};
  if(typeof module!=='undefined') module.exports=root.JeanneEffects;
})(typeof globalThis!=='undefined'?globalThis:this);
