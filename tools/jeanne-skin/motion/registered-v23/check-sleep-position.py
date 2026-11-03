from PIL import Image
from pathlib import Path
import numpy as np,json
p=Path(__file__).parent
# Track a fur/eye/nose patch of the fixed sleeping master; this checks within-row stability only.
def gray(f):return np.asarray(Image.open(f).convert('RGB').resize((224,320),Image.Resampling.LANCZOS),dtype=float).mean(2)
ref=gray(p.parent/'state-integrated-v19/sleeping/00-source.png');x,y,w,h=121,225,47,35;tpl=ref[y:y+h,x:x+w];a=tpl-tpl.mean();a/=np.linalg.norm(a);results=[]
for i in range(16):
 im=gray(p/'sleeping'/f'{i:02d}-source.png');best=(-2,0,0)
 for dy in range(-8,9):
  for dx in range(-8,9):
   b=im[y+dy:y+dy+h,x+dx:x+dx+w];b=b-b.mean();norm=np.linalg.norm(b)
   score=float((a*b).sum()/norm) if norm else -2
   if score>best[0]:best=(score,dx,dy)
 results.append({'frame':i+1,'facePatchDxNative':best[1],'facePatchDyNative':best[2],'correlation':round(best[0],4)})
report={'method':'normalized correlation of same master facial patch; not original Retto registration','frames':results,'maxDx':max(abs(r['facePatchDxNative']) for r in results),'maxDy':max(abs(r['facePatchDyNative']) for r in results)}
(p/'sleeping/position-check.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
