from pathlib import Path
import json,hashlib,importlib.util,math,sys
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('cleaner',ROOT.parent/'idle-v5-canonical-20261106/prepare.py');M=importlib.util.module_from_spec(s);s.loader.exec_module(M)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def nose(im):
 a=np.asarray(im).astype(int);r,g,b,al=[a[:,:,k] for k in range(4)];y,x=np.indices(al.shape);mask=(r>180)&(r-g>35)&(b-g>0)&(al>180)&(x>170)&(x<380)&(y>135)&(y<260)
 cs=M.comps(mask,6);assert cs,'main nose not found';c=max(cs,key=lambda c:len(c)*math.exp(-((float(np.mean([y for y,x in c]))-210)/25)**2));return [float(np.mean([x for y,x in c])),float(np.mean([y for y,x in c]))]
def one(group,i):
 g=ROOT/group;ident=f'{i:02}'
 if group=='gaze' and i==12:
  p=ROOT.parent/'gaze-left-v1-20261106/character/06.png';im=Image.open(p).convert('RGBA');dest=g/'character'/f'{ident}.png';im.save(dest);return im,{'id':ident,'path':str(dest.resolve()),'sha256':sha(dest),'retained_approved_source':str(p.resolve()),'retained_source_sha256':sha(p),'independent_complete_trio_drawing':True,'new_head_body_assembly':False}
 p=g/'raw'/f'{ident}.png';im,n=M.clean(Image.open(p).convert('RGBA'));dx=dy=0
 if group=='gaze':dy=484-M.support(im)
 elif i:
  anchor=Image.open(g/'character/00.png').convert('RGBA');base=nose(anchor);now=nose(im);dx=round(base[0]-now[0]);dy=round(base[1]+5*math.sin(math.tau*i/16)-now[1]);assert abs(dx)<30 and abs(dy)<35,(group,i,dx,dy)
 # Keep complete source extremities: registration is rigid and constrained by its actual alpha bounds.
 box=im.getbbox()
 if group!='gaze':
  dx=max(1-box[0],min(543-box[2],dx));dy=max(1-box[1],min(543-box[3],dy))
 out=Image.new('RGBA',(544,544));out.alpha_composite(im,(dx,dy));dest=g/'character'/f'{ident}.png';out.save(dest)
 return out,{'id':ident,'path':str(dest.resolve()),'sha256':sha(dest),'raw_sha256':sha(p),'whole_trio_registration':[dx,dy],'independent_complete_trio_drawing':True,'new_head_body_assembly':False,'nose_proxy':nose(out),'original_anatomical_landmarks':'unverified; no silhouette normalization','detached_dust_removed_pixels':n}
def board(fs,path,color):
 out=Image.new('RGB',(896,992),color);d=ImageDraw.Draw(out)
 for i,f in enumerate(fs):
  b=Image.new('RGBA',(544,544),color);b.alpha_composite(f);x=i%4*224;y=i//4*248;out.paste(b.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));d.text((x+5,y+226),str(i),fill='#a99572')
 out.save(path)
def main(group):
 fs=[];rs=[]
 for i in range(16):f,r=one(group,i);fs.append(f);rs.append(r)
 g=ROOT/group;(g/'sources.json').write_text(json.dumps(rs,indent=2)+'\n');fs[0].save(g/'review/character.webp',save_all=True,append_images=fs[1:],duration=200 if group=='gaze' else 100,loop=0,lossless=True,exact=True,method=4)
 for color,label in [('#10182a','dark'),('#edf0f5','light')]:board(fs,g/'review'/f'character-{label}.png',color)
if __name__=='__main__':main(sys.argv[1])
