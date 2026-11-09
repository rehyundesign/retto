"""Record a bounded effect-only repair with the pre-edit character lock."""
from pathlib import Path
import json,hashlib,subprocess,sys
ROOT=Path(__file__).resolve().parent;OLD=ROOT.parent/'running-v3-proportion-20261105';SKILL=Path('/Users/luxia/.codex/skills/retto-skin')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ref(p):return {'path':str(p.resolve()),'sha256':sha(p)}
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
lock=json.loads((ROOT/'pre-edit-lock.json').read_text());sources=[]
for ident,digest in lock['source_sha256'].items():
    p=OLD/'character'/f'{ident}.png';assert sha(p)==digest
    sources.append({'id':ident,**ref(p),'method':'existing complete independent drawing, retained byte-for-byte'})
write(ROOT/'sources.json',sources)
write(ROOT/'retained-map.json',{'playback_ids':[s['id'] for s in sources],'source_sha256':lock['source_sha256'],'pose_ms':200,'cycle_ms':3200})
t=json.loads((ROOT/'task.json').read_text());t.update(status='effect-only review candidate; user approval pending',renderer=ref(ROOT/'render.py'),approved_character_lock=ref(ROOT/'pre-edit-lock.json'),repair_checks=ref(ROOT/'review/repair-validation.json'),original_registration='inherited unverified; no anatomical redraw or native installation')
write(ROOT/'task.json',t)
checks={
 'identity_eyes':{'status':'pass','finding':'All16 final1x cells inspected light/dark; original character PNGs/animation exact, all RGBA outside glass unchanged; eyes and faces unaffected.'},
 'anatomy_grip':{'status':'pass','finding':'Existing16 whole drawings, paws/prop grip/size and turntable motion preserved byte-for-byte; no new anatomical certification claimed.'},
 'material_canon':{'status':'pass','finding':'Gentle gold/opal/cyan/lilac glass glints reviewed within actual per-frame dome registration; original dome rim/base/crystal design retained.'},
 'secondary_motion':{'status':'unverified','finding':'Existing character motion unchanged; added64 continuous light samples and frozen-pose change checked; actual live/native playback not observed.'},
 'legibility':{'status':'pass','finding':'All16 updated dome cells inspected at224px width dark/light; extra interior glow and cross glints readable without bloom outside glass or changed alpha.'},
 'loop_return':{'status':'unverified','finding':'3.2s export and periodic light/frozen-pose checks; actual native state-return playback not observed.'}}
visual={'source_sha256':lock['source_sha256'],'gif_sha256':sha(ROOT/'review/running.gif'),'runtime_size_comparison':ref(ROOT/'review/runtime-dark.png'),'checks':checks,'native_installed':False}
write(ROOT/'review/visual.json',visual)
run=json.loads((SKILL/'references/production-run.template.json').read_text());run.update(mode='effect-repair',repo=str(ROOT.parents[3]),task_record=ref(ROOT/'task.json'),references={'original_retto':ref(OLD/'references/original-identity.png'),'material':ref(ROOT.parent/'running-v1-20261105/references/material.png')},body_profiles=ref(OLD/'body-profiles.json'),approved_character_lock=ref(ROOT/'pre-edit-lock.json'))
g=run['groups'][0];g.update(id='running-musicbox-glow',view_stance='airborne-front-holding-prop',body_profile='original-airborne-hold-front',costume_master=ref(OLD/'character/00.png'),drawing_policy={'retained_count':16,'retained_map':ref(ROOT/'retained-map.json'),'reason':'user requested subtle extra dome light only; retained original independent character drawings and clocks'},pose_durations_ms=[200]*16,cycle_ms=3200,runtime_states=['running'],review_gif=ref(ROOT/'review/running.gif'),transparent_animation=ref(ROOT/'review/night.webp'),visual_review=ref(ROOT/'review/visual.json'),source_provenance=ref(ROOT/'sources.json'),approved_character_lock=ref(ROOT/'pre-edit-lock.json'))
for r,s in zip(sources,g['sources']):s.update({'path':r['path'],'sha256':r['sha256']})
write(ROOT/'production-run.json',run)
subprocess.run([sys.executable,str(SKILL/'scripts/validate_production_run.py'),str(ROOT/'production-run.json'),'--stage','motion','--output',str(ROOT/'review/production-validation.json')],capture_output=True,text=True)
v=json.loads((ROOT/'review/production-validation.json').read_text());print({'production_ok':v['ok'],'inherited_unverified_errors':len(v['errors']),'groups':v['groups']})
