const fs=require('fs'),path=require('path'),vm=require('vm'),crypto=require('crypto');
const dir=__dirname,root=path.dirname(dir),ctx={window:{}};
vm.runInNewContext(fs.readFileSync(root+'/state-integrated-v26-data.js','utf8'),ctx);
const rows=ctx.window.JeanneIntegrated19;
for(const id of ['waving','waiting']){
 const row=rows.find(r=>r.id===id);
 row.files=Array.from({length:16},(_,i)=>'integrated-repair-v27/'+id+'/'+String(i).padStart(2,'0')+'.png');
 row.animations=['dark','white'].flatMap(theme=>['webp','gif'].map(ext=>({theme,file:'integrated-repair-v27/'+id+'/animation-'+theme+'.'+ext})));
 row.status='완성 이미지 16장 · 크기와 위치 수정';
 row.note=id==='waving'?'로사리오 반응 → 앞발 인사 → 고개 인사 → 회복.':'앉은 자세에서 앞발 하나로 로사리오를 만지고 핀을 바라봅니다.';
}
for(const row of rows)for(const file of row.files.concat(row.animations.map(a=>a.file)))if(!fs.existsSync(root+'/'+file))throw Error('Missing '+file);
fs.writeFileSync(root+'/state-integrated-v27-data.js','window.JeanneIntegrated19='+JSON.stringify(rows)+';\n');
let html=fs.readFileSync(root+'/state-integrated-v26.html','utf8')
 .replace(/state-integrated-v26-data\.js\?v=\d+/,'state-integrated-v27-data.js?v='+Date.now())
 .replace('잔느 레토 · 완료 인사 다시 생성','잔느 레토 · 완료와 입력 대기 수정')
 .replace('완료 인사의 동작과 이펙트를 다시 생성했습니다. 준비 → 로사리오 반응 → 승리 인사 → 고개 인사 → 회복으로 이어집니다.','완료와 입력 대기의 레토·의상·핀·이펙트를 함께 그린 독립 프레임입니다. 다른 상태와 16방향 시선은 유지했습니다.')
 .replace('완료 인사 새 16장 · 다른 모션과 시선은 유지','완료·입력 대기 수정 · 다른 모션과 시선은 유지')
 .replace("link.textContent='모션 이미지 · '+(a.theme==='dark'?'어두운 배경':'흰 배경')", "link.textContent=(a.file.endsWith('.gif')?'GIF':'WebP')+' · '+(a.theme==='dark'?'어두운 배경':'흰 배경')");
for(const m of html.matchAll(/<script>([\s\S]*?)<\/script>/g))new vm.Script(m[1]);
fs.writeFileSync(root+'/state-integrated-v27.html',html);
const oldLocks=JSON.parse(fs.readFileSync(root+'/registration-v27/source-lock.json'));
const check=[];
for(const l of oldLocks){if(['waving','waiting'].includes(l.state))continue;const hash=crypto.createHash('sha256').update(fs.readFileSync(root+'/'+l.file)).digest('hex');if(hash!==(l.hash||l.sha256))throw Error('Changed unrelated '+l.file);check.push(l.file);}
const gazeLocks=JSON.parse(fs.readFileSync(root+'/completion-v26/lock.json')).filter(l=>l.file.startsWith('gaze-v25/'));
if(gazeLocks.length!==16)throw Error('Gaze lock count');
for(const l of gazeLocks){const hash=crypto.createHash('sha256').update(fs.readFileSync(root+'/'+l.file)).digest('hex');if(hash!==l.hash)throw Error('Changed gaze '+l.file);check.push(l.file);}
fs.writeFileSync(dir+'/preview-validation.json',JSON.stringify({htmlInlineScriptSyntax:'pass',allPathsExist:true,unaffectedFilesChecked:check.length,nativePlayback:'not checked',originalAbsoluteRegistration:'not certified'},null,2));
console.log('Preview paths and script syntax verified');
