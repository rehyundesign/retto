const fs=require('fs'),path=require('path'),vm=require('vm'),crypto=require('crypto');
const dir=__dirname,root=path.dirname(dir),ctx={window:{}};
vm.runInNewContext(fs.readFileSync(root+'/state-integrated-v27-data.js','utf8'),ctx);
const rows=ctx.window.JeanneIntegrated19;
for(const id of ['waving','waiting']){
 const row=rows.find(r=>r.id===id);
 row.files=Array.from({length:16},(_,i)=>'drawn-inbetweens-v30/'+id+'/'+String(i).padStart(2,'0')+'.png');
 row.animations=['dark','white'].flatMap(theme=>['webp','gif'].map(ext=>({theme,file:'drawn-inbetweens-v30/'+id+'/animation-'+theme+'.'+ext})));
 row.status='16장 유지 · 중간 자세 다시 그림';
 row.note=id==='waving'?'낮게 앞발 들기 → 팔꿈치 굽히기 → 팬던트 접촉 → 앞발 인사 → 단계적으로 내리기 → 고개 인사.':'낮게 앞발 들기 → 팬던트로 가져오기 → 기도 → 팔꿈치를 펴며 앞발 내리기 → 접지.';
 delete row.times;
}
for(const row of rows)for(const file of row.files.concat(row.animations.map(a=>a.file)))if(!fs.existsSync(root+'/'+file))throw Error('Missing '+file);
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(root+'/'+f)).digest('hex');
const protectedFiles=JSON.parse(fs.readFileSync(root+'/registration-v27/source-lock.json')).filter(l=>!['waving','waiting'].includes(l.state));
for(const r of protectedFiles)if(hash(r.file)!==r.sha256)throw Error('Changed unrelated '+r.file);
const gazeLocks=JSON.parse(fs.readFileSync(root+'/completion-v26/lock.json')).filter(l=>l.file.startsWith('gaze-v25/'));
for(const r of gazeLocks)if(hash(r.file)!==r.hash)throw Error('Changed gaze '+r.file);
for(const r of JSON.parse(fs.readFileSync(dir+'/preserved-keys.json')))if(hash(r.file)!==r.sha256)throw Error('Changed key source '+r.file);
fs.writeFileSync(root+'/state-integrated-v30-data.js','window.JeanneIntegrated19='+JSON.stringify(rows)+';\n');
let html=fs.readFileSync(root+'/state-integrated-v27.html','utf8')
 .replace(/state-integrated-v27-data\.js\?v=\d+/,'state-integrated-v30-data.js?v='+Date.now())
 .replace('잔느 레토 · 완료와 입력 대기 수정','잔느 레토 · 중간 동작 다시 그리기')
 .replace('완료와 입력 대기의 레토·의상·핀·이펙트를 함께 그린 독립 프레임입니다. 다른 상태와 16방향 시선은 유지했습니다.','완료·입력대기의 프레임 수는 각각 16장으로 유지하고, 팔꿈치와 앞발의 이동 경로를 나눠 문제 있던 중간 컷을 새로 그렸습니다. 각 컷은 레토·의상·핀·이펙트를 함께 포함합니다. <a href="drawn-inbetweens-v30/jeanne-png-frames.zip">PNG 32장 받기</a>')
 .replace('완료·입력 대기 수정 · 다른 모션과 시선은 유지','중간 자세 재작화 · 다른 상태와 시선 유지 · 다른 상태와 시선 유지');
for(const m of html.matchAll(/<script>([\s\S]*?)<\/script>/g))new vm.Script(m[1]);
fs.writeFileSync(root+'/state-integrated-v30.html',html);
fs.writeFileSync(dir+'/preview-validation.json',JSON.stringify({htmlSyntax:'pass',allPathsExist:true,unaffectedImageHashesChecked:protectedFiles.length+gazeLocks.length,keySourcesUnchanged:17,nativePlayback:'not checked',originalAbsoluteRegistration:'not certified'},null,2));
console.log('10-state preview with2 repaired states; other128 image hashes unchanged');
