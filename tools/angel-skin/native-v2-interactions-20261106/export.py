from pathlib import Path
import json,shutil,hashlib
from PIL import Image
R=Path(__file__).resolve().parent;M=R.parent/'motion';I=M/'interactions-v2-20261106';O=R/'build/AngelInteractions';O.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
manifest={'version':1,'idle':None,'flight':{},'gaze':None,'body_camera':{'reference_units':448,'source_size':544,'body_scale':1.06,'ground':484},'original_seven_states':'unchanged'}
source_records={}
def clip(key,p,pose):
 d=O/key;d.mkdir(exist_ok=True)
 with Image.open(p) as im:
  for n in range(im.n_frames):im.seek(n);im.convert('RGBA').save(d/f'{n:03}.png')
  count=im.n_frames
 assert count==64
 source_records[key]={'source':str(p.resolve()),'sha256':sha(p)}
 return {'samples':count,'cycle':3.2,'sampleMs':50,'drawings':16,'poseMs':pose}
manifest['idle']=clip('idle-look',M/'gaze-left-v1-20261106/review/night.webp',200)
for key in ['drag-left','drag-right']:manifest['flight'][key]=clip(key,I/key/'review/night.webp',100)
for key in ['gaze','gaze-back']:
 (O/key).mkdir(exist_ok=True)
 source=I/key/'character' if key=='gaze' else I/key
 for p in source.glob('*.png'):shutil.copy2(p,O/key/p.name)
rs=json.loads((I/'gaze/sources.json').read_text());manifest['gaze']={'count':16,'samples':64,'cycle':3.2,'anchors':[r['attachment_proxies'] for r in rs]}
(O/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(R/'resource-map.json').write_text(json.dumps({'sources':source_records,'files':{str(p.relative_to(O)):sha(p) for p in O.rglob('*') if p.is_file()}},indent=2)+'\n')
print('Exported',len(list(O.rglob('*.png'))),'PNG; idle variation, left/right flight and16 gaze, independent50ms effects')
