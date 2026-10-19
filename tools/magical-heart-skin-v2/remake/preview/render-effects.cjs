const fs=require('fs');
const path=require('path');
const crypto=require('crypto');
const {createCanvas,loadImage}=require('@napi-rs/canvas');
const fx=require('./effects.js');
const data=JSON.parse(fs.readFileSync(path.join(__dirname,'data.json'),'utf8'));
const output=path.join(__dirname,'effect-review');
fs.mkdirSync(output,{recursive:true});
const states=Object.keys(fx.cycles);
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const labels={idle:'기본',running:'작업',review:'검토',waiting:'대기',failed:'실패',waving:'완료',jumping:'점프',sleeping:'수면','drag-right':'오른쪽 이동','drag-left':'왼쪽 이동'};
async function main(){
  const materialImages=await Promise.all(['heart','petal','star','moon'].map(async key=>[key,await loadImage(path.join(__dirname,'material-assets',key+'.png'))]));materialImages.push(['scene',await loadImage(path.join(__dirname,'style-review-v9/effect.png'))]);fx.setTextures(Object.fromEntries(materialImages));
  const images=await Promise.all(states.map(state=>loadImage(path.join(__dirname,data.items.find(item=>item.state===state).src))));
  const artHashes=data.items.map(item=>({id:item.id,hash:hash(fs.readFileSync(path.join(__dirname,item.src)))}));
  const records=[];
  for(const state of states){
    const frameHashes=[];
    for(const t of [.21,.83,1.37]){
      const canvas=createCanvas(224,320),ctx=canvas.getContext('2d');
      fx.draw(ctx,state,t,false);fx.draw(ctx,state,t,true);
      frameHashes.push(hash(canvas.toBuffer('image/png')));
      if(!state.startsWith('drag')&&state!=='sleeping'){
        ctx.clearRect(0,0,224,320);fx.draw(ctx,state,t,true);
        const face=ctx.getImageData(43,66,143,117).data;
        for(let index=3;index<face.length;index+=4){if(face[index])throw new Error(state+': effect overlaps protected face area');}
      }
    }
    if(new Set(frameHashes).size!==3)throw new Error(state+': effect does not progress during static pose');
    records.push({state,cycle_seconds:fx.cycles[state],changing_effect_samples:3,character_pose:'static',front_face_exclusion:!state.startsWith('drag')&&state!=='sleeping'?'passed':'not applicable'});
  }
  const total=192,interval=.1;
  for(const theme of ['white','dark']){
    const folder=path.join(output,theme);fs.mkdirSync(folder,{recursive:true});
    for(let tick=0;tick<total;tick++){
      const canvas=createCanvas(1120,730),ctx=canvas.getContext('2d');
      ctx.fillStyle=theme==='white'?'#fffdfb':'#25232c';ctx.fillRect(0,0,1120,730);
      ctx.fillStyle=theme==='white'?'#674156':'#f5dbe6';ctx.font='16px sans-serif';
      ctx.fillText('Magical Heart · 정적 캐릭터 · 8개 상태 + 좌우 이동 이펙트',16,25);
      for(let i=0;i<states.length;i++){
        ctx.save();ctx.translate((i%5)*224,38+Math.floor(i/5)*346);
        const options=states[i]==='review'?{jewel:[95,206]}:states[i]==='waiting'?{jewel:[102,200]}:{};
        fx.draw(ctx,states[i],tick*interval,false,options);
        ctx.drawImage(images[i],0,0,224,320);
        fx.draw(ctx,states[i],tick*interval,true,options);
        ctx.fillStyle=theme==='white'?'#674156':'#f5dbe6';ctx.font='13px sans-serif';ctx.fillText(labels[states[i]],12,336);
        ctx.restore();
      }
      fs.writeFileSync(path.join(folder,String(tick).padStart(3,'0')+'.png'),canvas.toBuffer('image/png'));
    }
  }
  const afterHashes=data.items.map(item=>({id:item.id,hash:hash(fs.readFileSync(path.join(__dirname,item.src)))}));
  if(JSON.stringify(artHashes)!==JSON.stringify(afterHashes))throw new Error('Character art changed');
  fs.writeFileSync(path.join(output,'validation.json'),JSON.stringify({states:records,material_assets:materialImages.map(entry=>entry[0]),character_hashes_unchanged:true,character_motion_sequences_completed:0,export:{sampling_hz:10,duration_seconds:19.2,loop:true},html:{clock:'requestAnimationFrame elapsed time',character:'static',pause_and_visibility_controls:true}},null,2));
  console.log('PASS: 8 state and 2 directional effects progress with frozen character; front face exclusion; character hashes unchanged; 384 light/dark review boards exported.');
}
main().catch(error=>{console.error(error);process.exit(1);});
