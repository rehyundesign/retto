"""Gold stars and ivory feathers at the shared wink; all character pixels retained."""
from pathlib import Path
import importlib.util,json,hashlib,math
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops
ROOT=Path(__file__).resolve().parent;OLD=ROOT.parent/'jumping-v3-wink-20261105';SIZE=(544,544);CYCLE=2400;STEP=50

def mod(name,p):
 s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
G=mod('gold',ROOT.parent/'effect-repair-v3-stars-sad-20261106/render.py');P=mod('pet_fx',ROOT.parent/'pet-effects-v2-clean-idle-20261106/render.py');N=P.night

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ref(p):return {'path':str(p.resolve()),'sha256':sha(p)}
def envelope(ms,start,duration):
 q=(ms-start)/duration
 return (q,math.sin(math.pi*q)**.7) if 0<q<1 else (0,0)
def layers(ms):
 ms%=CYCLE;back=Image.new('RGBA',SIZE);front=back.copy();q,a=envelope(ms,550,1100)
 if a:
  glow=Image.new('RGBA',SIZE);d=ImageDraw.Draw(glow);r=85+155*q
  d.ellipse((272-r,280-r*.85,272+r,280+r*.85),fill=(255,218,109,round(36*a)))
  back.alpha_composite(glow.filter(ImageFilter.GaussianBlur(26)))
  # Radiating stage-light strokes, with round, fading tips rather than a box.
  rays=Image.new('RGBA',SIZE);d=ImageDraw.Draw(rays)
  for j in range(18):
   ang=j*math.tau/18-.1;r1=100+95*q;r2=r1+37+32*math.sin(math.pi*q)
   x,y=272,278;d.line((x+r1*math.cos(ang),y+r1*.82*math.sin(ang),x+r2*math.cos(ang),y+r2*.82*math.sin(ang)),fill=(255,231,160,round(190*a)),width=2 if j%2 else 3)
  back.alpha_composite(rays.filter(ImageFilter.GaussianBlur(3)));back.alpha_composite(rays)
  for j in range(13):
   ang=-math.pi/2+j*math.tau/13;r=193+50*q+(j%3)*6
   pos=(272+r*math.cos(ang),275+r*.9*math.sin(ang))
   if j%3==1:P.stamp(front,'feather',(pos[0]+8*math.sin(q*math.tau+j),pos[1]),43+(j%2)*6,(255,247,230),a*.96,j*19+55*math.sin(q*math.pi))
   else:G.gold_stamp(front,pos,29+(j%3)*7,a*(.8 if j%2 else 1),j*18+85*q)
  for j,(x,y) in enumerate([(60,92),(123,51),(415,51),(484,92),(52,431),(488,431)]):
   drift=16*q
   pos=(x+(-drift if x<272 else drift),y-15*math.sin(math.pi*q))
   if j%2:P.stamp(front,'feather',(pos[0]+7*math.sin(q*math.tau+j),pos[1]),48+(j%3)*4,(255,249,237),a,(-35 if x<272 else 35)+50*math.sin(q*math.pi+j))
   else:G.gold_stamp(front,pos,34+(j%3)*7,a,j*23+100*q)
  for j,color in enumerate([(102,202,255),(255,109,143)]):
   P.arc(back,(272,280),173+50*q,139+33*q,color,.7*a,125 if j==0 else -55,235 if j==0 else 55,3)
 # A slower golden shower follows the main reveal and settles with the landing.
 q,a=envelope(ms,950,1150)
 if a:
  for j in range(14):
   x=46+j*34+7*math.sin(j+q*math.pi);y=80+(j%4)*56+185*q
   if j%3==0:P.stamp(front,'feather',(x+12*math.sin(q*math.tau+j),y),30+(j%2)*6,(255,247,230),a*.85,20+45*math.sin(q*math.tau+j))
   else:G.gold_stamp(front,(x,y),8+(j%3)*3,a*.88,j*20+90*q)
 return P.fade(back),P.fade(front)
def compose(ms,base,char):
 back,front=layers(ms);protect=char.getchannel('A').point(lambda a:255 if a>4 else 0).filter(ImageFilter.MaxFilter(9))
 front.putalpha(ImageChops.multiply(front.getchannel('A'),ImageChops.invert(protect)))
 out=back.copy();out.alpha_composite(base);out.alpha_composite(front)
 opaque=np.asarray(base)[:,:,3]==255;assert np.array_equal(np.asarray(base)[opaque],np.asarray(out)[opaque])
 return out

def main():
 lock=json.loads((ROOT/'pre-edit-lock.json').read_text());chars=[];bases=[]
 for key,dest in [('character_animation',chars),('effect_animation',bases)]:
  p=Path(lock[key]['path']);assert sha(p)==lock[key]['sha256']
  with Image.open(p) as im:
   for i in range(im.n_frames):im.seek(i);im.load();dest.append(im.convert('RGBA'))
 assert len(chars)==16 and len(bases)==48
 frames=[];dark=[];unique=set();changed=[]
 for i,ms in enumerate(range(0,CYCLE,STEP)):
  f=compose(ms,bases[i],chars[ms//150]);assert N.border_max(f.getchannel('A'))==0
  unique.add(hashlib.sha256(f.tobytes()).hexdigest());changed.append(int(np.count_nonzero(np.any(np.asarray(f)!=np.asarray(bases[i]),axis=2))))
  frames.append(f);b=Image.new('RGBA',SIZE,'#10182a');b.alpha_composite(f);dark.append(b.convert('RGB'))
 assert len(unique)==48 and max(changed)>10000
 assert layers(0)[0].tobytes()==layers(CYCLE)[0].tobytes()
 assert compose(900,bases[18],chars[6]).tobytes()!=compose(950,bases[18],chars[6]).tobytes()
 N.save_webp(frames,ROOT/'review/night.webp',STEP)
 dark[0].save(ROOT/'review/jumping.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2)
 for bg,label in [('#10182a','dark'),('#edf0f5','light')]:
  board=Image.new('RGB',(896,992),bg);d=ImageDraw.Draw(board)
  for i in range(16):
   cell=Image.new('RGBA',SIZE,bg);cell.alpha_composite(frames[i*3]);x=i%4*224;y=i//4*248;board.paste(cell.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));d.text((x+5,y+227),str(i),fill='#ad986d')
  board.save(ROOT/'review'/f'runtime-{label}.png')
 for k,h in lock['source_sha256'].items():assert sha(OLD/'character'/f'{k}.png')==h
 report={'retained_character_drawings':16,'pose_ms':150,'effect_ms':50,'cycle_ms':2400,'effect_frames':48,'opaque_base_pixels_exact':True,'source_PNGs_and_character_animation_unchanged':True,'edge_alpha_max':0,'frozen_pose_effect_progression':True,'new_effect_changed_pixels_max':max(changed),'native_installed':False,'live_browser_verified':False}
 for name in ['night.webp','jumping.gif']:
  with Image.open(ROOT/'review'/name) as im:
   total=0
   for i in range(im.n_frames):im.seek(i);im.load();total+=im.info['duration']
   assert total==CYCLE;report[name]={'frames':im.n_frames,'cycle_ms':total,'sha256':sha(ROOT/'review'/name)}
 (ROOT/'review/validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
if __name__=='__main__':main()
