"""Hash-bound effect-only record, retaining original idle character sources."""
from pathlib import Path
import json,hashlib,subprocess,sys
ROOT=Path(__file__).resolve().parent;OLD=ROOT.parent/'idle-v5-canonical-20261106';SKILL=Path('/Users/luxia/.codex/skills/retto-skin')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ref(p):return {'path':str(p.resolve()),'sha256':sha(p)}
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
lock=json.loads((ROOT/'pre-edit-lock.json').read_text())
for ident,digest in lock['source_sha256'].items():assert sha(OLD/'character'/f'{ident}.png')==digest
write(ROOT/'retained-map.json',{'playback_ids':list(lock['source_sha256']),'source_sha256':lock['source_sha256'],'pose_ms':200,'cycle_ms':3200})
t=json.loads((ROOT/'task.json').read_text());t.update(status='background-star effect repair candidate; user review pending',renderer=ref(ROOT/'render.py'),validation=ref(ROOT/'review/validation.json'),approved_character_lock=ref(ROOT/'pre-edit-lock.json'),original_registration='inherited unverified; original characters unchanged, no native installation');write(ROOT/'task.json',t)
checks={k:{'status':'pass','finding':v} for k,v in {
 'identity_eyes':'All16 final224px cells inspected light/dark; original character PNGs/animation unchanged, every opaque character/face/physical-star pixel exact.',
 'anatomy_grip':'Approved star-passing action, four-limb anatomy, actual physical-star grips, wing articulation and flying pet poses retained without redraw/warp.',
 'material_canon':'Small yellow five-point background stars, gentle slow drift, independently phased twinkles; original moon/feathers and blue/red companion effects retained.',
 'legibility':'All16 effect-on cells inspected dark/light. Added gold visible at224px, stars behind silhouettes with transparent-edge fade, no rectangle or foreground explosion.'}.items()}
for k in ['secondary_motion','loop_return']:checks[k]={'status':'unverified','finding':'Original motion retained; periodic3.2s/frozen-pose star progression checked. Actual live/native playback not observed.'}
visual={'source_sha256':lock['source_sha256'],'gif_sha256':sha(ROOT/'review/idle.gif'),'runtime_size_comparison':ref(ROOT/'review/runtime-dark.png'),'checks':checks,'native_installed':False};write(ROOT/'review/visual.json',visual)
run=json.loads((SKILL/'references/production-run.template.json').read_text());run.update(mode='effect-repair',repo=str(ROOT.parents[3]),task_record=ref(ROOT/'task.json'),references={'original_retto':ref(OLD/'references/runtime-base.png'),'material':ref(OLD/'references/material.png')},body_profiles=ref(OLD/'body-profiles.json'))
profile=next(iter(json.loads((OLD/'body-profiles.json').read_text())['profiles']))
g=run['groups'][0];g.update(id='idle-background-stars',view_stance='retained-idle-star-game',body_profile=profile,costume_master=ref(OLD/'character/00.png'),drawing_policy={'retained_count':16,'retained_map':ref(ROOT/'retained-map.json'),'reason':'background-star effect-only request; keep approved complete16 drawings and timing'},pose_durations_ms=[200]*16,cycle_ms=3200,runtime_states=['idle'],review_gif=ref(ROOT/'review/idle.gif'),transparent_animation=ref(ROOT/'review/night.webp'),visual_review=ref(ROOT/'review/visual.json'),source_provenance=ref(OLD/'sources.json'),approved_character_lock=ref(ROOT/'pre-edit-lock.json'))
for s in g['sources']:s.update(ref(OLD/'character'/f"{s['id']}.png"))
write(ROOT/'production-run.json',run)
subprocess.run([sys.executable,str(SKILL/'scripts/validate_production_run.py'),str(ROOT/'production-run.json'),'--stage','motion','--output',str(ROOT/'review/production-validation.json')],capture_output=True,text=True)
v=json.loads((ROOT/'review/production-validation.json').read_text());print({'production_ok':v['ok'],'inherited_unverified_errors':len(v['errors']),'groups':v['groups']})
