(function (root) {
  'use strict';
  const cycles = {idle:3.2, running:2.4, review:3.2, waiting:3.2, failed:3.2, waving:2.4, jumping:2.4, sleeping:6.4, 'drag-right':1.6, 'drag-left':1.6};
  const descriptions = {
    idle:'진주빛 하트와 부드러운 분홍 보케',
    running:'앞발 사이의 크리스털 하트 · 분홍 발동 광선 · 빛나는 마법진',
    review:'보석에 반응하는 청백색 섬광과 무지갯빛 십자 반짝임',
    waiting:'사용자에게 흐르는 발광 하트와 진주빛 호출 고리',
    failed:'흩어진 빛 조각이 크리스털 하트로 다시 모이는 회복',
    waving:'반짝이는 키스 하트와 분홍 축하 광선',
    jumping:'백분홍 꽃잎 · 상승하는 빛 · 발광 착지 고리',
    sleeping:'진주빛 초승달과 천천히 흐르는 십자 별',
    'drag-right':'왼쪽 뒤로 흐르는 발광 리본과 하트 보케',
    'drag-left':'오른쪽 뒤로 흐르는 발광 리본과 하트 보케'
  };
  const pink='#ea4b89', deep='#bc285b', gold='#c59635', ivory='#ffddac', blue='#489ad7';
  const tau=Math.PI*2;
  let textures={};
  function setTextures(value){textures=value;}
  function material(ctx,id,x,y,r,alpha,angle=0){
    const image=textures[id];if(!image)return false;
    local(ctx,x,y,alpha,()=>{ctx.rotate(angle);ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality='high';ctx.shadowColor=id==='moon'?'#f5d497':'#ffb3d7';ctx.shadowBlur=r*.7;ctx.drawImage(image,-r*1.8,-r*1.8,r*3.6,r*3.6);});return true;
  }
  function local(ctx,x,y,alpha,fn){ctx.save();ctx.translate(x,y);ctx.globalAlpha*=Math.max(0,Math.min(1,alpha));fn();ctx.restore();}
  function heart(ctx,x,y,r,alpha=1,outline=false,color=pink){
    if(material(ctx,'heart',x,y,r,alpha*(outline?.72:1)))return;
    local(ctx,x,y,alpha,()=>{
      ctx.shadowColor='#ff77d8';ctx.shadowBlur=r*1.6;
      ctx.beginPath();ctx.moveTo(0,r*.7);ctx.bezierCurveTo(-r*1.5,-r*.1,-r*.8,-r*1.3,0,-r*.48);ctx.bezierCurveTo(r*.8,-r*1.3,r*1.5,-r*.1,0,r*.7);ctx.closePath();
      const material=ctx.createLinearGradient(-r,-r,r,r);material.addColorStop(0,'#ffffff');material.addColorStop(.28,'#ffe3f8');material.addColorStop(.63,color);material.addColorStop(1,'#fa5cc0');
      ctx.fillStyle=material;ctx.strokeStyle=outline?'#ffa5e8':'#ffdeb1';ctx.lineWidth=outline?2:1;
      if(!outline)ctx.fill();ctx.stroke();ctx.shadowBlur=0;
      if(outline){ctx.strokeStyle='#fff4ff';ctx.lineWidth=.65;ctx.stroke();}
      else{ctx.save();ctx.clip();const sheen=ctx.createLinearGradient(-r,-r,0,r*.3);sheen.addColorStop(0,'rgba(255,255,255,.95)');sheen.addColorStop(.55,'rgba(255,255,255,.35)');sheen.addColorStop(1,'rgba(255,255,255,0)');ctx.fillStyle=sheen;ctx.beginPath();ctx.ellipse(-r*.25,-r*.35,r*.6,r*.25,-.5,0,tau);ctx.fill();if(r>=9){ctx.fillStyle='rgba(255,255,255,.35)';ctx.beginPath();ctx.moveTo(0,-r*.45);ctx.lineTo(r*.6,-r*.15);ctx.lineTo(0,r*.65);ctx.lineTo(-r*.4,0);ctx.closePath();ctx.fill();ctx.strokeStyle='rgba(255,245,255,.6)';ctx.lineWidth=.5;ctx.stroke();}ctx.restore();}
    });
  }
  function star(ctx,x,y,r,alpha,color=gold){if(material(ctx,'star',x,y,r,alpha))return;local(ctx,x,y,alpha,()=>{ctx.shadowColor=color;ctx.shadowBlur=r*2.2;ctx.beginPath();for(let i=0;i<8;i++){const a=i*Math.PI/4,d=i%2?r*.12:r*(i%4===0?1.65:1.1);const px=Math.sin(a)*d,py=Math.cos(a)*d;i?ctx.lineTo(px,py):ctx.moveTo(px,py);}ctx.closePath();ctx.strokeStyle=color;ctx.lineWidth=.7;ctx.fillStyle='#ffffff';ctx.stroke();ctx.fill();ctx.shadowBlur=0;});}
  function ring(ctx,x,y,rx,ry,alpha,color=gold){local(ctx,x,y,alpha,()=>{
    ctx.beginPath();ctx.ellipse(0,0,rx,ry,0,0,tau);ctx.shadowColor='#ff83d8';ctx.shadowBlur=12;
    const g=ctx.createLinearGradient(-rx,-ry,rx,ry);g.addColorStop(0,'#ce719c');g.addColorStop(.23,'#ffbddc');g.addColorStop(.42,'#fff5d6');g.addColorStop(.62,color===blue?'#94c7eb':'#edb7c0');g.addColorStop(.83,'#f7d194');g.addColorStop(1,'#bf6994');
    ctx.strokeStyle=g;ctx.lineWidth=4.2;ctx.stroke();ctx.shadowBlur=0;
    ctx.beginPath();ctx.ellipse(0,-.65,rx,ry,0,Math.PI*1.02,Math.PI*1.92);ctx.strokeStyle='rgba(255,252,231,.9)';ctx.lineWidth=.95;ctx.stroke();
  });}
  function glow(ctx,x,y,r,alpha,color){local(ctx,x,y,alpha,()=>{const g=ctx.createRadialGradient(0,0,0,0,0,r);g.addColorStop(0,'#fff8ff');g.addColorStop(.2,color);g.addColorStop(.65,'rgba(255,130,216,.25)');g.addColorStop(1,'rgba(255,130,216,0)');ctx.fillStyle=g;ctx.fillRect(-r,-r,r*2,r*2);});}
  function petal(ctx,x,y,r,angle,alpha){if(material(ctx,'petal',x,y,r,alpha,angle))return;local(ctx,x,y,alpha,()=>{ctx.rotate(angle);ctx.shadowColor='#ffa4e8';ctx.shadowBlur=5;ctx.beginPath();ctx.moveTo(0,-r);ctx.bezierCurveTo(r*1.3,0,r*.65,r,0,r);ctx.bezierCurveTo(-r*.65,r,-r*1.3,0,0,-r);const g=ctx.createLinearGradient(0,-r,0,r);g.addColorStop(0,'#ffffff');g.addColorStop(.55,'#ffe1f7');g.addColorStop(1,'#ff93d2');ctx.fillStyle=g;ctx.fill();});}
  function rays(ctx,x,y,phase,power){
    local(ctx,x,y,power,()=>{for(let i=0;i<10;i++){
      const a=tau*i/10+.06*Math.sin(tau*phase),sx=Math.cos(a),sy=Math.sin(a);
      const ex=sx*86,ey=sy*(sy<0?175:60);
      for(let j=0;j<9;j++){const u=(j+.5)/9;glow(ctx,ex*u,ey*u,12+14*u,.32*Math.pow(1-u,.7),i%3?'#ff98d3':'#d4b3ff');}
    }});
  }
  function bokeh(ctx,x,y,r,alpha){local(ctx,x,y,alpha,()=>{const g=ctx.createRadialGradient(-r*.2,-r*.3,0,0,0,r);g.addColorStop(0,'rgba(255,255,255,.7)');g.addColorStop(.5,'rgba(255,166,235,.3)');g.addColorStop(1,'rgba(192,152,255,0)');ctx.fillStyle=g;ctx.beginPath();ctx.arc(0,0,r,0,tau);ctx.fill();ctx.strokeStyle='rgba(255,218,248,.35)';ctx.lineWidth=.5;ctx.stroke();});}
  // Keep v4 materials, particle counts and brightness; vary the choreography.
  function atmosphere(ctx,state,phase){
    const quiet=state==='sleeping'||state==='idle';
    const power=state==='running'?.75:state==='waving'?.55:state==='jumping'?.48:state==='review'?.34:state==='waiting'?.24:state==='failed'?.16:.06;
    const center=state==='waiting'?[156,216]:state==='review'?[103,210]:state==='jumping'?[112,287]:state==='waving'?[112,183]:[112,216];
    if(!state.startsWith('drag')){glow(ctx,...center,96,power,'#ff85cf');if(!quiet)rays(ctx,...center,state==='review'?-phase:phase,power);}
    function path(p,i){
      const side=i%2?1:-1,a=tau*(p+i/10);
      if(state==='running'){const r=90*(1-p)+13;return [112+Math.cos(a)*r,245+Math.sin(a)*r*.9];}
      if(state==='review')return [112+86*Math.cos(a),210+92*Math.sin(a)];
      if(state==='waiting')return [131+75*p,219+side*(12+65*p)];
      if(state==='failed'){const q=p<.5?p*2:(1-p)*2;return [112+side*(25+62*q),229+64*q+8*Math.sin(i)];}
      if(state==='waving'){const angle=Math.PI+(i+.5)/10*Math.PI;return [112+Math.cos(angle)*(23+82*p),186+Math.sin(angle)*(30+147*p)];}
      if(state==='jumping')return [112+side*(59+24*Math.sin(Math.PI*p)),302-232*p];
      if(state==='sleeping')return [112+side*(68+10*Math.sin(a)),198+19*Math.sin(a)];
      if(state.startsWith('drag')){const d=state==='drag-right'?1:-1;return [112-d*(38+64*p),240+side*14+9*Math.sin(a)];}
      return [112+side*(76+11*Math.sin(a+i)),253-94*p];
    }
    for(let i=0;i<(quiet?3:5);i++){const p=(phase+i/5)%1,[x,y]=path(p,i);bokeh(ctx,x,y,7+7*Math.sin(Math.PI*p),.6*fade(p));}
    const count=quiet?5:10;
    for(let i=0;i<count;i++){const p=(phase+i/count)%1,[x,y]=path(p,i),opacity=(quiet?.4:.72)*fade(p);
      if(state==='jumping'||state.startsWith('drag'))petal(ctx,x,y,5+2*fade(p),tau*p,opacity);
      else if(state==='review'||state==='sleeping')star(ctx,x,y,3.5+2.5*fade(p),opacity);
      else if(i%3===0||state==='waving')heart(ctx,x,y,5+2*fade(p),opacity);
      else star(ctx,x,y,2.5+2.5*fade(p),opacity);
    }
  }
  const fade=p=>Math.sin(Math.PI*p)**2;
  function draw(ctx,state,time,front,options={}){
    if(!(state in cycles))throw new Error('Unknown Magical Heart effect state: '+state);
    const t=Math.max(0,time), rawPhase=(t/cycles[state])%1;
    const phase=rawPhase<1e-9||rawPhase>1-1e-9?0:rawPhase;
    const jewel=options.jewel||[112,204], spell=options.spell||[112,250];
    ctx.save();ctx.beginPath();ctx.rect(6,6,212,308);ctx.clip();
    if(front && !state.startsWith('drag') && state!=='sleeping'){
      // Keep foreground particles outside the face; back effects remain behind it.
      ctx.beginPath();ctx.rect(0,0,224,320);ctx.rect(42,65,145,119);ctx.clip('evenodd');
    }
    if(!front)atmosphere(ctx,state,phase);
    if(state==='idle'){
      if(!front){glow(ctx,112,242,65,.09+.025*Math.sin(tau*phase),pink);}
      else for(let i=0;i<4;i++){const p=(phase+i/4)%1,s=i%2?1:-1;heart(ctx,112+s*(89+3*Math.sin(tau*p)),255-p*60,4.5+2*fade(p),.95*fade(p));star(ctx,112-s*86,225-p*36,3.5,.8*fade(p));}
    }else if(state==='running'){
      if(!front){ring(ctx,112,232,90,65,.7);ring(ctx,112,270,85,19,.65,pink);for(let i=0;i<8;i++){const a=tau*(phase+i/8);star(ctx,112+90*Math.cos(a),232+65*Math.sin(a),i%2?2.5:4,.9);}}
      else{const pulse=.65+.2*Math.sin(tau*phase);glow(ctx,...spell,35,.38,pink);heart(ctx,...spell,8.5+2*pulse,.98);for(let i=0;i<7;i++){const q=(phase+i/7)%1,a=tau*(q*1.5+i/7),r=12+44*(1-q);star(ctx,spell[0]+r*Math.cos(a),spell[1]+r*.6*Math.sin(a),3.7,.9,i%2?pink:gold);}}
    }else if(state==='review'){
      if(!front){for(let i=0;i<6;i++){const a=tau*(i/6+.06*Math.sin(tau*phase));petal(ctx,112+82*Math.cos(a),282+8*Math.sin(a),4,a,.6);}}
      else{for(let i=0;i<3;i++){const p=(phase+i/3)%1;star(ctx,26+3*Math.sin(tau*p),242-45*p,3+3*fade(p),.85*fade(p),blue);}glow(ctx,...jewel,22,.42,blue);star(ctx,...jewel,6+3*fade(phase),.95,blue);for(let i=0;i<2;i++){const p=(phase+i*.5)%1;ring(ctx,...jewel,19,7,.9*fade(p),blue);star(ctx,jewel[0]+19*Math.cos(tau*p),jewel[1]+9*Math.sin(tau*p),1.8,.65*fade(p),ivory);}}
    }else if(state==='waiting'){
      if(!front){for(let i=0;i<3;i++){const p=(phase+i/3)%1;ring(ctx,167+20*p,218,9+22*p,15+37*p,.7*fade(p),pink);}}
      else for(let i=0;i<4;i++){const p=(phase+i/4)%1;const x=131+68*p,y=227-24*Math.sin(Math.PI*p);heart(ctx,x,y,4+3*fade(p),.95*fade(p),i%2===1);star(ctx,x-5,y+7,2.5,.8*fade(p));}
    }else if(state==='failed'){
      if(!front){glow(ctx,112,257,53,.08,pink);}
      else if(phase<.48){const p=phase/.48;for(let i=0;i<7;i++){const a=tau*i/7;star(ctx,spell[0]+(10+76*p)*Math.cos(a),spell[1]+(8+33*p)*Math.sin(a),4.5*(1-p),.95*fade(p),i%2?blue:gold);}heart(ctx,spell[0]-8*p,spell[1]+10*p,4,.55*fade(p),true);heart(ctx,197-4*p,224+9*p,7,.9*fade(p),true);}
      else{const p=(phase-.48)/.52;heart(ctx,...spell,6+5*Math.sin(Math.PI*p),.95*fade(p));heart(ctx,199,224,7+2*fade(p),.9*fade(p));for(let i=0;i<4;i++){const a=tau*i/4;star(ctx,spell[0]+22*(1-p)*Math.cos(a),spell[1]+12*(1-p)*Math.sin(a),2.8,.85*fade(p));}}
    }else if(state==='waving'){
      if(!front){ring(ctx,112,280,85,16,.4+.2*fade(phase),pink);for(let i=0;i<6;i++){const p=(phase+i/6)%1,a=Math.PI+(i+.5)*Math.PI/6;star(ctx,112+Math.cos(a)*(38+66*p),173+Math.sin(a)*(35+111*p),4+2*fade(p),.8*fade(p));}}
      else for(let i=0;i<5;i++){const p=(phase+i/5)%1;const x=25+38*Math.exp(-22*p),y=194-145*p;heart(ctx,x,y,5+4*fade(p),.95*fade(p),false,i%2?pink:deep);star(ctx,x+8,y+11,2.8,.85*fade(p));}
    }else if(state==='jumping'){
      if(!front){for(let i=0;i<8;i++){const p=(phase+i/8)%1,a=tau*p+Math.PI*i;petal(ctx,112+Math.cos(a)*(80+7*p),292-150*p,4+2*fade(p),a,.9*fade(p));}}
      else{for(let i=0;i<4;i++){const q=(phase+i/4)%1;petal(ctx,i%2?201:25,286-140*q,4+2*fade(q),tau*q,.85*fade(q));}const p=(phase+.3)%1;const pulse=Math.sin(Math.PI*Math.min(1,p/.15)/2)*(1-p);ring(ctx,112,299,19+65*p,3+12*p,.95*pulse,pink);ring(ctx,112,299,15+53*p,2+9*p,.7*pulse,gold);for(let i=0;i<5;i++){const a=Math.PI*i/4;star(ctx,112+Math.cos(a)*70,296-Math.sin(a)*18,2,.6*fade(p));}}
    }else if(state==='sleeping'){
      if(!front){if(!material(ctx,'moon',172,177,14,.9))local(ctx,172,177,.85,()=>{ctx.beginPath();ctx.arc(0,0,18,Math.PI*.25,Math.PI*1.75);ctx.bezierCurveTo(-2,-13,-2,13,13,13);ctx.closePath();ctx.fillStyle=gold;ctx.fill();});glow(ctx,123,273,68,.08+.04*Math.sin(tau*phase),pink);}
      else for(let i=0;i<5;i++){const p=(phase+i/5)%1;star(ctx,29+i*38+4*Math.sin(tau*p),209-60*p,2.5+3*fade(p),.85*fade(p),i%2?pink:gold);}
    }else{
      const direction=state==='drag-right'?1:-1;
      const xAt=p=>112-direction*(42+57*p);
      if(!front){for(let band=0;band<2;band++){ctx.beginPath();for(let i=0;i<=40;i++){const p=i/40,x=xAt(p),y=243+band*9+Math.sin(tau*(p-phase))*7*(p+.2);i?ctx.lineTo(x,y):ctx.moveTo(x,y);}ctx.strokeStyle=band?gold:pink;ctx.globalAlpha=.7;ctx.lineWidth=band?1.5:2.3;ctx.stroke();ctx.globalAlpha=1;}}
      else for(let i=0;i<5;i++){const p=(phase+i/5)%1;heart(ctx,xAt(p),236+10*Math.sin(tau*(p-phase))+i%2*9,4+3*fade(p),.95*fade(p));star(ctx,xAt(p)+direction*6,254+4*Math.sin(tau*p),2.8,.8*fade(p));}
    }
    ctx.restore();
  }
  const api={draw,cycles,descriptions,setTextures};
  root.MagicalHeartPreviewEffects=api;
  if(typeof module!=='undefined'&&module.exports)module.exports=api;
})(typeof window!=='undefined'?window:globalThis);
