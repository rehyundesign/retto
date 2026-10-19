from PIL import Image
from pathlib import Path
import numpy as np,json
p=Path(__file__).parent
rois={'sleeping':(121,225,47,35),'drag-right':(155,176,44,39),'drag-left':(30,181,48,41),'review':(75,142,50,29),'waving':(75,135,48,35),'failed':(59,153,50,30),'idle':(76,139,47,30)}
def gray(f):return np.asarray(Image.open(f).convert('RGB').resize((224,320),Image.Resampling.LANCZOS),dtype=float).mean(2)
masters={j['state']:j['master'] for j in json.loads((p/'jobs.json').read_text())};reports={}
for state,(x,y,w,h) in rois.items():
 if not all((p/state/f'{i:02d}-source.png').is_file() for i in range(16)):continue
 ref=gray(p/state/'00-source.png');a=ref[y:y+h,x:x+w];a=a-a.mean();a/=np.linalg.norm(a);res=[]
 for i in range(16):
  im=gray(p/state/f'{i:02d}-source.png');best=(-2,0,0)
  for dy in range(-10,11):
   for dx in range(-10,11):
    b=im[y+dy:y+dy+h,x+dx:x+dx+w];b=b-b.mean();norm=np.linalg.norm(b);score=float((a*b).sum()/norm) if norm else -2
    if score>best[0]:best=(score,dx,dy)
  res.append({'frame':i+1,'dxNative':best[1],'dyNative':best[2],'correlation':round(best[0],4)})
 reports[state]={'method':'first NEW frame facial-patch normalized correlation; within-row only, not original or master registration','frames':res,'maxDx':max(abs(r['dxNative']) for r in res),'maxDy':max(abs(r['dyNative']) for r in res),'minimumCorrelation':min(r['correlation'] for r in res)}
 print(state,reports[state]['maxDx'],reports[state]['maxDy'],reports[state]['minimumCorrelation'])
(p/'within-row-position-checks.json').write_text(json.dumps(reports,indent=2))
