"""Brighter registered glass, floating opal glints around immutable subjects."""
from pathlib import Path
import importlib.util,json,hashlib,math
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops
ROOT=Path(__file__).resolve().parent;OLD=ROOT.parent/'running-v3-proportion-20261105';SIZE=(544,544);CYCLE=3200;STEP=50
def mod(name,p):
 s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
D=mod('dome',ROOT.parent/'running-v4-musicbox-glow-20261106/render.py');P=mod('pets',ROOT.parent/'pet-effects-v2-clean-idle-20261106/render.py');N=D.night
COLORS=[(255,242,190),(190,230,255),(233,204,255),(255,215,233)]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def glint(layer,xy,size,color,alpha):
 if alpha<=0:return
 x,y=xy;s=size*3;im=Image.new('RGBA',(s,s));d=ImageDraw.Draw(im);c=s/2;r=s*.45
 d.polygon([(c,c-r),(c+r*.14,c-r*.14),(c+r,c),(c+r*.14,c+r*.14),(c,c+r),(c-r*.14,c+r*.14),(c-r,c),(c-r*.14,c-r*.14)],fill=(*color,round(245*alpha)))
 d.ellipse((c-s*.07,c-s*.07,c+s*.07,c+s*.07),fill=(255,255,249,round(255*alpha)))
 im=im.resize((size,size),Image.Resampling.LANCZOS);pos=(round(x-size/2),round(y-size/2));halo=Image.new('RGBA',SIZE);halo.alpha_composite(im,pos);layer.alpha_composite(halo.filter(ImageFilter.GaussianBlur(3)));layer.alpha_composite(im,pos)
def glass(ms,dome):
 layer,mask=D.light(ms,dome);layer.putalpha(layer.getchannel('A').point(lambda a:min(220,round(a*1.9))))
 x,y,w,h=dome;t=(ms%CYCLE)/CYCLE;p=math.tau*t;extra=Image.new('RGBA',SIZE)
 glow=Image.new('RGBA',SIZE);d=ImageDraw.Draw(glow)
 for j,(cx,cy) in enumerate([(.33,.72),(.66,.65),(.5,.38)]):
  px=x+w*cx;py=y+h*cy;r=18+4*math.sin(p+j);d.ellipse((px-r,py-r,px+r,py+r),fill=(*COLORS[j],round(55+17*math.sin(p+j)**2)))
 extra.alpha_composite(glow.filter(ImageFilter.GaussianBlur(8)))
 for j,(cx,cy) in enumerate([(.2,.4),(.73,.32),(.45,.58),(.29,.73),(.7,.72),(.5,.18),(.8,.57),(.4,.85)]):
  a=.14+.86*(.5+.5*math.sin(p+j*.92))**3
  glint(extra,(x+w*(cx+.025*math.sin(p+j)),y+h*(cy+.04*math.cos(p+j))),8+(j%3)*3,COLORS[j%4],a)
 extra.putalpha(ImageChops.multiply(extra.getchannel('A'),mask));layer.alpha_composite(extra);return layer,mask
FIELD=[(48,86,20),(135,48,16),(225,32,14),(353,44,18),(461,88,22),(511,165,16),(503,265,18),(502,389,22),(457,468,15),(350,503,16),(202,507,20),(91,473,17),(36,393,21),(32,265,17),(35,167,19),(110,420,13),(434,420,15),(130,105,12),(414,113,12),(105,315,12),(440,324,14),(271,506,12)]
def atmosphere(ms,dome):
 t=(ms%CYCLE)/CYCLE;p=math.tau*t;layer=Image.new('RGBA',SIZE);x,y,w,h=dome
 for j,(px,py,size) in enumerate(FIELD):
  phase=j*.83;a=.18+.78*(.5+.5*math.sin(p+phase))**3
  glint(layer,(px+5*math.sin(p+phase),py+8*math.cos(p+phase)),size,COLORS[j%4],a)
 # Motes climb gently away from each side of the music box into open air.
 for side in [-1,1]:
  for j in range(4):
   q=(t+j/4)%1;a=math.sin(math.pi*q)**2
   glint(layer,(x+w/2+side*(w*.65+80*q),y+h*.55-120*q),11+j%2*4,COLORS[(j+(side>0))%4],a*.85)
 return P.fade(layer)
def compose(ms,base,char,dome):
 light,mask=glass(ms,dome);out=base.copy();out.alpha_composite(light);out.putalpha(base.getchannel('A'))
 bg=atmosphere(ms,dome);protect=char.getchannel('A').point(lambda a:255 if a>4 else 0).filter(ImageFilter.MaxFilter(11));bg.putalpha(ImageChops.multiply(bg.getchannel('A'),ImageChops.invert(protect)))
 out.alpha_composite(bg)
 a=np.asarray(base);b=np.asarray(out);safe=(np.asarray(mask)==0)&(a[:,:,3]==255)
 assert np.array_equal(a[safe],b[safe]),'opaque subjects changed outside dome'
 allowed=ImageChops.lighter(mask,bg.getchannel('A'));outside=np.asarray(allowed)==0;assert np.array_equal(a[outside],b[outside])
 return out,light,bg

def main():
 lock=json.loads((ROOT/'pre-edit-lock.json').read_text());chars=[];bases=[]
 for key,dest in [('character_animation',chars),('effect_animation',bases)]:
  path=Path(lock[key]['path']);assert sha(path)==lock[key]['sha256']
  with Image.open(path) as im:
   for i in range(im.n_frames):im.seek(i);im.load();dest.append(im.convert('RGBA'))
 assert len(chars)==16 and len(bases)==64
 frames=[];dark=[];unique=set();visible=[]
 for i,ms in enumerate(range(0,CYCLE,STEP)):
  f,l,b=compose(ms,bases[i],chars[ms//200],D.dome_at(ms//200));assert N.border_max(f.getchannel('A'))==0
  unique.add(hashlib.sha256(l.tobytes()+b.tobytes()).hexdigest());visible.append(int(np.count_nonzero(np.asarray(b.getchannel('A'))>40)));frames.append(f)
  bg=Image.new('RGBA',SIZE,'#10182a');bg.alpha_composite(f);dark.append(bg.convert('RGB'))
 assert len(unique)==64 and min(visible)>400
 assert atmosphere(0,D.dome_at(0)).tobytes()==atmosphere(CYCLE,D.dome_at(0)).tobytes()
 assert compose(700,bases[12],chars[3],D.dome_at(3))[0].tobytes()!=compose(750,bases[12],chars[3],D.dome_at(3))[0].tobytes()
 N.save_webp(frames,ROOT/'review/night.webp',STEP);dark[0].save(ROOT/'review/running.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2)
 for color,label in [('#10182a','dark'),('#edf0f5','light')]:
  board=Image.new('RGB',(896,992),color);d=ImageDraw.Draw(board)
  for i in range(16):
   bg=Image.new('RGBA',SIZE,color);bg.alpha_composite(frames[i*4]);x=i%4*224;y=i//4*248;board.paste(bg.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));d.text((x+5,y+226),str(i),fill='#ac986e')
  board.save(ROOT/'review'/f'runtime-{label}.png')
 for ident,h in lock['source_sha256'].items():assert sha(OLD/'character'/f'{ident}.png')==h
 report={'mode':'effect-repair','retained_drawings':16,'pose_ms':200,'cycle_ms':3200,'effect_ms':50,'distinct_light_samples':64,'character_files_and_animation_unchanged':True,'opaque_pixels_outside_dome_unchanged':True,'changes_only_in_dome_and_added_background_glints':True,'edge_alpha_max':0,'frozen_pose_light_progression':True,'background_glint_pixels_alpha_over40':[min(visible),max(visible)],'native_installed':False,'live_browser_verified':False}
 for name in ['night.webp','running.gif']:
  with Image.open(ROOT/'review'/name) as im:
   total=0
   for i in range(im.n_frames):im.seek(i);im.load();total+=im.info['duration']
   assert total==CYCLE;report[name]={'frames':im.n_frames,'cycle_ms':total,'sha256':sha(ROOT/'review'/name)}
 (ROOT/'review/validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
if __name__=='__main__':main()
