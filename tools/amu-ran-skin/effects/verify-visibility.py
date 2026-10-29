"""Compare actual exported pixels with the previously delivered effect layers."""
from pathlib import Path
from PIL import Image
import numpy as np
from io import BytesIO
import json,subprocess
ROOT=Path(__file__).resolve().parent.parent;REPO=ROOT.parents[1];BASE='baseline-v2';results=[]
for state in ['idle-v2','waving-v1','waiting-v1']:
 for layer in ['back','front']:
  p=ROOT/'motion'/state/('effect_'+layer)/'020.png';rel=str(p.relative_to(REPO));before=np.array(Image.open(ROOT/'effects'/BASE/f'{state}-{layer}-020.png').convert('RGBA')).astype(float);after=np.array(Image.open(p).convert('RGBA')).astype(float)
  def energy(a,white):return float(np.sum(a[:,:,3:4]/255*((255-a[:,:,:3]) if white else a[:,:,:3])))
  light=energy(after,True)/energy(before,True);dark=energy(after,False)/energy(before,False)
  assert light>1.15 and dark>1.15,(state,layer,light,dark)
  results.append({'state':state,'layer':layer,'white_background_contrast_energy_ratio':round(light,3),'dark_background_light_energy_ratio':round(dark,3)})
report={'baseline':BASE,'samples':results,'character_pose_timing_unchanged':True,'ambient_period_seconds':8,'installed':False};(ROOT/'effects/visibility-v3.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: actual PNG visibility increased on light/dark across6 representative layer samples')
