from pathlib import Path
import json,hashlib,re,subprocess
from PIL import Image
import numpy as np
R=Path(__file__).resolve().parent
results={}
for group in ['drag-left','drag-right','gaze']:
 g=R/group;rs=json.loads((g/'sources.json').read_text());assert len(rs)==16
 hashes=[]
 for r in rs:
  p=Path(r['path']);assert hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256'];a=np.array(Image.open(p));hashes.append(hashlib.sha256(a.tobytes()).hexdigest());assert not max(a[0,:,3].max(),a[-1,:,3].max(),a[:,0,3].max(),a[:,-1,3].max())
 assert len(set(hashes))==16
 v=json.loads((g/'review/validation.json').read_text());assert v['media']['night.webp']['duration_ms']==3200 and v['media']['night.webp']['frames']==64
 assert v['media']['character.webp']['duration_ms']==(3200 if group=='gaze' else 1600)
 results[group]={'full_character_sources':16,'unique_decoded_drawings':16,'border_alpha':0,'duration_verified':True,'whole_body_independent_sources':True}
with Image.open(R/'gaze/review/background.webp') as im:
 im.seek(0);a=np.array(im.convert('RGBA'));im.seek(8);b=np.array(im.convert('RGBA'));assert np.any(a!=b)
results['gaze_fixed_pose_effects']={'independent_background_samples':64,'different_at_0_and_400ms':True}
for path in [R/'index.html',R.parent.parent/'review-gallery-20261105/index.html']:
 s=path.read_text();scripts=re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>',s,re.S)
 for i,j in enumerate(scripts):
  if j.strip().startswith('['):json.loads(j);continue
  p=R/'review-js.tmp.js';p.write_text(j);q=subprocess.run(['/opt/homebrew/bin/node','--check',str(p)],capture_output=True,text=True);assert q.returncode==0,q.stderr
(R/'review-js.tmp.js').unlink(missing_ok=True)
results['html_syntax']=True
old=json.loads((R.parent/'gaze-left-v1-20261106/gallery-lock.json').read_text())
page=(R.parent.parent/'review-gallery-20261105/index.html').read_text()
current=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',page,re.S).group(1))
for state,item in old.items():
 now=next(z for z in current if z['id']==item['id'])
 for layer in ['character','effect']:assert now[layer]['sha256']==item[layer]['sha256'],(state,layer)
results['original_seven_states_unchanged']=True
(R/'verification.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results))
