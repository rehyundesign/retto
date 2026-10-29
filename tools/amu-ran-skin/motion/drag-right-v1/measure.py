from PIL import Image
import numpy as np
from pathlib import Path

def blobs(mask):
 todo=set(map(tuple,np.argwhere(mask)));out=[]
 while todo:
  p=todo.pop();part=[p];stack=[p]
  while stack:
   y,x=stack.pop()
   for q in [(y-1,x),(y+1,x),(y,x-1),(y,x+1)]:
    if q in todo:todo.remove(q);stack.append(q);part.append(q)
  if len(part)>5:
   a=np.array(part);out.append((len(part),float(a[:,1].mean()),float(a[:,0].mean())))
 return sorted(out,reverse=True)
def measure(path):
 im=Image.open(path).convert('RGBA');s=448/im.width;im=im.resize((448,round(im.height*s)),Image.Resampling.LANCZOS)
 a=np.asarray(im).astype(float);r,g,b,al=[a[:,:,i] for i in range(4)]
 blue=(b-r>9)&(g-r>2)&(al>160);blue[:250]=False;blue[500:]=False;blue[:,:230]=False
 bb=blobs(blue);n,x,y=bb[0]
 # Fur cheek span at the near-eye line, excluding the raised tail.
 spans=[]
 for row in range(round(y+8),round(y+18)):
  xs=np.flatnonzero(al[row]>110);xs=xs[xs>x-140]
  gaps=np.diff(xs);start=np.flatnonzero(gaps>3)
  if len(start):xs=xs[start[-1]+1:]
  spans.append(float(xs[-1]-xs[0]+1))
 bounds=im.getchannel('A').point(lambda a:255 if a>96 else 0).getbbox()
 return {'eye_x':x,'eye_y':y,'cheek_span':float(np.median(spans)),'bounds':bounds,'source_scale':s,'blue_blobs':bb[:2]}
if __name__=='__main__':
 import json
 r=Path(__file__).resolve().parent
 for p in list((r/'reference').glob('base*.png'))+list((r/'raw').glob('F*.png')):
  print(p.name,json.dumps(measure(p)))
