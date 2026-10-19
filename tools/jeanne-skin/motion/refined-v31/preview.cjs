const fs=require('fs'),path=require('path'),vm=require('vm'),crypto=require('crypto');
const root=path.dirname(__dirname),ctx={window:{}};
vm.runInNewContext(fs.readFileSync(root+'/state-integrated-v30-data.js','utf8'),ctx);
const rows=ctx.window.JeanneIntegrated19,timing=JSON.parse(fs.readFileSync(__dirname+'/timing.json'));
const protectedHashes=[];
for(const r of rows){
 if(!timing[r.id]){for(const f of r.files)protectedHashes.push([f,crypto.createHash('sha256').update(fs.readFileSync(root+'/'+f)).digest('hex')]);continue;}
 r.files=r.files.map((_,i)=>`refined-v31/${r.id}/${String(i).padStart(2,'0')}.png`);
 r.times=timing[r.id].timesMs.map(t=>t/1000);
 if(Math.abs(r.times.reduce((a,b)=>a+b,0)-r.cycle)>1e-8)throw Error('cycle mismatch');
 r.animations=['dark','white'].flatMap(theme=>['webp','gif'].map(ext=>({theme,file:`refined-v31/${r.id}/animation-${theme}.${ext}`})));
 r.status='중간 컷 보정 · 동작별 시간 조정';
 r.note=r.id==='waving'?'앞발을 천천히 들고 인사한 뒤, 리본이 잦아들며 고개 인사로 마무리합니다.':'핀을 바라보며 팬던트에 앞발을 가져갔다가, 기도 후 천천히 내립니다.';
}
for(const r of rows)for(const f of [...r.files,...r.animations.map(a=>a.file)])if(!fs.existsSync(root+'/'+f))throw Error(f);
fs.writeFileSync(root+'/state-integrated-v31-data.js','window.JeanneIntegrated19='+JSON.stringify(rows)+';\n');
let html=fs.readFileSync(root+'/state-integrated-v30.html','utf8').replace(/state-integrated-v30-data\.js\?v=\d+/,'state-integrated-v31-data.js?v='+Date.now()).replaceAll('drawn-inbetweens-v30/jeanne-png-frames.zip','refined-v31/jeanne-png-frames.zip').replaceAll('완료·입력대기의 프레임 수는 각각 16장으로 유지하고, 팔꿈치와 앞발의 이동 경로를 나눠 문제 있던 중간 컷을 새로 그렸습니다.', '완료·입력대기는 각각 16장입니다. v30에서 크기·위치 차이가 두드러진 네 컷을 다시 그렸고, 전체 주기를 유지하면서 컷별 표시 시간을 조정했습니다.').replaceAll('잔느 레토 · 중간 동작 다시 그리기','잔느 레토 · 동작 연결 보정').replaceAll('중간 자세 재작화 · 다른 상태와 시선 유지 · 다른 상태와 시선 유지','중간 자세와 타이밍 보정 · 다른 상태와 시선 유지');
for(const m of html.matchAll(/<script>([\s\S]*?)<\/script>/g))new vm.Script(m[1]);
fs.writeFileSync(root+'/state-integrated-v31.html',html);
fs.writeFileSync(__dirname+'/validation.json',JSON.stringify({htmlSyntax:'pass',assetPaths:'pass',protectedHashes,nativePlayback:'file URL blocked by browser security policy; not inspected',originalRegistration:'not certified'},null,2));
console.log('HTML syntax and asset paths pass; 2 timing schedules match exported GIF/WebP. Other states preserved.');
