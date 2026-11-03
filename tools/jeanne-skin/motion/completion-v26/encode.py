from pathlib import Path
from PIL import Image
import json,hashlib
p=Path(__file__).parent;root=p.parent
manifest=json.loads((p/'manifest.json').read_text())
checks=[]
for theme,color in [('dark','#181827'),('white','#fffdf8')]:
 frames=[]
 for record in manifest['frames']:
  im=Image.open(root/record['file']).convert('RGBA').resize((224,320),Image.Resampling.LANCZOS)
  bg=Image.new('RGBA',im.size,color);bg.alpha_composite(im);frames.append(bg.convert('RGB'))
 file=p/('animation-'+theme+'.webp')
 frames[0].save(file,save_all=True,append_images=frames[1:],duration=150,loop=0,lossless=True)
 decoded=Image.open(file);assert decoded.n_frames==16
 durations=[];pixels=[]
 for i in range(16):
  decoded.seek(i);decoded.load();durations.append(decoded.info['duration']);pixels.append(hashlib.sha256(decoded.convert('RGB').tobytes()).hexdigest())
 assert durations==[150]*16 and len(set(pixels))==16
 checks.append({'theme':theme,'frames':16,'distinctDecodedFrames':16,'durationsMs':durations,'totalMs':sum(durations)})
for record in manifest['frames']:
 assert hashlib.sha256((root/record['source']).read_bytes()).hexdigest()==record['sha256']
for record in json.loads((p/'lock.json').read_text()):
 assert hashlib.sha256((root/record['file']).read_bytes()).hexdigest()==record['hash']
for row in json.loads((p/'rows.json').read_text()):
 for file in row['files']+[a['file'] for a in row['animations']]:assert (root/file).exists(),file
(p/'encoded-checks.json').write_text(json.dumps(checks,indent=2))
print(json.dumps(checks));print('All16 sources and144 protected images verified;10-state preview paths exist.')
