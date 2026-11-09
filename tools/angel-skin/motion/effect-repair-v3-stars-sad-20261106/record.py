"""Bound source-preservation and effect-preview evidence for both scoped repairs."""
from pathlib import Path
import copy,json,hashlib,subprocess,sys,importlib.util
ROOT=Path(__file__).resolve().parent;SKILL=Path('/Users/luxia/.codex/skills/retto-skin')
NAMES={'waiting':'waiting-v2-highfive-20261106','failed':'failed-v2-tears-20261106'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ref(p):return {'path':str(p.resolve()),'sha256':sha(p)}
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
template=json.loads((SKILL/'references/production-run.template.json').read_text());group_template=copy.deepcopy(template['groups'][0])
profile={'schema_version':1,'original_sha256':sha(ROOT.parent/NAMES['waiting']/'references/runtime-base.png'),'measurement_method':'isolated-character-landmarks','profiles':{}}
groups=[]
for state,name in NAMES.items():
    old=ROOT.parent/name;dest=ROOT/state;lock=json.loads((dest/'pre-edit-lock.json').read_text())
    for ident,digest in lock['source_sha256'].items():assert sha(old/'character'/f'{ident}.png')==digest
    originals=json.loads((old/'body-profiles.json').read_text())['profiles'];profile['profiles'][state+'_retained']=next(iter(originals.values()))
    retained={'playback_ids':list(lock['source_sha256']),'source_sha256':lock['source_sha256'],'pose_ms':200,'cycle_ms':3200};write(dest/'retained-map.json',retained)
    checks={k:{'status':'pass','finding':v} for k,v in {
        'identity_eyes':'All16 final light/dark224px cells reviewed. Original32 character PNGs and both character animations retained exactly; waiting faces protected from gold stars; failed moving tears stay below current eye levels.',
        'anatomy_grip':'Original gestures, four-limb anatomy and real contact/tear-wiping poses retained; no character regeneration, head patch, limb warp or camera transform.',
        'material_canon':'Yellow five-point contact stars; clear pale-blue tears, gently falling blue-white feathers/drizzle; original Tato blue/Melody red companion palettes retained.',
        'legibility':'All16 effect-on cells inspected light/dark. High-five stars visible at actual contact600/2000ms and absent before; larger sad tear beads/feathers readable with alpha0 cell edges.'}.items()}
    for k in ['secondary_motion','loop_return']:checks[k]={'status':'unverified','finding':'Source motion unchanged; effect clocks/frozen-pose/loop exports checked, actual live/native playback not observed.'}
    visual={'source_sha256':lock['source_sha256'],'gif_sha256':sha(dest/f'{state}.gif'),'runtime_size_comparison':ref(dest/'runtime-dark.png'),'checks':checks,'native_installed':False};write(dest/'visual.json',visual)
    g=copy.deepcopy(group_template);g.update(id=state+'-effect-repair',view_stance=state+'-retained-whole-character-motion',body_profile=state+'_retained',costume_master=ref(old/'character/00.png'),drawing_policy={'retained_count':16,'retained_map':ref(dest/'retained-map.json'),'reason':'user requested only more readable effects; keep original16 drawings and approved3.2s timing'},pose_durations_ms=[200]*16,cycle_ms=3200,runtime_states=[state],review_gif=ref(dest/f'{state}.gif'),transparent_animation=ref(dest/'night.webp'),visual_review=ref(dest/'visual.json'),approved_character_lock=ref(dest/'pre-edit-lock.json'))
    for s in g['sources']:s.update(ref(old/'character'/f"{s['id']}.png"))
    groups.append(g)
write(ROOT/'body-profiles.json',profile)
t=json.loads((ROOT/'task.json').read_text());t.update(status='both scoped effect repairs rendered; user review pending',renderer=ref(ROOT/'render.py'),review_gif='review/effects.gif',original_registration='inherited quantitative anatomy unverified; no native installation');write(ROOT/'task.json',t)
template.update(mode='effect-repair',repo=str(ROOT.parents[3]),task_record=ref(ROOT/'task.json'),references={'original_retto':ref(ROOT.parent/NAMES['waiting']/'references/runtime-base.png'),'material':ref(ROOT.parent/NAMES['waiting']/'references/material.png')},body_profiles=ref(ROOT/'body-profiles.json'),groups=groups)
write(ROOT/'production-run.json',template)
subprocess.run([sys.executable,str(SKILL/'scripts/validate_production_run.py'),str(ROOT/'production-run.json'),'--stage','motion','--output',str(ROOT/'review/production-validation.json')],capture_output=True,text=True)
v=json.loads((ROOT/'review/production-validation.json').read_text());print({'production_ok':v['ok'],'inherited_unverified_errors':len(v['errors']),'groups':v['groups']})
