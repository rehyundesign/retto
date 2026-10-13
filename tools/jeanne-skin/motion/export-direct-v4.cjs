const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const sharp=require('/Users/luxia/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const effects=require('./idle-effects-v3.js');
const root=__dirname,dir=path.join(root,'idle-direct-v4');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
  const chars=[],records=[];
  for(let i=0;i<16;i++){
    const refined=path.join(dir,`idle-${String(i).padStart(2,'0')}-refined.png`);
    const file=fs.existsSync(refined)?refined:path.join(dir,`idle-${String(i).padStart(2,'0')}.png`),source=fs.readFileSync(file);
    const resized=await sharp(source).resize(224,320,{fit:'contain',background:'#00000000'}).png().toBuffer();
    const pixels=await sharp(resized).ensureAlpha().raw().toBuffer();
    chars.push(resized);records.push({frame:i,source:file,sourceHash:hash(source),decodedHash:hash(pixels),production:'single complete image generation; no clothing or anatomy patch composition'});
  }
  if(new Set(records.map(r=>r.sourceHash)).size!==16||new Set(records.map(r=>r.decodedHash)).size!==16)throw Error('duplicate drawings');
  const cache=[];
  for(let i=0;i<80;i++){
    const e=effects.render('idle',i/10,0);
    const back=await sharp(Buffer.from(e.back)).png().toBuffer(),front=await sharp(Buffer.from(e.front)).png().toBuffer();
    cache.push({back,front});
    for(const layer of [back,front]){
      const pixels=await sharp(layer).ensureAlpha().raw().toBuffer();let minX=224,minY=320,maxX=-1,maxY=-1;
      for(let y=0;y<320;y++)for(let x=0;x<224;x++)if(pixels[(y*224+x)*4+3]>4){minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y)}
      if(maxX>=0&&(minX<6||minY<6||maxX>217||maxY>313))throw Error('effect margin '+[i,minX,minY,maxX,maxY]);
    }
  }
  if(hash(cache[0].front)===hash(cache[9].front)||hash(cache[0].back)===hash(cache[9].back))throw Error('frozen effects');
  const palette=[['dark','#181827'],['white','#fffdf8']];
  for(const [name,bg] of palette){
    const exportDir=path.join(root,`direct-v4-export-${name}`);fs.mkdirSync(exportDir,{recursive:true});
    for(let i=0;i<160;i++){
      const pose=Math.floor(i/2)%16,e=cache[i%80];
      await sharp({create:{width:224,height:320,channels:4,background:bg}}).composite([{input:e.back},{input:chars[pose]},{input:e.front}]).png().toFile(path.join(exportDir,`${String(i).padStart(3,'0')}.png`));
    }
    const placements=[];
    for(let i=0;i<16;i++){
      placements.push({input:chars[i],left:(i%4)*224,top:Math.floor(i/4)*340});
      const label=Buffer.from(`<svg width="224" height="20"><text x="8" y="15" font-size="12" fill="${name==='dark'?'white':'black'}">${i+1}</text></svg>`);
      placements.push({input:label,left:(i%4)*224,top:Math.floor(i/4)*340+320});
    }
    await sharp({create:{width:896,height:1360,channels:3,background:bg}}).composite(placements).jpeg({quality:94}).toFile(path.join(root,'review',`direct-v4-character-${name}.jpg`));
  }
  for(const r of records)if(hash(fs.readFileSync(r.source))!==r.sourceHash)throw Error('character source changed');
  fs.writeFileSync(path.join(root,'direct-v4-validation.json'),JSON.stringify({scope:'idle only',records,independentDrawings:16,characterCycleSeconds:3.2,effectCycleSeconds:8,effectSamplesHz:10,exportSeconds:16,characterSourcesUnchanged:true,fixedPoseEffectProgression:true,originalRegistration:'whole generated cells require visual measurement; not proved by hashes',installation:'not requested or performed'},null,2));
  console.log('16 complete generated sources unchanged; effects continue with fixed pose; 16s exports rendered');
})().catch(e=>{console.error(e.message);process.exit(1)});
