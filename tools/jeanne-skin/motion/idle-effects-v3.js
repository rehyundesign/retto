(function(root){
  const tau=Math.PI*2,n=x=>x.toFixed(2),wrap=x=>(x%1+1)%1;
  const svg=x=>`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 224 320">${x}</svg>`;
  function star(x,y,r,o){return `<path d="M${n(x)},${n(y-r)} L${n(x+r*.24)},${n(y-r*.24)} L${n(x+r)},${n(y)} L${n(x+r*.24)},${n(y+r*.24)} L${n(x)},${n(y+r)} L${n(x-r*.24)},${n(y+r*.24)} L${n(x-r)},${n(y)} L${n(x-r*.24)},${n(y-r*.24)}Z" fill="#ffe6a4" stroke="#d6a042" stroke-width=".35" opacity="${n(o)}"/>`}
  function feather(x,y,angle,o){return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)})" opacity="${n(o)}"><path d="M0,-7 C7,-5 7,3 0,8 C-5,4 -5,-3 0,-7Z" fill="#fff8ec" stroke="#c7ad83" stroke-width=".45"/><path d="M0,-5 V7 M0,-1 L3,-3 M0,3 L-3,1" fill="none" stroke="#bca17b" stroke-width=".4"/></g>`}
  function render(state,time,frame){
    const p=wrap(time/8),a=p*tau,pulse=.65+.2*Math.sin(a);
    let back=`<g fill="none" stroke="#e5bd63" opacity="${n(pulse)}"><ellipse cx="88" cy="298" rx="${n(61+Math.sin(a)*2)}" ry="15" stroke-width="1"/><ellipse cx="88" cy="298" rx="50" ry="11" stroke-width=".45"/></g>`;
    let front='';
    for(let i=0;i<4;i++){const q=wrap(p+i*.25),left=i%2===0,x=(left?18:205)+Math.sin(q*tau)*3,y=269+Math.cos(q*tau)*22;const o=.3+.45*(1-Math.cos(q*tau))/2;back+=feather(x,y,Math.sin(q*tau)*25,o)}
    back+=`<path d="M16,245 C24,276 135,289 202,237" transform="translate(0 ${n(Math.sin(a)*3)})" fill="none" stroke="#cf304c" stroke-width="2.5" opacity=".65"/>`;
    for(let i=0;i<7;i++){const q=p+i/7,angle=q*tau,x=88+Math.cos(angle)*67,y=276+Math.sin(angle)*28;front+=star(x,y,1.4+Math.sin(q*tau)**2*1.4,.35+.4*Math.sin(q*tau)**2)}
    const x=21+Math.sin(a)*2,y=236+Math.cos(a)*3;
    front+=`<g transform="rotate(${n(p*360)} ${n(x)} ${n(y)})" fill="none" stroke="#e8c36d" opacity="${n(pulse)}"><circle cx="${n(x)}" cy="${n(y)}" r="10" stroke-width=".9"/><circle cx="${n(x)}" cy="${n(y)}" r="7" stroke-width=".4"/><path d="M${n(x-12)},${n(y)}H${n(x+12)} M${n(x)},${n(y-12)}V${n(y+12)}" stroke-width=".7"/></g>`;
    front+=star(164+Math.sin(a)*3,227,3,pulse);
    return {back:svg(back),front:svg(front)};
  }
  root.JeanneEffects={render};if(typeof module!=='undefined')module.exports=root.JeanneEffects;
})(typeof globalThis!=='undefined'?globalThis:this);
