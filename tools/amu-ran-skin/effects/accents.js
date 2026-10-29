// Same state/anchor/envelope contract as Python export and native AppKit.
function paintAccent(ctx,s,poseTime,gaze=false){
 if(gaze)return;const spec=interactionPlan.effects[String(s.row)];if(!spec||spec.strength===0)return;
 const phase=(Math.max(0,poseTime)/s.cycle)%1,d=Math.abs(phase-spec.peak),power=Math.pow(Math.max(0,1-Math.min(d,1-d)/spec.width),2)*spec.strength;
 if(power<.01)return;const[x,y]=spec.anchor;ctx.save();ctx.shadowColor=`rgba(255,82,154,${.5*power})`;ctx.shadowBlur=spec.mode==='ring'?6:8;ctx.lineWidth=2;
 const pink=a=>`rgba(255,82,154,${a*power/255})`;
 if(spec.mode==='ring'){for(let j=0;j<2;j++){ctx.strokeStyle=pink(150/(j+1));ctx.beginPath();ctx.ellipse(x,y,22+22*power+j*9,4+5*power+j*2,0,0,Math.PI*2);ctx.stroke()}}
 else{
  for(const[r,a]of[[18,45],[11,85],[4,200]]){ctx.fillStyle=pink(a);ctx.beginPath();ctx.arc(x,y,r,0,Math.PI*2);ctx.fill()}
  if(spec.mode==='signal')for(let j=0;j<2;j++){ctx.strokeStyle=pink(130);ctx.beginPath();ctx.arc(x,y,15+j*9+power*4,280*Math.PI/180,435*Math.PI/180);ctx.stroke()}
  for(let j=0;j<3;j++){const angle=(j-1)*.8,r=5+power*3,px=x+(x<224?-1:1)*Math.cos(angle)*(12+15*power),py=y+Math.sin(angle)*(12+15*power);ctx.beginPath();
   if(spec.mode==='glint'){ctx.fillStyle=`rgba(255,224,183,${245*power/255})`;ctx.moveTo(px,py-r);ctx.lineTo(px+r*.45,py);ctx.lineTo(px,py+r);ctx.lineTo(px-r*.45,py)}
   else{ctx.fillStyle=pink(245);for(let i=0;i<32;i++){const a=i*Math.PI*2/32,qx=px+r*Math.pow(Math.sin(a),3),qy=py-r*(13*Math.cos(a)-5*Math.cos(2*a)-2*Math.cos(3*a)-Math.cos(4*a))/16;i?ctx.lineTo(qx,qy):ctx.moveTo(qx,qy)}}ctx.closePath();ctx.fill()
  }
 }
 if(spec.mode!=='ring'){ctx.fillStyle=`rgba(255,244,250,${230*Math.min(1,power)/255})`;ctx.beginPath();ctx.moveTo(x,y-5);ctx.lineTo(x+2.5,y);ctx.lineTo(x,y+5);ctx.lineTo(x-2.5,y);ctx.closePath();ctx.fill()}
 ctx.restore();
}
