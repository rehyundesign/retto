const fs=require('fs'),path=require('path'),crypto=require('crypto');
const {createCanvas,loadImage}=require('@napi-rs/canvas');
const root=__dirname,characterPath=path.join(root,'../assets/integrated-review-anchor.png');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
 const before=hash(fs.readFileSync(characterPath));
 const [character,effect]=await Promise.all([loadImage(characterPath),loadImage(path.join(root,'effect-source.png'))]);
 const layer=createCanvas(448,640),lc=layer.getContext('2d');lc.drawImage(effect,0,0,448,640);fs.writeFileSync(path.join(root,'effect.png'),layer.toBuffer('image/png'));
 for(const [name,bg] of [['dark','#25232c'],['white','#fffdfb']]){
 const c=createCanvas(448,640),ctx=c.getContext('2d');ctx.fillStyle=bg;ctx.fillRect(0,0,448,640);ctx.save();ctx.beginPath();ctx.rect(0,0,448,640);ctx.rect(96,235,235,140);ctx.clip('evenodd');ctx.drawImage(layer,0,0);ctx.restore();ctx.drawImage(character,0,0);
 // Front light is restricted to pendant and the free perimeter. Face stays original.
 ctx.save();ctx.beginPath();ctx.rect(0,385,448,255);ctx.rect(0,0,70,640);ctx.rect(375,0,73,640);ctx.clip();ctx.drawImage(layer,0,0);ctx.restore();
 fs.writeFileSync(path.join(root,name+'.png'),c.toBuffer('image/png'));
 const face=ctx.getImageData(96,235,235,140).data,cc=createCanvas(448,640),cx=cc.getContext('2d');cx.fillStyle=bg;cx.fillRect(0,0,448,640);cx.drawImage(character,0,0);const original=cx.getImageData(96,235,235,140).data;let protectedPixels=0;
 for(let i=0;i<face.length;i+=4)if(original[i+3]===255){for(let ch=0;ch<3;ch++)if(face[i+ch]!==original[i+ch])throw Error('Face altered');protectedPixels++;}
 console.log(name+': '+protectedPixels+' opaque face pixels preserved');
 }
 if(before!==hash(fs.readFileSync(characterPath)))throw Error('Character source changed');
 fs.writeFileSync(path.join(root,'validation.json'),JSON.stringify({scope:'one static review-pendant effect style',characterSource:'assets/integrated-review-anchor.png',characterHash:before,characterSourceUnchanged:true,facePixelsPreserved:true,animationApplied:false},null,2));
})();
