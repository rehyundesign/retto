const fs=require('fs'),vm=require('vm'),path=require('path');const p=__dirname,root=path.dirname(p),ctx={window:{}};vm.runInNewContext(fs.readFileSync(root+'/state-integrated-v31-data.js','utf8'),ctx);
const rows=ctx.window.JeanneIntegrated19,map={idle:0,'drag-right':1,'drag-left':2,waving:3,jumping:4,running:5,waiting:6,failed:7,review:8,sleeping:11};
const res=p+'/Retto.app/Contents/Resources/JeanneFrames';fs.mkdirSync(res,{recursive:true});let states=[];
for(const r of rows){const row=map[r.id];const files=r.files.map((f,i)=>{const name=`character-${row}-${i}.png`;fs.copyFileSync(root+'/'+f,res+'/'+name);return name;});states.push({id:r.id,row,cycle:r.cycle,times:r.times||r.files.map(()=>r.cycle/r.files.length),files});}
const gaze={window:{}};vm.runInNewContext(fs.readFileSync(root+'/state-integrated-v25-gaze-data.js','utf8'),gaze);fs.writeFileSync(p+'/gaze-discovery.json',JSON.stringify(gaze.window));
fs.writeFileSync(res+'/manifest.json',JSON.stringify({states},null,2));
