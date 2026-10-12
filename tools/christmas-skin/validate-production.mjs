import fs from 'node:fs/promises';
import path from 'node:path';
import{createRequire}from'node:module';
import{fileURLToPath}from'node:url';
import{createHash}from'node:crypto';
const require=createRequire(import.meta.url),sharp=require(path.join(process.env.RETTO_NODE_MODULES,'sharp'));
const root=path.dirname(fileURLToPath(import.meta.url)),repo=path.resolve(root,'../..'),dir=path.join(root,'gen-production');
const map=JSON.parse(await fs.readFile(path.join(root,'production-map.json'))),tones=await fs.readFile(path.join(repo,'macos/Sources/Tones.swift'),'utf8'),geometry=await fs.readFile(path.join(repo,'macos/Sources/Geometry.swift'),'utf8');
const catalog=tones.split('let animationCatalog')[1],pattern=/\.(\w+):\s*Animation\(row:\s*(\d+),\s*frames:\s*(\d+),\s*interval:\s*([\d.]+)/g;
let states=0;for(const match of catalog.matchAll(pattern)){const id=match[1]==='running'?'thinking':match[1],g=map.groups.find(g=>g.id===id);if(!g||g.row!==Number(match[2])||g.frames!==Number(match[3])||g.interval!==Number(match[4]))throw new Error(`State map mismatch: ${id}`);states+=g.frames;}
const drag=tones.split('let dragRunAnimations')[1].split('let animationCatalog')[0];let dragCount=0;for(const match of drag.matchAll(pattern)){const g=map.groups.find(g=>g.id===(match[1]==='right'?'moveRight':'moveLeft'));if(!g||g.row!==Number(match[2])||g.frames!==Number(match[3])||g.interval!==Number(match[4]))throw new Error('Drag map mismatch');dragCount+=g.frames;}
if(!geometry.includes('let gazeDirectionCount = 16')||states!==49||dragCount!==16||map.gaze.length!==16)throw new Error('Runtime cell count mismatch');
const digest=b=>createHash('sha256').update(b).digest('hex'),sourceHashes=new Set();for(const id of [...Array.from({length:4},(_,i)=>`waving-${i}`),...map.gaze.map(g=>g.id)])sourceHashes.add(digest(await fs.readFile(path.join(dir,`${id}-source.png`))));if(sourceHashes.size!==20)throw new Error('New cells need independent sources');
let lockedChanges=0;for(const[file,hash]of Object.entries(map.locked_character_hashes))if(digest(await fs.readFile(path.join(root,file)))!==hash)lockedChanges++;
const files=['spritesheet-christmas.webp','spritesheet-christmas-character.webp','spritesheet-christmas-effects-back.webp','spritesheet-christmas-effects-front.webp'],alpha=[];
for(const file of files){const{data,info}=await sharp(path.join(repo,'assets',file)).ensureAlpha().raw().toBuffer({resolveWithObject:true});let hidden=0;for(let p=0;p<data.length;p+=4)if(!data[p+3]&&(data[p]||data[p+1]||data[p+2]))hidden++;if(hidden||info.width!==3584||info.height!==7680)throw new Error(`Atlas encoding failed: ${file} ${hidden}`);alpha.push({file,transparent_rgb_pixels:hidden});}
const master=await sharp(path.join(root,'gen-festive/idle-0-character.png')).ensureAlpha().raw().toBuffer();let gazeBodyChanges=0;
for(let i=0;i<16;i++){const char=await sharp(path.join(dir,`gaze-${i}-character.png`)).ensureAlpha().raw().toBuffer();for(let p=444*448*4;p<char.length;p++)if(char[p]!==master[p])gazeBodyChanges++;}
if(lockedChanges||gazeBodyChanges)throw new Error('Approved character changed');
const report={ok:true,runtime_map:{states,drag:dragCount,gaze:16,total:81},independent_new_sources:sourceHashes.size,approved_character_changes:lockedChanges,gaze_locked_body_changes:gazeBodyChanges,alpha,original_identity_pixel_mask_check:'not performed: candidate retains approved pose variants; original gaze used as direction reference',app_build:'not run: only art and preview tools changed',installation:'not installed'};
await fs.writeFile(path.join(dir,'delivery-validation.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
