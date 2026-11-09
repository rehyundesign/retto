"""Blue-only strength repair: compare isolated Melody layers at every export sample."""
from pathlib import Path
import json,hashlib
from PIL import Image
ROOT=Path(__file__).resolve().parent;OLD=ROOT.parent/'pet-effects-v1-20261106'
needle="for actor,color,side in [('tato',BLUE,-1),('melody',RED,1)]:"
old=(OLD/'render.py').read_text().replace(needle,"for actor,color,side in [('melody',RED,1)]:")
new=(ROOT/'render.py').read_text().replace(needle,"for actor,color,side in [('melody',RED,1)]:")
a={'__file__':str(ROOT/'render.py'),'__name__':'prior_melody'};b={'__file__':str(ROOT/'render.py'),'__name__':'current_melody'};exec(compile(old,str(ROOT/'render.py'),'exec'),a);exec(compile(new,str(ROOT/'render.py'),'exec'),b)
report={'method':'isolate only Melody actor in both exact render functions; compare both RGBA layers pixel-for-pixel at every original export timestamp','samples':{}}
for state,v in json.loads((ROOT/'render-inputs.json').read_text()).items():
    with Image.open(v['effect']) as im:im.seek(0);im.load();a['SIZE']=b['SIZE']=im.size;step=im.info['duration']
    count=0
    for ms in range(0,v['cycle_ms'],step):
        old_layers=a['effects'](state,ms,v['cycle_ms']);new_layers=b['effects'](state,ms,v['cycle_ms']);assert all(x.tobytes()==y.tobytes() for x,y in zip(old_layers,new_layers));count+=1
    report['samples'][state]=count
report['melody_effect_RGBA_changed_pixels']=0;(ROOT/'melody-preserved.json').write_text(json.dumps(report,indent=2)+'\n');print(report['samples'])
