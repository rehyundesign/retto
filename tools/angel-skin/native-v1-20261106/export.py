"""Keep approved544px scenes; body-derived native fit lives in manifest, not raster resizes."""
from pathlib import Path
import json,re,hashlib
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent;G=ROOT.parent/'review-gallery-20261105';DEST=ROOT/'build/AngelFrames'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
items=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',(G/'index.html').read_text(),re.S)[1]);current={x['state']:x for x in items if x['status']!='archive'}
DEST.mkdir(parents=True,exist_ok=True);manifest={'version':1,'sourceSize':[544,544],'sampleMs':50,'states':{},'fitBasis':'main Retto facial-fur/torso/ear-to-paw landmarks; exclude wings/pets/FX; fixed per-state transforms','reference':'installed ClassicGrownFrames idle00,448x640, ground593 mapped to native628'}
board=Image.new('RGB',(448*4,640*2),'#142035');d=ImageDraw.Draw(board)
base=Image.open(Path.home()/'Applications/Retto.app/Contents/Resources/ClassicGrownFrames/idle/00.png').convert('RGBA');bg=Image.new('RGBA',base.size,'#142035');bg.alpha_composite(base);board.paste(bg.convert('RGB'),(0,0));d.text((5,610),'classic448 reference',fill='white')
for j,(state,item) in enumerate(current.items(),1):
 char=(G/item['character']['src'].split('?')[0]).resolve();fx=(G/item['effect']['src'].split('?')[0]).resolve();assert sha(char)==item['character']['sha256'] and sha(fx)==item['effect']['sha256']
 folder=DEST/state;folder.mkdir(exist_ok=True)
 with Image.open(char) as im:im.seek(0);first=im.convert('RGBA')
 # Provisional common seated body scale from manual original-body comparison;
 # genuine sleeping stance has a distinct fit and support line.
 fit=1.06;ground=468 if state=='sleeping' else 484
 with Image.open(fx) as im:
  total=0
  for i in range(im.n_frames):
   im.seek(i);im.load();im.convert('RGBA').save(folder/f'{i:03}.png');total+=im.info['duration']
  assert total==item['effect']['ms']
  manifest['states'][state]={'samples':im.n_frames,'sampleMs':total/im.n_frames,'cycle':total/1000,'poseMs':total/16,'drawings':16,'bodyScale':fit,'ground':ground,'characterSource':str(char),'characterSha256':sha(char),'effectSource':str(fx),'effectSha256':sha(fx)}
 out=first.resize((round(544*fit),round(544*fit)),Image.Resampling.LANCZOS);tile=Image.new('RGBA',(448,640),'#142035');tile.alpha_composite(out,(round(224-out.width/2),round(593-ground*fit)));x=j%4*448;y=j//4*640;board.paste(tile.convert('RGB'),(x,y));d.text((x+5,y+610),state,fill='white')
(DEST/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');board.save(ROOT/'review/body-fit-first-pass.png');print('Exported current7 states with exact source clocks, no raster refit')
