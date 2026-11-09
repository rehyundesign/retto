"""Record scoped same-pose eye repair without claiming original/native certification."""
from pathlib import Path
import json,hashlib
ROOT=Path(__file__).resolve().parent
OLD=ROOT.parent/'jumping-v2-trio-flight-20261105'
SKILL=Path('/Users/luxia/.codex/skills/retto-skin')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ref(p):return {'path':str(p.resolve()),'sha256':sha(p)}
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
t=json.loads((ROOT/'task.json').read_text());t.update(status='completed wink repair; user review pending',retained_complete_drawings=16,same_pose_eye_repairs=16,review_gif='review/jumping.gif',transparent_animation='review/night.webp',original_registration='inherited unverified',native_installed=False)
write(ROOT/'task.json',t)
records=json.loads((ROOT/'sources.json').read_text())
visual={'source_sha256':{r['id']:r['sha256'] for r in records},'gif_sha256':sha(ROOT/'review/jumping.gif'),'user_approval':'pending','native_installed':False,'checks':{'identity_eyes':{'status':'pass','finding':'All16 completed cells inspected together.05..08 share a screen-left wink; right eye remains open. Tato dot/^ and Melody rectangle/curved wink retained.'},'protected_pixels':{'status':'pass','finding':'Character alpha exact; all RGBA outside eye masks exact; original16 body drawings, original48 effect samples and2.4s cadence retained.'},'registration':{'status':'unverified','finding':'Original anatomical landmarks remain unmeasured; source registration inherited without geometric edits.'},'live_playback':{'status':'unverified','finding':'Offline decoded media and boards checked; native rendering not observed.'}}}
write(ROOT/'review/visual.json',visual)
run=json.loads((SKILL/'references/production-run.template.json').read_text());run.update(mode='still-repair',repo=str(ROOT.parents[3]),task_record=ref(ROOT/'task.json'),references={'original_retto':ref(OLD/'references/original-identity.png'),'material':ref(ROOT.parent/'running-v1-20261105/references/material.png')},body_profiles=ref(OLD/'body-profiles.json'))
g=run['groups'][0];g.update(id='jumping-trio-wink',view_stance='retained-frontal-click',body_profile='original-frontal-click',costume_master=ref(OLD/'character/00.png'),drawing_policy={'retained_count':16,'retained_map':[r['original_path'] for r in records],'reason':'same-pose protected eyelid repair of retained independent complete drawings'},pose_durations_ms=[150]*16,cycle_ms=2400,runtime_states=['jumping'],review_gif=ref(ROOT/'review/jumping.gif'),visual_review=ref(ROOT/'review/visual.json'),source_provenance=ref(ROOT/'sources.json'),transparent_animation=ref(ROOT/'review/night.webp'))
for r,s in zip(records,g['sources']):s.update(ref(ROOT/r['path']))
write(ROOT/'production-run.json',run)
