import fs from 'node:fs/promises';import path from 'node:path';import{createRequire}from'node:module';import{fileURLToPath}from'node:url';
const require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp')),root=path.dirname(fileURLToPath(import.meta.url)),dir=path.join(root,'gen-smooth16'),map=JSON.parse(await fs.readFile(path.join(root,'smooth16-map.json')));
for(const g of map.groups){const layers=[];for(let i=0;i<16;i++)for(const dark of [false,true]){const input=await sharp({create:{width:224,height:320,channels:4,background:dark?'#202632':'#fff'}}).composite([{input:await sharp(path.join(dir,`${g.id}-${i}-complete.png`)).resize(224,320).png().toBuffer()}]).png().toBuffer();layers.push({input,left:(i%4+(dark?4:0))*224,top:Math.floor(i/4)*320+26});}await sharp({create:{width:1792,height:1306,channels:4,background:'#ece5d9'}}).composite(layers).png().toFile(path.join(dir,`${g.id}-review.png`));}
const master=await sharp(path.join(root,'gen-production/idle-0-character.png')).ensureAlpha().raw().toBuffer(),gazeLayers=[];
for(let i=0;i<16;i++){
 const buffer=await fs.readFile(path.join(dir,`gaze-${i}-character.png`)),pixels=await sharp(buffer).ensureAlpha().raw().toBuffer();
 if(!pixels.subarray(484*448*4).equals(master.subarray(484*448*4)))throw new Error(`Gaze body drift: ${i}`);
 for(const dark of [false,true]){const input=await sharp({create:{width:224,height:320,channels:4,background:dark?'#202632':'#fff'}}).composite([{input:await sharp(buffer).resize(224,320).png().toBuffer()}]).png().toBuffer();gazeLayers.push({input,left:(i%4+(dark?4:0))*224,top:Math.floor(i/4)*320});}
}
await sharp({create:{width:1792,height:1280,channels:4,background:'#fff'}}).composite(gazeLayers).png().toFile(path.join(dir,'gaze-continuity-review.png'));
for(const group of map.groups){const times=group.frame_durations;if(times?.length!==16||times.some(t=>t<.04)||Math.abs(times.reduce((a,b)=>a+b,0)-group.interval*16)>1e-6)throw new Error(`Bad frame timing: ${group.id}`);}
const file=path.resolve(root,'../../assets/spritesheet-christmas-16-character.webp'),{data,info}=await sharp(file).ensureAlpha().raw().toBuffer({resolveWithObject:true});let bad=0;for(let p=0;p<data.length;p+=4)if(!data[p+3]&&(data[p]||data[p+1]||data[p+2]))bad++;if(bad)throw new Error(`RGB under transparent alpha: ${bad}`);
if(info.width!==7168||info.height!==7680||map.groups.some(g=>g.frames!==16))throw new Error('Incorrect 16-frame layout');
console.log(JSON.stringify({groups:map.groups.length,frames_per_group:16,mapped:map.mapped_cells,transparent_rgb:bad,size:[info.width,info.height]}));
