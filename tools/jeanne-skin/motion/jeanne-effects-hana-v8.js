(function(scope){
const W=448,H=640,TAU=2*Math.PI;
const palette=['#ed618a','#fff0b2','#f4c564','#fffaf1','#b72747'];
function star(x,y,s=12,c='#e8bd3e',o=1){return `<path d="M${x} ${y-s} Q${x+3} ${y-3} ${x+s} ${y} Q${x+3} ${y+3} ${x} ${y+s} Q${x-3} ${y+3} ${x-s} ${y} Q${x-3} ${y-3} ${x} ${y-s}" fill="${c}" stroke="#fff8d4" stroke-width="1.4" opacity="${o}"/>`;}
function note(x,y,s=1,r=0,o=1){return `<g transform="translate(${x} ${y}) rotate(${r}) scale(${s})" opacity="${o}"><path d="M0 13C-8 4-14-1-11-12L-7-9C-11-21-5-29 2-36C10-32 16-19 12-10L8-7C12 1 7 10 0 13Z" fill="#fffdf7" stroke="#c7a566" stroke-width="1.5"/><path d="M0 12Q1-9 2-30M1-12L-6-20M1-3L8-12M0 5L-7-2" fill="none" stroke="#dfc996" stroke-width="1.2"/></g>`;}
function bubble(x,y,r=15,c='#ec8ead',o=.8){return `<g opacity="${o}"><circle cx="${x}" cy="${y}" r="${r}" fill="${c}" fill-opacity=".35" stroke="${c}" stroke-width="2.5"/><circle cx="${x}" cy="${y}" r="${r*.67}" fill="#fff4db" fill-opacity=".28"/><path d="M${x-r*.55} ${y-r*.12}Q${x-r*.48} ${y-r*.65} ${x+r*.02} ${y-r*.68}" fill="none" stroke="#ffffff" stroke-width="3" stroke-linecap="round"/></g>`;}
function heart(x,y,s=1,c='#ed92b0',o=.9){return `<path transform="translate(${x} ${y}) scale(${s})" d="M0 8C-25-6-18-27-4-18L0-13 4-18C18-27 25-6 0 8Z" fill="${c}" fill-opacity="${o}" stroke="#fff0f4" stroke-width="2"/>`;}
function ring(x,y,rx,ry,p,c='#dbb53b'){return `<g opacity=".9"><ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${ry}" fill="none" stroke="${c}" stroke-width="3.2"/><ellipse cx="${x}" cy="${y}" rx="${rx-10}" ry="${Math.max(4,ry-7)}" fill="none" stroke="#fae6a0" stroke-width="2"/>${Array.from({length:5},(_,i)=>{const a=p*TAU+i*TAU/5;return star(x+rx*Math.cos(a),y+ry*Math.sin(a),7+i%2*3,palette[i]);}).join('')}</g>`;}
function petal(x,y,s,rot,c='#e45979',o=.9){return `<g transform="translate(${x} ${y}) rotate(${rot}) scale(${s/12})" opacity="${o}"><path d="M-6-4C-2-12 8-10 9-2C8 5 0 12-7 5Q-2 1-6-4Z" fill="${c}" stroke="#fff0d6" stroke-width="1.3"/><path d="M-3-5Q3-7 5-1Q1-3-1 3" fill="none" stroke="#ffbfc4" stroke-width="1.6"/></g>`;}
function glow(x,y,rx,ry,c='#ffe595'){return `<ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${ry}" fill="${c}" fill-opacity=".16"/>`;}
function arc(d,c='#dbb73f',o=1,w=3){return `<path d="${d}" fill="none" stroke="${c}" opacity="${o}" stroke-width="${w}" stroke-linecap="round"/>`;}
function svg(s){return `<svg xmlns="http://www.w3.org/2000/svg" width="224" height="320" viewBox="0 0 448 640">${s}</svg>`;}
function render(state,time,pose=0,attachment){time/=2;let b='',f='';const p=((time%4)+4)%4/4, sine=Math.sin(TAU*p);const short=(time%2+2)%2/2,life=q=>Math.sin(Math.PI*q);
 const dust=(x0,x1,y0,y1,n=7)=>Array.from({length:n},(_,i)=>{let q=(p+i/n)%1;return star(x0+(x1-x0)*(i%2),y1-(y1-y0)*q,4+4*Math.sin(Math.PI*q),palette[i%5],Math.sin(Math.PI*q)*.95)}).join('');
 if(state==='idle'){
  const q=(p+.5)%1;f=note(56+8*sine,310-65*p,1,12*sine,life(p))+note(355+7*Math.sin(TAU*(p+.3)),190-26*q,.8,-10*sine,life(q))+bubble(63,379-65*short,16+4*short,'#e6c76c',life(short))+dust(44,382,325,550,4);
 }else if(state==='running'){
  b=ring(215,551,149,35,p)+glow(215,420,144,130);
  for(let i=0;i<5;i++){let a=p*TAU+i*TAU/5,x=220+157*Math.cos(a),y=362+130*Math.sin(a),orb=bubble(x,y,10+2*Math.sin(a),palette[i],.92);if(y<350)b+=orb;else f+=orb;}
  f+=star(65,413,13+3*sine)+star(378,470,10-2*sine);
 }else if(state==='review'){
  b=ring(220,556,97+9*sine,23,p)+glow(220,526,113,60,'#ffcfdf');
  f=star(167+10*sine,512,12+4*sine,'#ffd06f')+star(270,523,10-3*sine)+bubble(61,413-55*short,12,'#f2b1c8',life(short))+note(365,337-30*p,.65,6*sine,life(p));
 }else if(state==='waiting'){
  const arcs=Array.from({length:3},(_,i)=>{let q=(short+i/3)%1,r=18+q*43;return arc(`M${324-r*.22} ${393-r} Q${360+r*.55} ${377-r*.8} ${363+r} 419`,'#e1b63f',1-q,3)}).join('');b=arcs;
  f=note(375+4*sine,330-38*p,.9,12*sine,life(p))+bubble(61,357-40*short,16,'#f0be81',life(short))+star(373,470,11+3*sine);
 }else if(state==='failed'){
  b=bubble(62,410,13+18*short,'#d793a3',1-short)+bubble(380,437,12+16*((short+.5)%1),'#f0bdc9',1-((short+.5)%1));
  f=Array.from({length:7},(_,i)=>{let a=i*TAU/7,q=short;return star(66+q*37*Math.cos(a),373+q*35*Math.sin(a),5*(1-q)+2,'#e2b19b',1-q)}).join('')+petal(366,473-40*p,11,150*p,'#fff0c0',life(p))+note(367,420-40*p,.7,30*sine,.8);
 }else if(state==='waving'){
  b=ring(215,574,140,25,p);
  const q=(short+.5)%1;f=note(56+5*sine,323-48*short,1.1,25*sine,life(short))+note(373-7*sine,377-62*q,.9,-20*sine,life(q))+note(64,475-28*p,.75,12*sine,life(p))+dust(40,394,355,520,6);
 }else if(state==='jumping'){
  b=ring(215,587,130+18*short,22+4*sine,p);
  f=Array.from({length:10},(_,i)=>{let q=(short+i/10)%1;return petal(58+i*36+9*Math.sin(TAU*q),584-155*Math.sin(Math.PI*q),8+4*Math.sin(Math.PI*q),i*41+180*q,palette[i%5],.82)}).join('')+star(63,373,12+3*sine)+star(389,389,10-2*sine);
 }else if(state==='sleeping'){
  b=`<path transform="translate(0 ${4*sine})" d="M77 215A38 38 0 1 0 122 273A33 33 0 0 1 77 215" fill="#edcf75" stroke="#faebba" stroke-width="2" opacity=".87"/>`;
  f=star(154,208+6*sine,8+2*sine)+star(340,278-5*sine,10-3*sine)+bubble(317,330-50*p,13+3*p,'#e8c6cc',life(p))+note(380,397-30*p,.5,-8*sine,life(p));
 }else if(state.startsWith('drag-')){
  const right=state==='drag-right',sgn=right?1:-1,x=right?59:389;
  b=arc(`M${x} 555Q${x+sgn*30} ${578+5*sine} ${x+sgn*91} 559`)+arc(`M${x-sgn*8} 574Q${x+sgn*30} 601 ${x+sgn*95} 578`,'#ead089',.8,2);
  f=Array.from({length:8},(_,i)=>{let q=(short+i/8)%1;return star(x+sgn*(65-65*q),541-32*Math.sin(Math.PI*q),4+6*Math.sin(Math.PI*q),palette[i%5],life(q))}).join('')+note(x,492-22*short,.65,sgn*15*sine,life(short));
 }
 return {back:svg(b),front:svg(f)};
}
scope.JeanneHanaEffects={render,width:224,height:320};if(typeof module!=='undefined')module.exports=scope.JeanneHanaEffects;
})(typeof globalThis!=='undefined'?globalThis:this);
