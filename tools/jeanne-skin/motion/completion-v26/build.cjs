const fs=require('fs'),path=require('path'),vm=require('vm'),crypto=require('crypto');
const sharp=require('/Users/luxia/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const dir=__dirname,root=path.dirname(dir),hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
(async()=>{
 const jobs=JSON.parse(fs.readFileSync(dir+'/jobs.json'));
 const records=[];
 for(const j of jobs){
  if(!fs.existsSync(j.dest))throw Error('Missing completion frame '+j.frame);
  const n=String(j.frame).padStart(2,'0'),meta=await sharp(j.dest).metadata();
  if(!meta.hasAlpha)throw Error('No alpha '+n);
  await sharp(j.dest).resize(448,640,{fit:'fill'}).png().toFile(dir+'/'+n+'.png');
  records.push({frame:j.frame,source:'completion-v26/'+n+'-source.png',file:'completion-v26/'+n+'.png',sha256:hash(j.dest),actionAndEffect:j.prompt});
 }
 if(new Set(records.map(r=>r.sha256)).size!==16)throw Error('Repeated source');
 for(const [theme,bg]of [['dark','#181827'],['white','#fffdf8']]){
  const tiles=await Promise.all(records.map(async(r)=>({input:await sharp(root+'/'+r.file).resize(224,320).png().toBuffer(),left:r.frame%4*224,top:Math.floor(r.frame/4)*320})));
  await sharp({create:{width:896,height:1280,channels:4,background:bg}}).composite(tiles).png().toFile(dir+'/review-'+theme+'.png');
 }
 const locks=JSON.parse(fs.readFileSync(dir+'/lock.json'));
 for(const l of locks)if(hash(root+'/'+l.file)!==l.hash)throw Error('Unrelated source changed '+l.file);
 const ctx={window:{}};vm.runInNewContext(fs.readFileSync(root+'/state-integrated-v25-data.js','utf8'),ctx);
 const rows=ctx.window.JeanneIntegrated19,row=rows.find(r=>r.id==='waving');
 row.files=records.map(r=>r.file);row.cycle=2.4;delete row.times;
 row.status='완료 인사 · 동작과 이펙트 16장 새로 생성';
 row.note='로사리오를 만짐 → 빛과 리본 확산 → 앞발 인사 → 짧은 고개 인사 → 회복. 핀과 깃털도 같은 흐름으로 움직입니다.';
 row.animations=['dark','white'].map(theme=>({theme,file:'completion-v26/animation-'+theme+'.webp'}));
 fs.writeFileSync(dir+'/rows.json',JSON.stringify(rows,null,2));
 fs.writeFileSync(root+'/state-integrated-v26-data.js','window.JeanneIntegrated19='+JSON.stringify(rows)+';\n');
 let html=fs.readFileSync(root+'/state-integrated-v25.html','utf8')
  .replace(/state-integrated-v25-data\.js\?v=\d+/,'state-integrated-v26-data.js?v='+Date.now())
  .replace('잔느 레토 · 모션과 16방향 시선','잔느 레토 · 완료 인사 다시 생성')
  .replace('v24의 10개 상태 모션에 마우스를 따라보는 16방향 시선을 추가했습니다. 좌우 드래그는 일단 사용하기로 한 v24 그림을 유지합니다.','완료 인사의 동작과 이펙트를 다시 생성했습니다. 준비 → 로사리오 반응 → 승리 인사 → 고개 인사 → 회복으로 이어집니다.')
  .replace("rows.findIndex(r=>r.id==='idle')","rows.findIndex(r=>r.id==='waving')")
  .replace('16방향 시선 추가 · 좌우 보행은 각각 8개 원본 자세','완료 인사 새 16장 · 다른 모션과 시선은 유지');
 for(const m of html.matchAll(/<script>([\s\S]*?)<\/script>/g))new vm.Script(m[1]);
 fs.writeFileSync(root+'/state-integrated-v26.html',html);
 fs.writeFileSync(dir+'/manifest.json',JSON.stringify({state:'waving',cycle:2.4,intervalMs:150,independentSources:16,frames:records,unaffectedSourceLocks:locks.length,integrated:true,originalRegistration:'not certified',nativePlayback:'not checked'},null,2));
 console.log('Completion16 sources built; all144 other-state/gaze images unchanged.');
})();
