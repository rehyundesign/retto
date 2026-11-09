"""Record retained complete drawings separately from boundary-corrected exports."""
from pathlib import Path
import hashlib,json,os,subprocess
ROOT=Path(__file__).resolve().parent
OLD=ROOT.parent/'night-effects-v1-20261105'
STATES=['idle','waiting','failed','waving','jumping']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(exist_ok=True,parents=True);p.write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n')
def ref(p):return {'path':str(p.resolve()),'sha256':sha(p)}
def absolute_refs(v,base):
    if isinstance(v,dict):
        if isinstance(v.get('path'),str):v['path']=str((base/v['path']).resolve())
        for x in v.values():absolute_refs(x,base)
    elif isinstance(v,list):
        for x in v:absolute_refs(x,base)

write(ROOT/'task.json',{'mode':'effect-repair','scope':'five existing motions; remove enclosed white-background pockets and faint background noise; no new pose or timing',
    'states':STATES,'protected':'complete original pose files, interior RGB, eyes, paws, companions, effects and cadence',
    'method':'RGB-locked neutral-white background-component alpha extraction and alpha-noise floor16; protect maroon-eye white borders',
    'status':'negative-space matte repair candidate;80 changed cells inspected on light/dark boards; original landmark/native/live playback unverified',
    'known_inherited_failure':'jumping remains old unfinished draft with02/05/06/12 scale/support defects; no replacement click requested here',
    'native_installed':False})
run=None
for state in STATES:
    old=OLD/state/'production-run.json';r=json.loads(old.read_text());absolute_refs(r,old.parent)
    if run is None:run=r;run['groups']=[]
    g=r['groups'][0] if r is not run else json.loads(old.read_text())['groups'][0]
    if r is run:absolute_refs(g,old.parent)
    g['id']='matte-repair-'+state
    lock={'source_sha256':{s['id']:s['sha256'] for s in g['sources']}}
    write(ROOT/'locks'/f'{state}.json',lock)
    g['approved_character_lock']=ref(ROOT/'locks'/f'{state}.json')
    checks={
      'identity_eyes':{'status':'pass','finding':'All16 repaired cells inspected on light/dark boards; protected interior RGB exactly unchanged; Tato dots/^^ and Melody rectangular eyes retained.'},
      'anatomy_grip':{'status':'repair' if state=='jumping' else 'pass','finding':'Existing complete poses retained without geometry changes.'+(' Inherited unfinished click02/05/06/12 scale/support defects remain.' if state=='jumping' else ' Four limbs and companion positions remain as original.')},
      'material_canon':{'status':'pass','finding':'Same source drawings; all RGB unchanged; alpha changed for white background pockets and noise only.'},
      'secondary_motion':{'status':'unverified','finding':'All16 effects-off cells inspected; live playback at native draw size not directly verified.'},
      'legibility':{'status':'pass','finding':'All16 changed cells inspected on dark/light boards; opaque white background pockets between wings/body/companions and tail loops removed; faint alpha noise removed; legitimate ivory fur and rabbit eye whites retained.'},
      'loop_return':{'status':'unverified','finding':'Original source order/pose durations/effect clocks unchanged and export duration checked; live state-return not observed.'}}
    visual={'source_sha256':lock['source_sha256'],'gif_sha256':sha(ROOT/state/'preview.gif'),
       'runtime_size_comparison':ref(ROOT/state/'poses-dark.png'),'checks':checks}
    write(ROOT/state/'visual.json',visual)
    g['review_gif']=ref(ROOT/state/'preview.gif');g['visual_review']=ref(ROOT/state/'visual.json')
    g['transparent_animation']=ref(ROOT/state/'night.webp')
    g['display_matte_provenance']=ref(ROOT/state/'validation.json')
    run['groups'].append(g)
run['task_record']=ref(ROOT/'task.json');run['native_review']=None
write(ROOT/'production-run.json',run)
result=subprocess.run(['/private/tmp/retto-gaze-20261104-venv/bin/python','/Users/luxia/.codex/skills/retto-skin/scripts/validate_production_run.py',str(ROOT/'production-run.json'),'--stage','motion','--output',str(ROOT/'motion-check.json')],stdout=subprocess.DEVNULL)
print(json.dumps({'production_check_exit':result.returncode,'expected_unverified':'original landmarks, native/live secondary motion and return; inherited click defects','groups':len(run['groups'])}))
