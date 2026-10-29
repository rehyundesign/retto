"""Measure face scale from a protected central template, excluding cape/plume/paws.
Only estimates a whole-character transform; never composites a static face.
"""
from PIL import Image
import numpy as np

def gray(im):
 a=np.asarray(im.convert('RGB'),dtype=np.float32);return .299*a[:,:,0]+.587*a[:,:,1]+.114*a[:,:,2]
def match(im,reference,roi=(108,325,243,414),guess_eye=(171,352),reference_anchor=(171.5,355.5)):
 ref=gray(reference.crop(roi));ref=(ref-ref.mean())/(ref.std()+1e-5)
 # Central face texture is used because alpha silhouettes include headgear and raised paws.
 def score(s,dx,dy):
  p=im.transform((roi[2]-roi[0],roi[3]-roi[1]),Image.Transform.AFFINE,(1/s,0,(roi[0]-dx)/s,0,1/s,(roi[1]-dy)/s),Image.Resampling.BILINEAR)
  z=gray(p);z=(z-z.mean())/(z.std()+1e-5)
  return float(np.mean((ref-z)**2))
 cx,cy=guess_eye;best=(1e9,1,0,0)
 for s in np.arange(.78,1.261,.02):
  bx=reference_anchor[0]-cx*s;by=reference_anchor[1]-cy*s
  for ox in [-12,-6,0,6,12]:
   for oy in [-8,-4,0,4,8]:
    dx,dy=bx+ox,by+oy;v=score(s,dx,dy)
    if v<best[0]:best=(v,float(s),float(dx),float(dy))
 _,bs,bx,by=best
 for s in np.arange(bs-.019,bs+.020,.004):
  for ox in [-2,0,2]:
   for oy in [-2,0,2]:
    dx=bx+ox+(bs-s)*cx;dy=by+oy+(bs-s)*cy;v=score(s,dx,dy)
    if v<best[0]:best=(v,float(s),float(dx),float(dy))
 return {'ncc_loss':best[0],'scale_to_reference':best[1],'translation_to_reference':[best[2],best[3]],'roi':list(roi)}
