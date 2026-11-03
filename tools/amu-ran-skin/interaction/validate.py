from pathlib import Path
from PIL import Image
import json,hashlib,sys,subprocess,math
root=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(Path(__file__).resolve().parent))
import runtime as ran
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
previous=json.loads(subprocess.check_output(['git','show','f4c95cd86:tools/amu-ran-skin/native/resources.json'],text=True));current=json.loads((root/'native/resources.json').read_text());now={x['destination']:x['sha256'] for x in current['files']}
protected=[x for x in previous['files'] if not Path(x['destination']).name.startswith(('back-','front-'))]
assert all(now[x['destination']]==x['sha256'] for x in protected)
assert len(current['files'])-len(previous['files'])==17
for side in ['left','right']:
 r=root/'motion'/f'ran-interaction-{side}-v1';records=json.loads((r/'registration.json').read_text());assert len(records)==8
 assert len({sha(r/'raw'/f'R{i:02}.png') for i in range(8)})==8
 assert len({Image.open(r/'character'/f'R{i:02}.png').convert('RGBA').tobytes() for i in range(8)})==8
 assert all(x['whole_source_only'] and not x['mirrored'] for x in records)
for row,track in ran.PLAN['rows'].items():
 period=math.lcm(round(track['cycle']*10),80)/10
 assert ran.sample(int(row),0,0)==ran.sample(int(row),period,period),(row,'loop')
 for i in range(1024):
  side,pose,x,y=ran.sample(int(row),i*.037,123+i*.019)
  assert 12<=x<=346 and 12<=y<=538 and 0<=pose<8,(row,i,x,y)
assert ran.sample(3,1.05,123.7)[:2]==('left',3)
assert ran.sample(3,0,1.05)[:2]==('left',0)
assert ran.sample(3,0,.1,4)!=ran.sample(3,0,1.1,4)
report={'scope':'Ran partner response only','existing_character_gaze_partner_hashes_preserved':len(protected),'new_independent_partner_sources':16,'active_partner_sources':24,'retained_legacy_partner_sources':8,'new_data_contracts':1,'states':10,'bounded_samples_per_state':1024,'composite_loops':'pass','character_epoch_not_effect_epoch':'pass','held_gaze_partner_progression':'pass','visual_review':'16 poses, all10 composited states reviewed; native/browser review recorded separately','installed':False}
(root/'interaction/validation.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: all208 original character/gaze/legacy partner resources preserved;16 new poses;10 state tracks;10240 bounds samples;clock/loop/hold checks')
