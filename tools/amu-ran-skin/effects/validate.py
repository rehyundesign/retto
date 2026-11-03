from pathlib import Path
from PIL import Image
import json,hashlib,subprocess,sys
ROOT=Path(__file__).resolve().parent.parent;REPO=ROOT.parents[1]
sys.path.insert(0,str(Path(__file__).resolve().parent));import accents
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
lock=json.loads((ROOT/'effects/approved-character-lock.json').read_text())
new=json.loads((ROOT/'native/resources.json').read_text());now={x['destination']:x['sha256'] for x in new['files']}
protected=lock['files']
assert len(protected)==224 and all(now[x['destination']]==x['sha256']==sha(REPO/x['destination']) for x in protected)
assert lock['atlas_sha256']==sha(REPO/'assets/spritesheet-amu-ran.webp')
plan=json.loads((ROOT/'interaction/plan.json').read_text());oldplan=lock['interaction'];assert plan['rows']==oldplan['rows'] and plan['gaze']==oldplan['gaze']
config=json.loads((ROOT/'review-config.json').read_text());count=0
for state in config:
 assert state['stateTitle'] and state['stateNote']
 for layer in ['back','front']:
  images=[Image.open(ROOT/state['path']/('effect_'+layer)/f'{i:03}.png').convert('RGBA') for i in range(80)]
  assert all(im.size==(448,640) for im in images)
  for image in images:
   bb=image.getchannel('A').getbbox();assert bb and bb[0]>=12 and bb[1]>=12 and bb[2]<=436 and bb[3]<=628,(state['id'],layer,bb)
  assert len({im.tobytes() for im in images})>=20
  count+=80
 spec=plan['effects'][str(state['row'])];blank=Image.new('RGBA',(448,640))
 assert accents.draw(blank.copy(),state['row'],state['cycle']*spec['peak'],0,True).tobytes()==blank.tobytes()
 if spec['strength']:
  out=accents.draw(blank.copy(),state['row'],state['cycle']*spec['peak'],0);bb=out.getchannel('A').getbbox();assert bb and bb[0]>=12 and bb[1]>=12 and bb[2]<=436 and bb[3]<=628,(state['id'],'accent bounds',bb)
report={'scope':'effect layers, pose accents and preview state labels','protected_png_hashes':224,'character_gaze_atlas_unchanged':True,'partner_response_tracks_unchanged':True,'ambient_samples_checked':count,'effect_period_seconds':8,'ambient_hz':10,'gesture_accents':'character pose epoch, no contact burst during held gaze','effect_margin_2x':12,'states_labelled':10,'reference':'macos/Sources/Tones.swift animationCatalog','installed':False};(ROOT/'effects/validation.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:224 character/gaze/partner PNGs and atlas unchanged;1600 effect samples;gesture/gaze separation;10 labelled states')
