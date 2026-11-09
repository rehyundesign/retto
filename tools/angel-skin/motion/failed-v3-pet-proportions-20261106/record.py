"""Scope/evidence record; canonical original landmarks remain unverified."""
from pathlib import Path
import json,hashlib,subprocess,sys
ROOT=Path(__file__).resolve().parent;SKILL=Path('/Users/luxia/.codex/skills/retto-skin')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ref(p):return {'path':str(p.resolve()),'sha256':sha(p)}
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
records=json.loads((ROOT/'sources.json').read_text());t=json.loads((ROOT/'task.json').read_text())
t.update(status='same-pose pet-size repair review candidate; user approval pending',retained_main_drawings=16,pose_ms=200,effect_ms=50,cycle_ms=3200,original_registration='unverified original landmark certification',native_installed=False,renderer=ref(ROOT/'render.py'),sources=ref(ROOT/'sources.json'))
write(ROOT/'task.json',t)
keys=['face_box','torso_box','body_center_x','foot_baseline_y','tail_anchor','eye_line_y']
profile={'schema_version':1,'original_sha256':sha(ROOT/'references/runtime-base.png'),'measurement_method':'isolated-character-landmarks','profiles':{'canonical-seated-crying':{'canonical_cell':'approved concept-v5; original quantitative landmarks unverified',**{k:None for k in keys}}}}
write(ROOT/'body-profiles.json',profile)
run=json.loads((SKILL/'references/production-run.template.json').read_text())
run.update(mode='still-repair',repo=str(ROOT.parents[3]),task_record=ref(ROOT/'task.json'),references={'original_retto':ref(ROOT/'references/runtime-base.png'),'approved_design':ref(ROOT/'references/canonical-master.png'),'material':ref(ROOT/'references/material.png')},body_profiles=ref(ROOT/'body-profiles.json'))
g=run['groups'][0];g.update(id='failed-pet-size-only',view_stance='seated-crying-comfort',body_profile='canonical-seated-crying',costume_master=ref(ROOT/'character/00.png'),pose_durations_ms=[200]*16,cycle_ms=3200,runtime_states=['failed'],review_gif=ref(ROOT/'review/failed.gif'),source_provenance=ref(ROOT/'sources.json'),transparent_animation=ref(ROOT/'review/night.webp'))
for r,s in zip(records,g['sources']):s.update(ref(ROOT/r['path']))
write(ROOT/'production-run.json',run)
subprocess.run([sys.executable,str(SKILL/'scripts/validate_production_run.py'),str(ROOT/'production-run.json'),'--stage','anchor','--output',str(ROOT/'review/production-validation.json')],capture_output=True,text=True)
v=json.loads((ROOT/'review/production-validation.json').read_text());print({'stage':'anchor','ok':v['ok'],'unverified_errors':len(v['errors'])})
