from pathlib import Path
import json,hashlib,importlib.util,math,sys
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops
import prepare
ROOT=Path(__file__).resolve().parent
def mod(name,p):
 s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
F=mod('fx',ROOT.parent/'idle-v5-canonical-20261106/render.py');S=mod('sky',ROOT.parent/'idle-v6-background-stars-20261106/render.py');N=F.night
SIZE=(544,544);CYCLE=3200;STEP=50
Y,X=np.indices((544,544));DIST=np.minimum(np.minimum(X,543-X),np.minimum(Y,543-Y));Q=np.clip((DIST-12)/36,0,1);EDGE=Image.fromarray(np.round(Q*Q*(3-2*Q)*255).astype('uint8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def fade(im):
 out=im.copy();out.putalpha(ImageChops.multiply(im.getchannel('A'),EDGE));return out
def anchors(im,group):
 a=np.asarray(im).astype(int);r,g,b,al=[a[:,:,i] for i in range(4)]
 def bottom(mask,fallback):
  ys,xs=np.nonzero(mask)
  if len(xs)<5:return fallback
  by=int(ys.max());sel=ys>by-12;return [round(float(np.median(xs[sel])),2),int(by)]
 parts=prepare.M.comps(al>180,250)
 def pet_foot(left,fallback):
  candidates=[c for c in parts if (np.mean([x for y,x in c])<145 if left else np.mean([x for y,x in c])>390) and len(c)<30000]
  if candidates:
   c=max(candidates,key=len);by=max(y for y,x in c);xs=[x for y,x in c if y>by-12];return [round(float(np.median(xs)),2),int(by)]
  # Some wing tips overlap the pet alpha; constrain colour fallback to its own column.
  return bottom((al>180)&((X<125) if left else (X>405))&((r>200)&(g>180)&(b>165) if left else (r>190)&(r-g>30)&(g>100)&(b-g>-18)),fallback)
 tato=pet_foot(True,[75,300]);melody=pet_foot(False,[450,300])
 gold=(al>200)&(r>170)&(g>175)&(r>g*1.01)&(g>b*1.55)&(b<170)&(X<170)
 cs=prepare.M.comps(gold,12)
 star=[95,310]
 if cs:
  c=max(cs,key=len);star=[float(np.mean([x for y,x in c])),float(np.mean([y for y,x in c]))]
 side=1 if group=='drag-left' else -1
 tailmask=(al>180)&(r<205)&(r-g>12)&(g-b>8)&(Y>300)&((X>355) if side>0 else(X<180))
 ys,xs=np.nonzero(tailmask);tail=[480 if side>0 else 40,400]
 if len(xs):
  extreme=xs.max() if side>0 else xs.min();near=abs(xs-extreme)<6;tail=[int(extreme),float(np.mean(ys[near]))]
 return {'tato':tato,'melody':melody,'star':[round(v,2) for v in star],'tail':[round(v,2) for v in tail]}
def background(ms):
 t=(ms%CYCLE)/CYCLE;b=N.opacity(N.night_atmosphere(ms,SIZE,CYCLE),.6);b.alpha_composite(S.starfield(ms));N.stamp(b,N.crescent(46),(382,112+2*math.sin(math.tau*t)),46,.4,-18)
 for j in range(4):
  q=(t+j/4)%1;N.stamp(b,F.FEATHER,(40+j*149+8*math.sin(math.tau*q+j),100+360*q),21,.35*math.sin(math.pi*q)**2,25*math.sin(math.tau*q+j),halo=False)
 return fade(b)
def gaze_magic(ms,a):
 b=Image.new('RGBA',SIZE)
 for actor,color in [('tato',F.BLUE),('melody',F.RED)]:
  for j in range(3):
   q=(ms/1000+j*.15)%.8/.8;x,y=a[actor];x+=(-8 if actor=='tato' else 8)*q;y+=6+28*q
   F.stamp(b,'star' if actor=='tato' else 'heart',(x,y),16 if actor=='tato' else 14,color,.82*math.sin(math.pi*q)**1.2)
 return fade(b)
def flight_effects(group,ms,rs):
 t=(ms%CYCLE)/CYCLE;side=1 if group=='drag-left' else -1;b=background(ms);f=Image.new('RGBA',SIZE)
 for age in [0,150,300,450,600]:
  q=age/750;source=rs[int(((ms-age)%1600)//100)]['attachment_proxies'];tx,ty=source['tail'];x=tx+side*(5+42*q);y=ty-15+30*q
  F.stamp(b,'feather',(x,y),24+(age//150)%2*6,(255,246,225),.6*(1-q)**1.3,side*(15+45*q))
  if age%300==0:F.stamp(b,'star',(x-side*10,y-25),9,(255,224,137),.65*(1-q))
 for actor,color in [('tato',F.BLUE),('melody',F.RED)]:
  for j in range(4):
   q=(t*4+j/4)%1;birth=ms-q*800;root=rs[int((birth%1600)//100)]['attachment_proxies'][actor];px,py=root
   F.stamp(b,'star' if actor=='tato' else 'heart',(px+side*(6+35*q),py+5+25*q),17 if actor=='tato' else 14,color,.9*math.sin(math.pi*q)**1.2,side*25*q)
 return fade(b),fade(f)
def runtime(f):
 side=round(224*544/448*1.06);out=Image.new('RGBA',(320,360),'#10182a');out.alpha_composite(f.resize((side,side),Image.Resampling.LANCZOS),((320-side)//2,round(320-484*side/544)));return out.convert('RGB')
def main(group):
 g=ROOT/group;rs=json.loads((g/'sources.json').read_text());chars=[Image.open(r['path']).convert('RGBA') for r in rs];assert len(chars)==16 and len({hashlib.sha256(c.tobytes()).hexdigest() for c in chars})==16
 for r,c in zip(rs,chars):r['attachment_proxies']=anchors(c,group)
 (g/'sources.json').write_text(json.dumps(rs,indent=2)+'\n');frames=[];hashes=[];backs=[]
 for ms in range(0,CYCLE,STEP):
  if group=='gaze':
   i=ms//200;b=background(ms);b.alpha_composite(gaze_magic(ms,rs[i]['attachment_proxies']));f=Image.new('RGBA',SIZE)
  else:i=(ms//100)%16;b,f=flight_effects(group,ms,rs)
  result=F.compose(b,chars[i],f);assert N.border_max(result.getchannel('A'))==0;frames.append(result);hashes.append(hashlib.sha256(result.tobytes()).hexdigest())
 assert len(set(hashes))==64;N.save_webp(frames,g/'review/night.webp',50);tiles=[runtime(f) for f in frames];tiles[0].save(g/'review'/f'{group}.gif',save_all=True,append_images=tiles[1:],duration=50,loop=0,disposal=2)
 for color,label in [('#10182a','dark'),('#edf0f5','light')]:prepare.board([frames[i*(4 if group=='gaze' else 2)] for i in range(16)],g/'review'/f'effects-{label}.png',color)
 if group=='gaze':
  back=ROOT/'gaze-back';back.mkdir(exist_ok=True)
  for ms in range(0,CYCLE,STEP):background(ms).save(back/f'{ms//50:03}.png')
  N.save_webp([background(ms) for ms in range(0,CYCLE,STEP)],g/'review/background.webp',50)
 report={'group':group,'independent_complete_trio_drawings':16,'pose_ms':200 if group=='gaze' else 100,'pose_cycle_ms':3200 if group=='gaze' else 1600,'effect_cycle_ms':3200,'effect_samples':64,'effect_ms':50,'flight_body_loops_per_effect_cycle':1 if group=='gaze' else 2,'opaque_character_pixels_unchanged_byFX':True,'effect_margin_px':12,'edge_alpha_max':0,'native_body_display_scale':1.06,'native_installed':False,'media':{}}
 for name in ['character.webp','night.webp',f'{group}.gif']:
  with Image.open(g/'review'/name) as im:
   total=0
   for i in range(im.n_frames):im.seek(i);im.load();total+=im.info['duration']
   report['media'][name]={'frames':im.n_frames,'duration_ms':total,'sha256':sha(g/'review'/name)}
 (g/'review/validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
if __name__=='__main__':main(sys.argv[1])
