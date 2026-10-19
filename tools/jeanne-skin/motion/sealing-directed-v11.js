(function(root){
 const n=x=>Number(x).toFixed(2),clamp=x=>Math.max(0,Math.min(1,x)),smooth=(a,b,x)=>{let q=clamp((x-a)/(b-a));return q*q*(3-2*q)},T=Math.PI*2;
 const hands=[[76,226],[82,199],[68,172],[65,172],[64,174],[56,170],[58,171],[59,171],[58,174],[61,174],[89,202],[65,193],[79,224],[78,229],[78,229],[76,228]];
 const svg=s=>`<svg xmlns="http://www.w3.org/2000/svg" width="224" height="320" viewBox="0 0 224 320">${s}</svg>`;
 const glint=(x,y,r,o)=>`<path d="M${n(x-r)} ${n(y)}Q${n(x)} ${n(y-1)} ${n(x)} ${n(y-r)}Q${n(x+1)} ${n(y)} ${n(x+r)} ${n(y)}Q${n(x)} ${n(y+1)} ${n(x)} ${n(y+r)}Q${n(x-1)} ${n(y)} ${n(x-r)} ${n(y)}Z" fill="#fffbe7" opacity="${n(o)}"/>`;
 function feather(x,y,angle,o){return `<g transform="translate(${n(x)} ${n(y)}) rotate(${n(angle)})" opacity="${n(o)}"><path d="M0 9C-6 2-9-5-4-12L0-15C7-10 9-3 3 4Z" fill="#fff9ee" stroke="#e8bb84" stroke-width=".6"/><path d="M0 8V-10M0 0L-4-5M0-3L4-8" fill="none" stroke="#d9b17b" stroke-width=".5"/></g>`}
 function ribbon(points,time,opacity){if(points.length<2||opacity<.01)return '';let l=[],r=[];for(let i=0;i<points.length;i++){const prev=points[Math.max(0,i-1)],next=points[Math.min(points.length-1,i+1)],dx=next.x-prev.x,dy=next.y-prev.y,length=Math.hypot(dx,dy)||1,q=i/(points.length-1),half=(1.4+1.7*Math.sin(q*Math.PI))*(.88+.12*Math.sin(time*3+q*8));l.push([points[i].x-dy/length*half,points[i].y+dx/length*half]);r.push([points[i].x+dy/length*half,points[i].y-dx/length*half]);}const path='M'+l.map(p=>p.map(n).join(' ')).join('L')+'L'+r.reverse().map(p=>p.map(n).join(' ')).join('L')+'Z';return `<path d="${path}" fill="url(#silk11)" stroke="#a61e3b" stroke-width=".55" opacity="${n(opacity)}"/>`}
 function render(state,time,frame,attachment,phase){
 const u=phase===undefined?frame/16:phase,gather=smooth(.02,.24,u)*(1-smooth(.4,.56,u)),cast=smooth(.25,.48,u),close=smooth(.47,.56,u),fade=1-smooth(.66,.94,u),flash=Math.exp(-(((u-.57)/.06)**2)),release=smooth(.63,.98,u),pulse=.5+.5*Math.sin(time*5),hand=hands[frame%16],hx=hand[0],hy=hand[1],x=attachment?.x??98,y=attachment?.y??220,tx=46,ty=269;
 const defs=`<defs><radialGradient id="light11"><stop stop-color="#fffef5"/><stop offset=".22" stop-color="#ffe9b5" stop-opacity=".9"/><stop offset=".55" stop-color="#ffc1d9" stop-opacity=".6"/><stop offset="1" stop-color="#ffb8cc" stop-opacity="0"/></radialGradient><linearGradient id="silk11" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#8c1732"/><stop offset=".42" stop-color="#ee4262"/><stop offset=".62" stop-color="#ffc0b1"/><stop offset=".8" stop-color="#d42c4e"/><stop offset="1" stop-color="#8c1732"/></linearGradient></defs>`;
 let b=defs,f=defs;
 // Preparation: a current leaves the worn Rosario and meets the presented palm.
 const gatherLight=.05+gather*.85;
 f+=`<circle cx="${n(x)}" cy="${n(y)}" r="${n(9+gather*9)}" fill="url(#light11)" opacity="${n(gatherLight)}"/><circle cx="${hx}" cy="${hy}" r="${n(8+gather*13)}" fill="url(#light11)" opacity="${n(gather*(.8+.15*pulse))}"/>`;
 for(let i=0;i<4;i++){let q=((time/1.4+i/4)%1+1)%1,px=x+(hx-x)*q+Math.sin(q*Math.PI)*9,py=y+(hy-y)*q;f+=glint(px,py,1.5+q,gather*Math.sin(q*Math.PI));}
 // Actual evolving fabric trajectory, not a rotated finished effect image.
 const origin=u>.5?hands[8]:hand,ox=origin[0],oy=origin[1],trim=smooth(.53,.76,u)*.85;const points=[];for(let i=0;i<=36;i++){const q=i/36;if(q<trim)continue;if(q>cast)break;const z=1-q;points.push({x:z*z*z*ox+3*z*z*q*20+3*z*q*q*18+q*q*q*tx,y:z*z*z*oy+3*z*z*q*219+3*z*q*q*258+q*q*q*ty});}
 f+=ribbon(points,time,fade);
 const coils=[];for(let i=0;i<=55;i++){const q=i/55;if(q>close)break;const angle=q*T*1.45+.3,rad=26-q*15;coils.push({x:tx+Math.cos(angle)*rad,y:ty+Math.sin(angle)*rad*.67+Math.sin(time*2+q*5)*.6});}f+=ribbon(coils,time,fade);
 // Seal: the spiral closes to a cross, then releases one strong light impulse.
 b+=`<circle cx="${tx}" cy="${ty}" r="${n(10+flash*24)}" fill="url(#light11)" opacity="${n(close*fade*.75)}"/>`;
 f+=`<path d="M${tx} ${ty-17}V${ty+18}M${tx-11} ${ty-5}H${tx+11}" fill="none" stroke="#f5c56e" stroke-width="2" opacity="${n(close*fade)}"/>`;
 f+=glint(tx,ty,6+flash*24,close*fade*(.5+.5*pulse));
 for(let i=0;i<8;i++){const a=i*T/8+time*.03,rad=9+flash*24;f+=`<path d="M${n(tx+Math.cos(a)*9)} ${n(ty+Math.sin(a)*9)}L${n(tx+Math.cos(a)*rad)} ${n(ty+Math.sin(a)*rad)}" stroke="#ffe9ba" stroke-width="${i%2?1:1.8}" opacity="${n(flash*.9)}"/>`;}
 // Follow-through: the sealed light loosens into feathers and drifting dust.
 if(u>.62)for(let i=0;i<3;i++){const a=i*2.1+1.4,px=tx+Math.cos(a)*release*29,py=ty+release*(20+i*9)+Math.sin(time*2+i)*2;f+=feather(px,py,release*80+i*35,(1-release)*Math.sin(release*Math.PI)*.95);}
 for(let i=0;i<3;i++){const q=((time/4+i/3)%1+1)%1;b+=glint(156+i*16,286-q*13,1.4,Math.sin(q*Math.PI)*.13);}
 return {back:svg(b),front:svg(f)};
 }
 root.JeanneSealing11={render};if(typeof module!=='undefined')module.exports=root.JeanneSealing11;
})(globalThis);
