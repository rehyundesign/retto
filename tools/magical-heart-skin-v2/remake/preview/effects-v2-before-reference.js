(function (root) {
  'use strict';
  const cycles = {idle:3.2, running:2.4, review:3.2, waiting:3.2, failed:3.2, waving:2.4, jumping:2.4, sleeping:6.4, 'drag-right':1.6, 'drag-left':1.6};
  const descriptions = {
    idle:'브로치의 작은 하트와 은은한 금빛 반짝임',
    running:'앞발 사이에서 모이는 하트 마법과 회전하는 마법진',
    review:'보석에 반응하는 푸른 빛과 짧은 꽃잎 고리',
    waiting:'사용자에게 향하는 하트 신호와 부드러운 호출 고리',
    failed:'흩어진 마법 조각이 다시 작은 하트로 모이는 회복',
    waving:'앞발에서 날아가는 키스 하트와 금빛 궤적',
    jumping:'상승하는 꽃잎 궤적과 퍼지는 착지 고리',
    sleeping:'초승달 아래 느리게 흐르는 별과 수면 빛',
    'drag-right':'왼쪽 뒤로 흐르는 하트 리본과 이동 궤적',
    'drag-left':'오른쪽 뒤로 흐르는 하트 리본과 이동 궤적'
  };
  const pink='#ea4b89', deep='#bc285b', gold='#c59635', ivory='#ffddac', blue='#489ad7';
  const tau=Math.PI*2;
  function local(ctx,x,y,alpha,fn){ctx.save();ctx.translate(x,y);ctx.globalAlpha*=Math.max(0,Math.min(1,alpha));fn();ctx.restore();}
  function heart(ctx,x,y,r,alpha=1,outline=false,color=pink){
    local(ctx,x,y,alpha,()=>{ctx.beginPath();ctx.moveTo(0,r*.7);ctx.bezierCurveTo(-r*1.5,-r*.1,-r*.8,-r*1.3,0,-r*.48);ctx.bezierCurveTo(r*.8,-r*1.3,r*1.5,-r*.1,0,r*.7);ctx.closePath();ctx.fillStyle=color;ctx.strokeStyle=outline?color:gold;ctx.lineWidth=outline?1.5:.8;if(!outline)ctx.fill();ctx.stroke();});
  }
  function star(ctx,x,y,r,alpha,color=gold){local(ctx,x,y,alpha,()=>{ctx.beginPath();for(let i=0;i<8;i++){const a=i*Math.PI/4,d=i%2?r*.22:r;const px=Math.sin(a)*d,py=Math.cos(a)*d;i?ctx.lineTo(px,py):ctx.moveTo(px,py);}ctx.closePath();ctx.fillStyle=color;ctx.fill();});}
  function ring(ctx,x,y,rx,ry,alpha,color=gold){local(ctx,x,y,alpha,()=>{ctx.beginPath();ctx.ellipse(0,0,rx,ry,0,0,tau);ctx.strokeStyle=color;ctx.lineWidth=1.3;ctx.stroke();});}
  function glow(ctx,x,y,r,alpha,color){local(ctx,x,y,alpha,()=>{const g=ctx.createRadialGradient(0,0,0,0,0,r);g.addColorStop(0,color);g.addColorStop(1,'rgba(255,230,242,0)');ctx.fillStyle=g;ctx.fillRect(-r,-r,r*2,r*2);});}
  function petal(ctx,x,y,r,angle,alpha){local(ctx,x,y,alpha,()=>{ctx.rotate(angle);ctx.beginPath();ctx.moveTo(0,-r);ctx.bezierCurveTo(r*1.3,0,r*.65,r,0,r);ctx.bezierCurveTo(-r*.65,r,-r*1.3,0,0,-r);ctx.fillStyle='#f8c4d7';ctx.fill();ctx.strokeStyle=gold;ctx.lineWidth=.4;ctx.stroke();});}
  const fade=p=>Math.sin(Math.PI*p)**2;
  function draw(ctx,state,time,front,options={}){
    if(!(state in cycles))throw new Error('Unknown Magical Heart effect state: '+state);
    const t=Math.max(0,time), phase=(t/cycles[state])%1;
    const jewel=options.jewel||[112,204], spell=options.spell||[112,250];
    ctx.save();ctx.beginPath();ctx.rect(6,6,212,308);ctx.clip();
    if(front && !state.startsWith('drag') && state!=='sleeping'){
      // Keep foreground particles outside the face; back effects remain behind it.
      ctx.beginPath();ctx.rect(0,0,224,320);ctx.rect(42,65,145,119);ctx.clip('evenodd');
    }
    if(state==='idle'){
      if(!front){glow(ctx,112,242,65,.09+.025*Math.sin(tau*phase),pink);}
      else for(let i=0;i<4;i++){const p=(phase+i/4)%1,s=i%2?1:-1;heart(ctx,112+s*(89+3*Math.sin(tau*p)),255-p*60,4.5+2*fade(p),.95*fade(p));star(ctx,112-s*86,225-p*36,3.5,.8*fade(p));}
    }else if(state==='running'){
      if(!front){ring(ctx,112,232,90,65,.7);ring(ctx,112,270,85,19,.65,pink);for(let i=0;i<8;i++){const a=tau*(phase+i/8);star(ctx,112+90*Math.cos(a),232+65*Math.sin(a),i%2?2.5:4,.9);}}
      else{const pulse=.65+.2*Math.sin(tau*phase);glow(ctx,...spell,29,.4,pink);heart(ctx,...spell,10+3*pulse,.95);for(let i=0;i<5;i++){const a=tau*(phase+i/5);star(ctx,spell[0]+23*Math.cos(a),spell[1]+16*Math.sin(a),3.5,.85,i%2?pink:gold);}}
    }else if(state==='review'){
      if(!front){for(let i=0;i<6;i++){const a=tau*(i/6+.06*Math.sin(tau*phase));petal(ctx,112+82*Math.cos(a),282+8*Math.sin(a),4,a,.6);}}
      else{for(let i=0;i<3;i++){const p=(phase+i/3)%1;star(ctx,26+3*Math.sin(tau*p),242-45*p,3+3*fade(p),.85*fade(p),blue);}glow(ctx,...jewel,22,.42,blue);star(ctx,...jewel,6+3*fade(phase),.95,blue);for(let i=0;i<2;i++){const p=(phase+i*.5)%1;ring(ctx,...jewel,4+15*p,2+5*p,.9*fade(p),blue);star(ctx,jewel[0]+19*Math.cos(tau*p),jewel[1]+9*Math.sin(tau*p),1.8,.65*fade(p),ivory);}}
    }else if(state==='waiting'){
      if(!front){for(let i=0;i<3;i++){const p=(phase+i/3)%1;ring(ctx,112,266,38+54*p,9+16*p,.7*fade(p),pink);}}
      else for(let i=0;i<4;i++){const p=(phase+i/4)%1;const x=131+68*p,y=227-24*Math.sin(Math.PI*p);heart(ctx,x,y,4+3*fade(p),.95*fade(p),i%2===1);star(ctx,x-5,y+7,2.5,.8*fade(p));}
    }else if(state==='failed'){
      if(!front){glow(ctx,112,257,53,.08,pink);}
      else if(phase<.48){const p=phase/.48;for(let i=0;i<7;i++){const a=tau*i/7;star(ctx,spell[0]+(10+76*p)*Math.cos(a),spell[1]+(8+33*p)*Math.sin(a),4.5*(1-p),.95*fade(p),i%2?blue:gold);}heart(ctx,spell[0]-8*p,spell[1]+10*p,4,.55*fade(p),true);heart(ctx,197-4*p,224+9*p,7,.9*fade(p),true);}
      else{const p=(phase-.48)/.52;heart(ctx,...spell,6+5*Math.sin(Math.PI*p),.95*fade(p));heart(ctx,199,224,7+2*fade(p),.9*fade(p));for(let i=0;i<4;i++){const a=tau*i/4;star(ctx,spell[0]+22*(1-p)*Math.cos(a),spell[1]+12*(1-p)*Math.sin(a),2.8,.85*fade(p));}}
    }else if(state==='waving'){
      if(!front){ring(ctx,112,280,85,16,.4+.2*fade(phase),pink);}
      else for(let i=0;i<5;i++){const p=(phase+i/5)%1;const x=25+38*Math.exp(-22*p),y=194-145*p;heart(ctx,x,y,5+4*fade(p),.95*fade(p),false,i%2?pink:deep);star(ctx,x+8,y+11,2.8,.85*fade(p));}
    }else if(state==='jumping'){
      if(!front){for(let i=0;i<8;i++){const p=(phase+i/8)%1,a=tau*p+Math.PI*i;petal(ctx,112+Math.cos(a)*(80+7*p),292-150*p,4+2*fade(p),a,.9*fade(p));}}
      else{for(let i=0;i<4;i++){const q=(phase+i/4)%1;petal(ctx,i%2?201:25,286-140*q,4+2*fade(q),tau*q,.85*fade(q));}const p=(phase+.3)%1;const pulse=Math.sin(Math.PI*Math.min(1,p/.15)/2)*(1-p);ring(ctx,112,299,19+65*p,3+12*p,.95*pulse,pink);ring(ctx,112,299,15+53*p,2+9*p,.7*pulse,gold);for(let i=0;i<5;i++){const a=Math.PI*i/4;star(ctx,112+Math.cos(a)*70,296-Math.sin(a)*18,2,.6*fade(p));}}
    }else if(state==='sleeping'){
      if(!front){local(ctx,172,177,.85,()=>{ctx.beginPath();ctx.arc(0,0,18,Math.PI*.25,Math.PI*1.75);ctx.bezierCurveTo(-2,-13,-2,13,13,13);ctx.closePath();ctx.fillStyle=gold;ctx.fill();});glow(ctx,123,273,68,.08+.04*Math.sin(tau*phase),pink);}
      else for(let i=0;i<5;i++){const p=(phase+i/5)%1;star(ctx,29+i*38+4*Math.sin(tau*p),209-60*p,2.5+3*fade(p),.85*fade(p),i%2?pink:gold);}
    }else{
      const direction=state==='drag-right'?1:-1;
      const xAt=p=>112-direction*(42+57*p);
      if(!front){for(let band=0;band<2;band++){ctx.beginPath();for(let i=0;i<=40;i++){const p=i/40,x=xAt(p),y=243+band*9+Math.sin(tau*(p-phase))*7*(p+.2);i?ctx.lineTo(x,y):ctx.moveTo(x,y);}ctx.strokeStyle=band?gold:pink;ctx.globalAlpha=.7;ctx.lineWidth=band?1.5:2.3;ctx.stroke();ctx.globalAlpha=1;}}
      else for(let i=0;i<5;i++){const p=(phase+i/5)%1;heart(ctx,xAt(p),236+10*Math.sin(tau*(p-phase))+i%2*9,4+3*fade(p),.95*fade(p));star(ctx,xAt(p)+direction*6,254+4*Math.sin(tau*p),2.8,.8*fade(p));}
    }
    ctx.restore();
  }
  const api={draw,cycles,descriptions};
  root.MagicalHeartPreviewEffects=api;
  if(typeof module!=='undefined'&&module.exports)module.exports=api;
})(typeof window!=='undefined'?window:globalThis);
