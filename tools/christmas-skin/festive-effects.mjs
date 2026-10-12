// 캐릭터와 분리해 재생하는 크리스마스 효과. 모든 좌표는 448×640 셀 기준이다.
const TAU=Math.PI*2;
const unit=t=>((t%1)+1)%1;
const colors=['#d7354d','#287752','#edba58'];
const snow=(x,y,r,a=1,rotate=0)=>`<g transform="translate(${x} ${y}) rotate(${rotate})" stroke="#83b9cc" stroke-width="1.5" stroke-linecap="round" opacity="${a}">${[0,60,120].map(angle=>`<g transform="rotate(${angle})"><path d="M${-r} 0H${r} M${-r*.62} ${-r*.28}L${-r*.37} 0L${-r*.62} ${r*.28} M${r*.62} ${-r*.28}L${r*.37} 0L${r*.62} ${r*.28}"/></g>`).join('')}</g>`;
const sparkle=(x,y,r,a=1,angle=0)=>`<g transform="translate(${x} ${y}) rotate(${angle})" opacity="${a}"><path d="M0 ${-r}Q${r*.2} ${-r*.2} ${r} 0Q${r*.2} ${r*.2} 0 ${r}Q${-r*.2} ${r*.2} ${-r} 0Q${-r*.2} ${-r*.2} 0 ${-r}" fill="#ffdc75" stroke="#c99438" stroke-width=".8"/></g>`;
const glow=(x,y,r,a,color='#ffc85f')=>`<circle cx="${x}" cy="${y}" r="${r}" fill="${color}" opacity="${a*.16}"/><circle cx="${x}" cy="${y}" r="${r*.55}" fill="${color}" opacity="${a*.27}"/><circle cx="${x}" cy="${y}" r="${r*.18}" fill="#fff2b9" opacity="${a*.8}"/>`;
export const effectPeriods={idle:4,moveRight:.68,moveLeft:.68,thinking:3,review:2,waiting:1.86,failed:3,jumping:.75,sleeping:5,waving:2.2};
export function shootingStars(time,period=effectPeriods.waving){
  return [[408,58,38,218,false],[420,150,390,574,true],[110,80,28,568,false]].map(([sx,sy,ex,ey,front],i)=>{
    const q=unit(time/period+i*.37),dx=ex-sx,dy=ey-sy,length=Math.hypot(dx,dy),ux=dx/length,uy=dy/length;
    return {x:sx+dx*q,y:sy+dy*q,ux,uy,travel:length*q,alpha:Math.pow(Math.sin(q*Math.PI),.8)*.95,front};
  });
}
export function reviewAtmosphere(time,period=effectPeriods.review){
  const p=unit(time/period),phase=p*TAU,sway=6*Math.sin(phase);
  return {sway,bulbs:Array.from({length:6},(_,i)=>{const x=50+i*70;return {x,y:113+(50/188**2)*(x-224)**2+sway,r:5,alpha:.35+.55*(.5+.5*Math.sin(phase-i*.8)),color:colors[i%3]};}),flakes:Array.from({length:8},(_,i)=>{const q=unit(p+i/8);return {x:(i%2?412:36)+8*Math.sin(phase+i),y:180+q*410,r:5+2*(i%3),alpha:Math.sin(q*Math.PI)*.65,angle:phase*18+i*25};})};
}
export function festiveEffects(group,time,front,poseIndex=0){
  const id=group.id==='moveLeft'?'moveRight':group.id;
  const p=unit(time/(group.effect_period??effectPeriods[id])),phase=p*TAU;
  let s='';
  if(id==='idle'){
    if(!front){
      for(let i=0;i<6;i++){const q=unit(p+i/6),x=i%2?414:32,y=165+q*430;s+=snow(x+9*Math.sin(phase+i),y,7+2*(i%2),Math.sin(q*Math.PI)*.8,phase*25+i*30);}
    }else s+=sparkle(36,568+12*Math.sin(phase),8,.25+.5*(.5+.5*Math.sin(phase*2)))+sparkle(412,299+18*Math.cos(phase),8,.2+.65*(.5+.5*Math.cos(phase)));
  }
  if(id==='moveRight'){
    for(let i=0;i<9;i++){const q=unit(p+i/9),x=145-118*q,y=595+20*Math.sin(q*Math.PI+i*.8),a=Math.sin(q*Math.PI)*.8;
      if(!front)s+=snow(x,y,5+4*q,a,phase*30+i*30);
      else if(i%3===0)s+=sparkle(x,617-12*q,5,a);
    }
    if(!front)s+=`<path d="M25 592Q69 ${574+8*Math.sin(phase)} 109 587" fill="none" stroke="#acd2df" stroke-width="2" stroke-dasharray="5 11" stroke-dashoffset="${-p*32}" opacity=".55"/>`;
  }
  if(id==='thinking'){
    if(front){
      for(let i=0;i<7;i++){const a=phase+i*TAU/7,x=210+170*Math.cos(a),y=536+38*Math.sin(a);s+=sparkle(x,y,7+3*(.5+.5*Math.sin(a)),.3+.6*(.5+.5*Math.sin(a)),a*30);}
      s+=`<ellipse cx="210" cy="536" rx="165" ry="38" fill="none" stroke="#dfb74e" stroke-width="2" stroke-dasharray="8 22" stroke-dashoffset="${-p*60}" opacity=".65"/>`;
    }
    if(front){
      for(let i=0;i<3;i++){const q=unit(p+i/3);s+=sparkle(320+45*q,553-115*q,8,Math.sin(q*Math.PI)*.9,phase*40);}
      s+=glow(207,536,18,.4+.4*Math.sin(phase)**2);
    }
  }
  if(id==='review'){
    if(!front){
      const atmosphere=reviewAtmosphere(time,group.effect_period??effectPeriods.review),y=atmosphere.sway;
      s+=`<path d="M36 ${155+y}Q224 ${55+y} 412 ${155+y}" fill="none" stroke="#367e59" stroke-width="3" opacity=".55"/>`;
      for(const bulb of atmosphere.bulbs)s+=`<path d="M${bulb.x} ${bulb.y-8}v8" stroke="#b4914d" stroke-width="1.5" opacity=".65"/>`+glow(bulb.x,bulb.y,13,bulb.alpha,bulb.color)+`<circle cx="${bulb.x}" cy="${bulb.y}" r="${bulb.r}" fill="${bulb.color}" opacity="${bulb.alpha}"/>`;
      for(const flake of atmosphere.flakes)s+=snow(flake.x,flake.y,flake.r,flake.alpha,flake.angle);
      for(let i=0;i<4;i++){const q=unit(p+i/4);s+=sparkle(i%2?405:42,230+q*285,6,Math.sin(q*Math.PI)*.7,phase*20);}
    }
    const key=group.pose_sequence?.[poseIndex]??0,[cx,cy]=group.effect_anchors?.[poseIndex]?.[0]??[77,key===2?468:494];
    if(!front){s+=glow(cx,cy,46,.45+.45*Math.sin(phase)**2);for(let i=0;i<5;i++){const a=phase+i*TAU/5;s+=sparkle(cx+37*Math.cos(a),cy+37*Math.sin(a),7,.65,a*25);}}
    else{for(let i=0;i<6;i++){const a=phase/2+i*TAU/6,r=29+7*Math.sin(phase);s+=`<path d="M${cx+Math.cos(a)*r} ${cy+Math.sin(a)*r}l${Math.cos(a)*9} ${Math.sin(a)*9}" stroke="#dfaa37" stroke-width="2" opacity="${.35+.5*Math.sin(phase)**2}"/>`;}}
  }
  if(id==='waiting'){
    const key=group.pose_sequence?.[poseIndex]??0,[cx,cy]=group.effect_anchors?.[poseIndex]?.[0]??[key===1?308:key===2?355:329,key===1?454:438];
    if(front){for(let i=0;i<3;i++){const q=unit(p+i/3),r=12+38*q;s+=`<path d="M${cx+r*.65} ${cy-r*.76}A${r} ${r} 0 0 1 ${cx+r*.65} ${cy+r*.76}" fill="none" stroke="#d79c32" stroke-width="${3.4-1.4*q}" opacity="${.8*(1-q)}"/>`;}
      const q=unit(p+.3);s+=`<g transform="translate(${392+6*Math.sin(phase)} ${427-58*q})" opacity="${Math.sin(q*Math.PI)}" fill="#c89332"><path d="M0 0v-17l12-3v14h-3v-10l-6 2v14z"/><ellipse cx="-2" cy="1" rx="5" ry="3"/><ellipse cx="10" cy="-5" rx="5" ry="3"/></g>`;
    }else s+=glow(cx,cy,29,.35+.5*Math.sin(phase)**2);
  }
  if(id==='failed'){
    const key=group.pose_sequence?.[poseIndex]??0;
    const bulbs=group.effect_anchors?.[poseIndex]??(key===1?[[144,475],[158,523],[182,578],[262,584],[159,490]]:key===2?[[290,397],[237,571],[166,598],[201,604],[259,599]]:[[126,593],[173,608],[195,615],[217,608],[269,597]]);
    if(front){for(let i=0;i<bulbs.length;i++){const a=.15+.65*(.5+.5*Math.sin(phase-i*1.2))**3;s+=glow(...bulbs[i],10,a,colors[i%3]);}
      const q=unit(p+.2);s+=sparkle(315+18*q,581-67*q,7,Math.sin(q*Math.PI)*.65,phase*30);
    }else{for(let i=0;i<3;i++){const q=unit(p+i/3);s+=snow(405+5*Math.sin(phase+i),535+74*q,6,Math.sin(q*Math.PI)*.55,phase*12);}}
  }
  if(id==='jumping'){
    // 선물·바닥 소품 없이, 도약에 맞춰 퍼지는 눈꽃과 빨강·초록·금색 색종이만 사용한다.
    if(!front){const a=Math.sin(p*Math.PI),r=24+160*p;s+=`<ellipse cx="205" cy="612" rx="${r}" ry="${5+8*p}" fill="none" stroke="#dfb85a" stroke-width="${4-2*p}" opacity="${a*.7}"/>`;}
    for(let i=0;i<12;i++){const q=unit(p+i*.037),side=i%2?-1:1,x=205+side*(50+q*130),y=593-200*Math.sin(q*Math.PI),a=Math.sin(q*Math.PI)*.9;
      if(!front&&i%3===0)s+=snow(x,y,9,a,phase*50+i*30);
      if(front&&i%3!==0)s+=`<rect x="${x}" y="${y}" width="6" height="12" rx="1" fill="${colors[i%3]}" opacity="${a}" transform="rotate(${phase*75+i*40} ${x+3} ${y+6})"/>`;
    }
  }
  if(id==='sleeping'){
    if(!front){const x=285+9*Math.sin(phase),y=392+7*Math.cos(phase);s+=glow(x,y,27,.3+.25*(.5+.5*Math.sin(phase)));s+=`<path d="M${x} ${y-16}A17 17 0 1 0 ${x+13} ${y+13}A15 15 0 0 1 ${x} ${y-16}" fill="#eac36e" opacity=".85"/>`;
      for(let i=0;i<4;i++){const q=unit(p+i/4);s+=snow(174+i*58+10*Math.sin(phase+i),353+82*q,6+2*(i%2),Math.sin(q*Math.PI)*.65,phase*12+i*30);}
    }else s+=sparkle(403,452+12*Math.sin(phase),7,.3+.3*Math.sin(phase)**2);
  }
  if(id==='waving'){
    for(const m of shootingStars(time,group.effect_period??effectPeriods.waving)){
      if(m.front!==front)continue;
      const {x,y,ux,uy,travel,alpha:a}=m;
      const tail=(length,width,opacity,color)=>`<path d="M${x-ux*Math.min(length,travel)} ${y-uy*Math.min(length,travel)}L${x} ${y}" stroke="${color}" stroke-width="${width}" stroke-linecap="round" opacity="${a*opacity}"/>`;
      s+=tail(86,9,.08,'#efb846')+tail(68,4,.28,'#e6b34c')+tail(45,1.8,.85,'#f5cf79');
      for(let k=1;k<=4;k++){const offset=Math.min(k*21,travel);const tx=x-ux*offset+(k%2?3:-3),ty=y-uy*offset;s+=sparkle(tx,ty,3.5-k*.45,a*(1-k/5)*.65);}
      const points=Array.from({length:10},(_,i)=>{const angle=-Math.PI/2+i*Math.PI/5,r=i%2?4:9;return `${x+Math.cos(angle)*r},${y+Math.sin(angle)*r}`;}).join(' ');
      s+=glow(x,y,16,a)+`<polygon points="${points}" fill="#ffe39a" stroke="#c99438" stroke-width="1" opacity="${a}"/>`;
    }
  }
  if(group.id==='moveLeft')s=`<g transform="translate(448 0) scale(-1 1)">${s}</g>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="448" height="640" viewBox="0 0 448 640">${s}</svg>`;
}
