import numpy as np
from PIL import Image,ImageFilter

def clean(im, protected_regions=()):
 v=np.asarray(im).copy();rgb=v[:,:,:3];a=v[:,:,3];r,g,b=[rgb[:,:,i].astype(int) for i in range(3)]
 red=(r>100)&(r>g*2)&(r>b*1.4)&(g<110)&(b>g*.65)
 protected=np.asarray(Image.fromarray((red*255).astype('uint8')).filter(ImageFilter.MaxFilter(9)))>0
 # Keep reviewed true white face highlights; classify complete components,
 # rather than preserving a broad area that would also keep white background.
 h,w=a.shape;yy,xx=np.indices(a.shape)
 face=((xx-(w/2-28))/98)**2+((yy-160)/95)**2<=1
 for x0,y0,x1,y1 in protected_regions:face[y0:y1,x0:x1]=True

 lo=(np.min(rgb,axis=2)>=232)&(np.ptp(rgb,axis=2)<=12)&(a>16)&~protected
 seed=(np.min(rgb,axis=2)>=250)&(np.ptp(rgb,axis=2)<=4)&(a>16)&~protected
 h,w=a.shape;bits=bytearray(lo.tobytes());seeds=seed.ravel();erase=np.zeros(h*w,bool);components=[];kept=[]
 for start in np.flatnonzero(seed):
  if not bits[start]:continue
  todo=[int(start)];bits[start]=0;pts=[];ns=0
  while todo:
   p=todo.pop();pts.append(p);ns+=int(seeds[p]);x=p%w;y=p//w
   for q in (p-1 if x else -1,p+1 if x+1<w else -1,p-w if y else -1,p+w if y+1<h else -1):
    if q>=0 and bits[q]:bits[q]=0;todo.append(q)
  if ns>=8 and len(pts)>=20 and float(np.mean(face.ravel()[pts]))>=.85:
   ys=np.array(pts)//w;xs=np.array(pts)%w;kept.append({'area':len(pts),'box':[int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)]})
  if ns>=8 and len(pts)>=20 and float(np.mean(face.ravel()[pts]))<.85:
   erase[pts]=True;ys=np.array(pts)//w;xs=np.array(pts)%w;components.append({'area':len(pts),'seeds':ns,'box':[int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)]})
 newa=a.copy();newa[(a<=16)|erase.reshape(h,w)]=0
 v[:,:,3]=newa
 clean.last_kept=kept
 return Image.fromarray(v),erase.reshape(h,w),components
