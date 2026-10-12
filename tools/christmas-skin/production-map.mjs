import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
const root=new URL('./',import.meta.url);
const previous=JSON.parse(await fs.readFile(new URL('keyframes.json',root)));
const rows={idle:0,moveRight:1,moveLeft:2,waving:3,jumping:4,failed:5,waiting:6,thinking:7,review:8,sleeping:11};
const groups=previous.groups.map(g=>({...g,label:g.id==='idle'?'기본':g.label,row:rows[g.id]}));
groups.splice(3,0,{id:'waving',label:'완료 인사',row:3,frames:4,interval:.185,cycle_limit:2,pose_sequence:[0,1,2,3],pose_group:'front-seated-wave',source_dir:'gen-production'});
const anchors=[['idle',0],['thinking',0],['review',0],['waiting',0],['failed',0],['waving',0],['jumping',1],['sleeping',0],['moveRight',0],['moveLeft',0],['thinking',1],['review',2],['waiting',1],['failed',4],['jumping',0],['sleeping',1]].map(([id,frame],i)=>({id:`anchor-${String(i+1).padStart(2,'0')}`,group:id,frame,canonical_base_cell:[rows[id],frame],destination:[rows[id],frame],view:groups.find(g=>g.id===id).pose_group??'side-running',status:id==='waving'?'new':'approved-preview-locked'}));
const gaze=Array.from({length:16},(_,i)=>({id:`gaze-${i}`,direction:i,degrees_clockwise_from_up:i*22.5,row:9+Math.floor(i/8),column:i%8,frames:1,interval:1,canonical_base_cell:[9+Math.floor(i/8),i%8]}));
const lock={};for(const g of previous.groups)for(let i=0;i<g.frames;i++){const name=`gen-festive/${g.id}-${i}-character.png`;lock[name]=createHash('sha256').update(await fs.readFile(new URL(name,root))).digest('hex');}
const map={version:4,scope:'Complete missing waving and gaze art while preserving approved Christmas preview',mode:'registered-character',cell:{width:448,height:640,columns:8,rows:12,runtime_width:224,runtime_height:320},groups,anchors,gaze,used_cells:81,state_cells:49,drag_cells:16,gaze_cells:16,unused_cells:15,locked_character_hashes:lock,layer_order:['effect_back','character','effect_front'],costume:'Approved Santa hat, red plush coat, white collar/cuffs, two gold buttons, brown belt with square gold buckle',registration_note:'Existing approved pose variants are locked. New gaze head views use corresponding original Retto gaze cells as direction references; torso remains the approved seated master. Record original-reference differences separately from preview consistency.'};
await fs.writeFile(new URL('production-map.json',root),JSON.stringify(map,null,2)+'\n');
console.log(JSON.stringify({anchors:anchors.length,used_cells:map.used_cells,state_cells:49,drag_cells:16,gaze_cells:16}));
