"""Hash-bind this motion study without claiming unmeasured original registration."""
from pathlib import Path
import hashlib,json,os

ROOT=Path(__file__).resolve().parent
SKILL=Path('/Users/luxia/.codex/skills/retto-skin')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ref(p):return {'path':os.path.relpath(p,ROOT),'sha256':sha(p)}
def write(p,v):p.write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n')

task=json.loads((ROOT/'task.json').read_text())
task.update(status='new music-box motion candidate; user visual review pending',
            character_sources_generated=16,selected_gif='review/running.gif',
            selected_animation='review/night.webp',
            next_stage='user review of this working motion only; original registration/native verification remain unverified')
write(ROOT/'task.json',task)
template=json.loads((SKILL/'references/production-run.template.json').read_text())
profiles=json.loads((ROOT.parent/'running-v1-20261105/body-profiles.json').read_text())
profiles['profiles']={'original-airborne-hold-front':{
    'canonical_cell':'Original airborne music-box hold equivalent not present; anatomical landmark certification pending',
    **{k:None for k in ['face_box','torso_box','body_center_x','foot_baseline_y','tail_anchor','eye_line_y']}}}
profiles['measurement_method']='unverified: original airborne pose comparison required; no silhouette-derived measurements'
write(ROOT/'body-profiles.json',profiles)
template.update(repo=str(ROOT.parents[3]),task_record=ref(ROOT/'task.json'),
                references={'original_retto':ref(ROOT/'references/original-identity.png'),
                            'material':ref(ROOT.parent/'running-v1-20261105/references/material.png')},
                body_profiles=ref(ROOT/'body-profiles.json'))
g=template['groups'][0]
g.update(id='running-musicbox-airborne',view_stance='airborne-front-holding-prop',
         body_profile='original-airborne-hold-front',costume_master=ref(ROOT/'raw/00.png'),
         pose_durations_ms=[200]*16,cycle_ms=3200,runtime_states=['running'])
for i,s in enumerate(g['sources']):s.update(ref(ROOT/'character'/f'{i:02}.png'))
g['review_gif']=ref(ROOT/'review/running.gif')
g['visual_review']=ref(ROOT/'review/visual.json')
g['transparent_animation']=ref(ROOT/'review/night.webp')
write(ROOT/'production-run.json',template)
