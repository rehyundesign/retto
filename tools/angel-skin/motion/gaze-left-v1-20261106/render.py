"""Retained angel motifs; physical star/Tato/Melody emitters follow each new drawing."""
from pathlib import Path
import json,importlib.util,hashlib,math
import numpy as np
from PIL import Image,ImageChops
import prepare
ROOT=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('idle_fx',ROOT.parent/'idle-v5-canonical-20261106/render.py');FX=importlib.util.module_from_spec(s);s.loader.exec_module(FX)
s=importlib.util.spec_from_file_location('stars',ROOT.parent/'idle-v6-background-stars-20261106/render.py');ST=importlib.util.module_from_spec(s);s.loader.exec_module(ST)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def compose(ms,char,records):
 b,f=FX.effects(ms,records);b.alpha_composite(ST.starfield(ms))
 # Readable flight accents beneath each pet, away from faces and the cell edge.
 for actor,key,color in [('tato','star',FX.BLUE),('melody','melody_magic_emitter',FX.RED)]:
  for age in [0,150,300]:
   q=(ms%800+age)%800/800;phase=math.pi*q
   sx,sy=FX.at(records,ms-age,key)
   if actor=='tato':pos=(sx-40-8*q,sy+98+27*q);kind='star';size=16
   else:pos=(sx-30+8*q,sy+66+27*q);kind='heart';size=14
   FX.stamp(f,kind,pos,size,color,.82*math.sin(phase)**1.2,18*math.sin(math.tau*q))

 y,x=np.indices((544,544));dist=np.minimum(np.minimum(x,543-x),np.minimum(y,543-y));q=np.clip((dist-12)/36,0,1);mask=Image.fromarray(np.round(q*q*(3-2*q)*255).astype('uint8'))
 for layer in [b,f]:layer.putalpha(ImageChops.multiply(layer.getchannel('A'),mask))
 return FX.compose(b,char,f)
def main():
 records=json.loads((ROOT/'sources.json').read_text());chars=[Image.open(ROOT/r['path']).convert('RGBA') for r in records]
 assert len(chars)==16 and len({hashlib.sha256(f.tobytes()).hexdigest() for f in chars})==16
 frames=[];dark=[];hashes=[]
 for ms in range(0,3200,50):
  f=compose(ms,chars[ms//200],records);assert FX.night.border_max(f.getchannel('A'))==0
  frames.append(f);hashes.append(hashlib.sha256(f.tobytes()).hexdigest());b=Image.new('RGBA',f.size,'#10182a');b.alpha_composite(f);dark.append(b.convert('RGB'))
 assert len(set(hashes))==64
 assert compose(0,chars[0],records).tobytes()==compose(3200,chars[0],records).tobytes()
 assert compose(1200,chars[6],records).tobytes()!=compose(1250,chars[6],records).tobytes()
 FX.night.save_webp(frames,ROOT/'review/night.webp',50)
 runtime=[]
 for f in frames:
  # Same1.06 body camera as installed AngelSkin.rect,224px native pet canvas.
  side=round(224*544/448*1.06);cell=Image.new('RGBA',(320,360),'#10182a');cell.alpha_composite(f.resize((side,side),Image.Resampling.LANCZOS),((320-side)//2,round(320-484*side/544)));runtime.append(cell.convert('RGB'))
 runtime[0].save(ROOT/'review/gaze-left.gif',save_all=True,append_images=runtime[1:],duration=50,loop=0,disposal=2)
 for label,color in [('dark','#10182a'),('light','#edf0f5')]:prepare.board([frames[i*4] for i in range(16)],ROOT/'review'/f'effect-{label}.png',color)
 report={'independent_complete_trio_drawings':16,'main_head_neck_body_patches':False,'pose_ms':200,'effect_ms':50,'cycle_ms':3200,'effect_samples':64,'edge_alpha_max':0,'opaque_character_and_star_pixels_unchanged_by_FX':True,'periodic_fx_loop':True,'frozen_pose_fx_progression':True,'review_only':True,'native_installed':False,'runtime_GIF_bodyScale':1.06,'runtime_GIF_canvas':[320,360],'media':{}}
 for name in ['character.webp','night.webp','gaze-left.gif']:
  with Image.open(ROOT/'review'/name) as im:
   total=0
   for i in range(im.n_frames):im.seek(i);im.load();total+=im.info['duration']
   assert total==3200;report['media'][name]={'frames':im.n_frames,'cycle_ms':total,'sha256':sha(ROOT/'review'/name)}
 (ROOT/'review/media-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
if __name__=='__main__':main()
