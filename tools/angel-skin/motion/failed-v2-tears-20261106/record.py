"""Record canonical whole-character redraws without claiming native certification."""
from pathlib import Path
import json,hashlib,subprocess,sys
ROOT=Path(__file__).resolve().parent
SKILL=Path('/Users/luxia/.codex/skills/retto-skin')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ref(p):return {'path':str(p.resolve()),'sha256':sha(p)}
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
records=json.loads((ROOT/'sources.json').read_text())
t=json.loads((ROOT/'task.json').read_text())
t.update(status='shared sobbing and tear-wiping failed review candidate; user approval pending',distinct_drawings=16,pose_ms=200,effect_ms=50,cycle_ms=3200,method='16 independently redrawn complete connected characters; no eye/head/neck patches',motion_preservation='new user-requested shared crying, left Tato/right Melody cheek wipes; main4 paws grounded, both pets fly; other state art preserved',references={'approved_design':ref(ROOT/'references/canonical-master.png'),'shipped_runtime_comparison':ref(ROOT/'references/runtime-base.png')},original_registration='unverified quantitative original landmark certification',native_installed=False)
t['effect_helper']=ref(ROOT.parent/'idle-v3-airborne-20261106/render.py');t['renderer']=ref(ROOT/'render.py');t['cell_review']=ref(ROOT/'review/cell-review.json');t['tear_endpoint_board']=ref(ROOT/'review/tear-endpoint-board.png');write(ROOT/'task.json',t)
keys=['face_box','torso_box','body_center_x','foot_baseline_y','tail_anchor','eye_line_y']
profile={'schema_version':1,'original_sha256':sha(ROOT/'references/runtime-base.png'),'measurement_method':'isolated-character-landmarks','profiles':{'canonical-seated-crying':{'canonical_cell':'approved concept-v5; shifted/genuine looking poses require anatomical counterparts; full measurements unverified',**{k:None for k in keys}}}}
write(ROOT/'body-profiles.json',profile)
checks={
 'identity_eyes':{'status':'pass','finding':'All16 final crying cells inspected against canonical concept-v5: natural muzzle/ears/mask/blaze and blue-grey irises retained, sad expression/wet cheeks are user-requested; no eye-size modifiers, Tato dots and Melody burgundy rectangles retained.'},
 'anatomy_grip':{'status':'pass','finding':'All16 changed cells reviewed light/dark: Tato wipes main left cheek03/04 and Melody right10/11, below eye rather than eyeball; main4 paws grounded throughout, pet arms attached continuously, all3 cry, Tato dot eyes and Melody rectangular eyes retained.'},
 'material_canon':{'status':'pass','finding':'Canonical cream/brown cat and attached ivory wings reviewed against master and material reference; both companions retain their approved texture and identities.'},
 'secondary_motion':{'status':'unverified','finding':'16 ordered full drawings reviewed; actual live temporal playback not observed.'},
 'legibility':{'status':'pass','finding':'All16 character-only and effects-on cells inspected at224px width on dark/light; edge alpha zero and all64 effect samples distinct; clear tear beads follow per-frame wet-face endpoints and move below eye level; newly emitted main tears pause during wiping, blue/red comfort effects remain separate from pale tears.'},
 'loop_return':{'status':'unverified','finding':'Ordered adjacent frames and last-to-first compared; 3.2s clocks and effect periodicity checked; live/native transition playback not observed.'}}
visual={'source_sha256':{s['id']:s['sha256'] for s in records},'gif_sha256':sha(ROOT/'review/failed.gif'),'runtime_size_comparison':ref(ROOT/'review/effect-runtime-dark.png'),'checks':checks,'user_approval':'pending','native_installed':False}
write(ROOT/'review/visual.json',visual)
run=json.loads((SKILL/'references/production-run.template.json').read_text())
run.update(mode='new-motion',repo=str(ROOT.parents[3]),task_record=ref(ROOT/'task.json'),references={'original_retto':ref(ROOT/'references/runtime-base.png'),'approved_design':ref(ROOT/'references/canonical-master.png'),'material':ref(ROOT/'references/material.png')},body_profiles=ref(ROOT/'body-profiles.json'))
g=run['groups'][0]
g.update(id='failed-canonical-tears',view_stance='seated-crying-comfort',body_profile='canonical-seated-crying',costume_master=ref(ROOT/'character/00.png'),pose_durations_ms=[200]*16,cycle_ms=3200,runtime_states=['failed'],review_gif=ref(ROOT/'review/failed.gif'),visual_review=ref(ROOT/'review/visual.json'),source_provenance=ref(ROOT/'sources.json'),transparent_animation=ref(ROOT/'review/night.webp'))
for r,s in zip(records,g['sources']):s.update(ref(ROOT/r['path']))
write(ROOT/'production-run.json',run)
subprocess.run([sys.executable,str(SKILL/'scripts/validate_production_run.py'),str(ROOT/'production-run.json'),'--stage','motion','--output',str(ROOT/'review/production-validation.json')],capture_output=True,text=True)
v=json.loads((ROOT/'review/production-validation.json').read_text())
print({'production_ok':v['ok'],'unverified_errors':len(v['errors']),'groups':v['groups']})
