const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const sharp=require('/Users/luxia/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root=__dirname,hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const states=JSON.parse(fs.readFileSync(path.join(root,'delivery-map.json'))).states;
const times=[.3,.3,.3,.3,.3,.07,.07,.05,.04,.05,.06,.07,.3,.3,.3,.39];
const extras=[['charge','봉인 · 힘 모으기','running','11-running-charge.png'],['release','봉인 · 힘 펼치기','running','12-running-release.png'],['focus','검토 · 집중','review','13-review-focus.png'],['bow','완료 · 인사 마무리','waving','14-waving-bow.png'],['jump-prep','점프 · 준비 자세','jumping','15-jump-prep.png'],['sleep-settle','수면 · 자리 잡기','sleeping','16-sleep-settle.png']];
const records=[];
const generatedRoot=path.join(root,'state-direct-v1');
const generatedFiles=id=>fs.existsSync(path.join(generatedRoot,id))?fs.readdirSync(path.join(generatedRoot,id)).filter(f=>/^\d{2}\.png$/.test(f)).sort():[];
const softTailReady=Array.from({length:16},(_,i)=>path.join(root,'idle-direct-v5',`idle-${String(i).padStart(2,'0')}.png`)).every(f=>fs.existsSync(f));
const expected={idle:[98,220],running:[106,175],review:[98,175],waiting:[89,171],failed:[68,200],waving:[98,170],jumping:[118,209],sleeping:[91,207],'drag-right':[175,216],'drag-left':[58,203],charge:[94,171],release:[108,166],focus:[93,178],bow:[99,188],'jump-prep':[126,228],'sleep-settle':[91,186]};
async function attachment(file,id){
  const pixels=await sharp(path.join(root,file)).resize(224,320).ensureAlpha().raw().toBuffer(),[ex,ey]=expected[id],mask=new Uint8Array(224*320),seen=new Uint8Array(224*320);let best=[],bestScore=Infinity;
  for(let y=Math.max(0,ey-35);y<Math.min(320,ey+35);y++)for(let x=Math.max(0,ex-35);x<Math.min(224,ex+35);x++){
    const p=(y*224+x)*4,r=pixels[p],g=pixels[p+1],b=pixels[p+2];if(r>140&&b>105&&r-g>20&&b-g>10&&r-b>8&&pixels[p+3]>150)mask[y*224+x]=1;
  }
  for(let i=0;i<mask.length;i++)if(mask[i]&&!seen[i]){
    const stack=[i],part=[];seen[i]=1;
    while(stack.length){const k=stack.pop(),x=k%224,y=Math.floor(k/224);part.push(k);for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){const nx=x+dx,ny=y+dy,j=ny*224+nx;if(nx>=0&&nx<224&&ny>=0&&ny<320&&mask[j]&&!seen[j]){seen[j]=1;stack.push(j)}}}
    const xs=part.map(k=>k%224),ys=part.map(k=>Math.floor(k/224)),w=Math.max(...xs)-Math.min(...xs)+1,h=Math.max(...ys)-Math.min(...ys)+1,cx=(Math.max(...xs)+Math.min(...xs))/2,cy=(Math.max(...ys)+Math.min(...ys))/2,score=Math.hypot(cx-ex,cy-ey)-Math.min(5,part.length*.08);if(part.length>=2&&w<=22&&h<=22&&score<bestScore){best=part;bestScore=score;}
  }
  if(best.length<2)return{x:ex,y:ey,visible:false};const xs=best.map(k=>k%224),ys=best.map(k=>Math.floor(k/224));return{x:(Math.min(...xs)+Math.max(...xs))/2,y:(Math.min(...ys)+Math.max(...ys))/2,visible:true};
}
async function cache(source,id,index){
  const sourceFile=path.join(root,source),input=fs.readFileSync(sourceFile),folder=path.join(root,'latest-preview-assets',id);fs.mkdirSync(folder,{recursive:true});
  const target=path.join(folder,`${index}.png`);
  await sharp(input).resize(448,640,{fit:'contain',background:'#00000000'}).png().toFile(target);
  records.push({source,hash:hash(input),preview:path.relative(root,target)});return path.relative(root,target);
}
(async()=>{
  const rows=[];
  for(const s of states){
    const files=[];
    if(s.id==='idle')for(let i=0;i<16;i++)files.push(await cache(`${softTailReady?'idle-direct-v5':'idle-direct-v4'}/idle-${String(i).padStart(2,'0')}${!softTailReady&&[1,2].includes(i)?'-refined':''}.png`,s.id,i));
    else {const generated=generatedFiles(s.id);if(generated.length>1)for(const f of generated)files.push(await cache(`state-direct-v1/${s.id}/${f}`,s.id,f.slice(0,2)));else files.push(await cache(`masters/${s.id}.png`,s.id,0));}
    const trials=[];
    if(['running','review','waiting'].includes(s.id))for(let i=0;i<4;i++)trials.push(await cache(`production-raw/${s.id}-${String(i).padStart(2,'0')}.png`,s.id,'trial-'+i));
    rows.push({id:s.id,label:s.label,state:s.id,files,trials,times:s.id==='idle'?times:null,cycle:s.cycle,kind:'state',status:s.id==='idle'?'16장 캐릭터 모션 · 빠른 깜빡임':files.length>1?`${files.length}/16장 새 캐릭터 모션 · 검수용`:'승인 정지 포즈 · 이펙트 재생',note:s.id==='idle'?(softTailReady?'꼬리는 쉬는 형태로 재생성했습니다. 일부 프레임의 위치와 꼬리 연결은 추가 보정이 필요합니다.':'꼬리 진폭 축소는 이미지 생성 한도 해제 후 재생성 예정입니다.'):files.length>1?'의상·포즈·레토·핀을 함께 생성한 독립 그림입니다. 최종 연결과 원본 크기 검증이 남아 있습니다.':'캐릭터 16장 모션은 아직 제작 전입니다.'});
  }
  for(const [id,label,state,file]of extras){rows.push({id,label,state,files:[await cache('masters/'+file,id,0)],trials:[],cycle:3.2,times:null,kind:'key',status:'상태 안의 추가 핵심 포즈 · 이펙트 재생',note:'새 런타임 상태가 아닌, 각 동작에 사용할 다른 자세입니다.'})}
  for(const r of rows){if(r.id!=='idle'&&generatedFiles(r.id).length>1){const points={running:[98,220],review:[105,213],waiting:[105,208],failed:[88,226],waving:[97,207],jumping:[150,239],sleeping:[143,280],'drag-right':[140,246],'drag-left':[63,243]};expected[r.id]=points[r.id];}r.anchors=[];for(const f of r.files)r.anchors.push(await attachment(f,r.id));r.trialAnchors=[];for(const f of r.trials)r.trialAnchors.push(await attachment(f,r.id));}
  const exportedPath=path.join(root,'state-direct-v1','export-validation.json');const exported=fs.existsSync(exportedPath)?JSON.parse(fs.readFileSync(exportedPath)):[];for(const r of rows){r.animations=[];if(r.id==='idle'){for(const theme of ['dark','white']){const f='latest-idle-'+theme+'.webp';if(fs.existsSync(path.join(root,f)))r.animations.push({theme,file:f});}}else {const e=exported.find(e=>e.state===r.id);if(e&&e.drawings===r.files.length&&e.previewFiles&&e.previewFiles.every((f,i)=>f===r.files[i]&&e.previewHashes[i]===hash(fs.readFileSync(path.join(root,f)))))for(const theme of ['dark','white']){const f='state-direct-v1/'+r.id+'-'+theme+'.webp';if(fs.existsSync(path.join(root,f)))r.animations.push({theme,file:f});}}}
  fs.writeFileSync(path.join(root,'latest-motion-data.js'),'window.JeanneLatestData='+JSON.stringify(rows)+';\n');
  for(const r of records)if(hash(fs.readFileSync(path.join(root,r.source)))!==r.hash)throw Error('changed character source');
  fs.writeFileSync(path.join(root,'latest-source-lock.json'),JSON.stringify({records,characterSourcesUnchanged:true,blinkSeconds:times.slice(5,12).reduce((a,b)=>a+b,0),idleCycleSeconds:times.reduce((a,b)=>a+b,0),tailRepair:softTailReady?'16 complete whole drawings ready for visual review':'pending image generation limit reset'},null,2));
  console.log(rows.length+' items prepared; whole character sources preserved');
})().catch(e=>{console.error(e);process.exit(1)});
