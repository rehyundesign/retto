const fs=require('fs'),path=require('path'),crypto=require('crypto'),vm=require('vm');
const sharp=require('/Users/luxia/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root=__dirname,m=JSON.parse(fs.readFileSync(path.join(root,'manifest.json'))),lock=JSON.parse(fs.readFileSync(path.join(root,'../effects-v36/approved-motion-lock.json')));
function assert(v,msg){if(!v)throw Error(msg)}
async function main(){
 assert(m.states.length===10,'10 states');let characters=0,effects=0;
 const rows={idle:0,'drag-right':1,'drag-left':2,waving:3,jumping:4,failed:5,waiting:6,running:7,review:8,sleeping:11};
 for(const s of m.states){
  const old=lock.states.find(x=>x.id===s.id);assert(s.row===rows[s.id],s.id+' row');assert(JSON.stringify(s.times)===JSON.stringify(old.times),s.id+' timing changed');assert(s.cycle===old.cycle,s.id+' cycle changed');
  assert(s.characters.length===(s.id.startsWith('drag')?8:16),s.id+' count');assert(s.ready,s.id+' not ready');
  assert(Math.abs(s.effects.length*s.effectInterval-s.effectCycle)<1e-6,s.id+' FX duration');assert(s.anchors.every(Boolean),s.id+' missing Rosario anchor');
  const hashes=[];
  for(const f of s.characters){const p=path.join(root,f),meta=await sharp(p).metadata();assert(meta.width===448&&meta.height===640&&meta.hasAlpha,f+' dimensions/alpha');hashes.push(crypto.createHash('sha256').update(await sharp(p).raw().toBuffer()).digest('hex'));characters++}
  assert(new Set(hashes).size===hashes.length,s.id+' duplicate character images');
  for(const e of s.effects)for(const f of [e.back,e.front]){assert(fs.existsSync(path.join(root,f)),f+' missing');effects++}
  const frozenA=s.effects[Math.floor(.35/s.effectInterval)%s.effects.length],frozenB=s.effects[Math.floor(1.15/s.effectInterval)%s.effects.length];assert(!fs.readFileSync(path.join(root,frozenA.front)).equals(fs.readFileSync(path.join(root,frozenB.front))),s.id+' frozen FX');
 }
 // Run the actual preview controller with a small DOM/image harness.
 const el=new Map(),callbacks=[],drawCalls=[];
 function element(id){if(!el.has(id))el.set(id,{id,checked:['effects'].includes(id),value:'1',classList:{toggle(){}},append(){},getContext(){return {clearRect(){},drawImage(im,...args){drawCalls.push({src:im.src,args})},globalAlpha:1}},textContent:''});return el.get(id)}
 class Img{set src(v){this._src=v;assert(fs.existsSync(path.join(root,v)),'preview missing '+v);if(this.onload)this.onload()}get src(){return this._src}}
 const ctx={window:{JEANNE_V38:m},document:{getElementById:element,createElement:()=>({dataset:{},classList:{toggle(){}},textContent:''}),querySelectorAll:()=>[]},performance:{now:()=>0},requestAnimationFrame:f=>callbacks.push(f),Image:Img};
 vm.runInNewContext(fs.readFileSync(path.join(root,'preview.js'),'utf8'),ctx);
 for(let i=0;i<180;i++){const f=callbacks.shift();assert(f,'animation stopped');f(i*50)}
 element('freeze').checked=true;element('freeze').onchange();let before=drawCalls.length;
 for(let i=180;i<200;i++)callbacks.shift()(i*50);
 const held=drawCalls.slice(before).filter(x=>x.src.includes('characters/')).map(x=>x.src);assert(new Set(held).size===1,'frozen character changed');
 const fx=drawCalls.slice(before).filter(x=>x.src.includes('effects/')).map(x=>x.src);assert(new Set(fx).size>4,'effects froze with character');
 assert(characters===144,'total characters');const report={characters,effectPngs:effects,states:10,sourceTimingPreserved:true,rowsVerified:true,previewController:'passed with DOM/image harness',frozenPoseEffects:'passed',browserVisualQA:'not performed',nativeInstalled:false};
 fs.writeFileSync(path.join(root,'validation.json'),JSON.stringify(report,null,2));console.log(report);
}
main().catch(e=>{console.error(e);process.exitCode=1});
