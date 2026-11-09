"""Detect accidentally hidden companion colors after full composition; not an art approval."""
from pathlib import Path
import json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parent
lock=json.loads((ROOT/'pre-edit-lock.json').read_text());report={}
for state,v in lock.items():
    old=Image.open(v['effect']);new=Image.open(ROOT/state/'night.webp');counts=[]
    for i in range(new.n_frames):
        old.seek(i);new.seek(i);ims=[]
        for im in [old,new]:
            f=Image.new('RGBA',im.size,'#10182a');f.alpha_composite(im.convert('RGBA'));ims.append(np.asarray(f).astype(int))
        a,b=ims;delta=b-a
        red=(delta[:,:,0]>delta[:,:,1]+8)&(b[:,:,0]>b[:,:,1]*1.2)
        blue=(delta[:,:,2]>delta[:,:,0]+8)&(b[:,:,2]>b[:,:,0]*1.2)
        counts.append([int(blue.sum()),int(red.sum())])
    c=np.asarray(counts);mean=c.mean(axis=0);samples=(c>5).sum(axis=0)
    assert np.all(mean>=12),(state,'a companion color is mostly hidden',mean)
    assert np.all(samples>=12),(state,'a companion color is visible for too few samples',samples)
    report[state]={'mean_visible_pixels_blue_red':mean.round(1).tolist(),'max':c.max(axis=0).tolist(),'samples_with_color':samples.tolist()}
(ROOT/'color-legibility.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
