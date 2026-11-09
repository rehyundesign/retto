"""Hash-bound review candidate; original anatomical/native certification remains separate."""
from pathlib import Path
import hashlib,json

ROOT=Path(__file__).resolve().parent
SKILL=Path('/Users/luxia/.codex/skills/retto-skin')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ref(p):return {'path':str(p.resolve()),'sha256':sha(p)}
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')

task=json.loads((ROOT/'task.json').read_text())
task.update(status='new shared-flight click review candidate; user approval pending',
    character_drawings_generated=16,selected_independent_drawings=16,generation_attempts=18,
    rejected_source_ids={'02-rejected-deep-crouch':'anticipation too deep, replaced by independent02 redraw',
                         '12-rejected-deep-landing':'landing compression too deep, replaced by independent12 redraw'},
    review_gif='review/jumping.gif',transparent_animation='review/night.webp',
    character_animation='review/character.webp',
    next_stage='user review of this one click motion; no other new state started; original/native registration remains unverified',
    quality_reference={'path':str(SKILL/'assets/quality-baseline/hana-toto-16-half-speed.webp'),
                       'review':'reference board inspected alongside224x320 candidate board; live/native comparison not directly observed'},
    body_registration='complete-drawing rigid y registration using support/ear proxies; common544/1254 resolution conversion; no per-frame silhouette fitting or anatomy warp')
if 'queued_key' in task:task['historical_queued_key']=task.pop('queued_key')
write(ROOT/'task.json',task)
landmarks={k:None for k in ['face_box','torso_box','body_center_x','foot_baseline_y','tail_anchor','eye_line_y']}
profile={'schema_version':1,'original_sha256':sha(ROOT/'references/original-identity.png'),
    'measurement_method':'isolated-character-landmarks','profiles':{'original-frontal-click':{
        'canonical_cell':'original grown Retto frontal identity; actual pose-specific measurements pending; display support proxies are not original registration',**landmarks}}}
write(ROOT/'body-profiles.json',profile)
records=json.loads((ROOT/'sources.json').read_text())
checks={
 'identity_eyes':{'status':'pass','finding':'All16 character-only drawings inspected on dark/light and224x320 boards. Retto frontal small blue-grey eyes, happy closed blink07/08; Tato dots/^^ only; Melody burgundy rectangles retained.'},
 'anatomy_grip':{'status':'pass','finding':'Continuous complete feline anatomy inspected all16. Four main limbs; forepaws bend and rearfeet tuck in05..08, rearfeet partly occluded by extending forelegs in09/10. Both pets lift their feet during05..10 and return to support; no added Tato wings.02/12 redrawn to reduce excessive crouch.'},
 'material_canon':{'status':'pass','finding':'Original cream/brown identity, ivory feathers, white bell-wearing Tato and pink red-bow Melody retained; no held prop or outfit redesign. Main neutral/apex compared to approved idle at544square.'},
 'secondary_motion':{'status':'unverified','finding':'Static16-cell boards show articulated wing strokes, companion arm/foot changes and ear/tail/bow response. Live playback at actual native display size not directly observed.'},
 'legibility':{'status':'pass','finding':'All16 character and effect cells inspected on dark/light backgrounds and224x320 study board. Empty spaces between white parts are transparent, isolated background noise check passed; no effect obscures face or action.'},
 'loop_return':{'status':'unverified','finding':'15->00 support/pose board and2.4s clocks inspected; effect phase0/2400 pixels exactly match. Native transient-to-idle return/live temporal smoothness not directly verified.'}}
visual={'source_sha256':{r['id']:r['sha256'] for r in records},'gif_sha256':sha(ROOT/'review/jumping.gif'),
    'runtime_size_comparison':ref(ROOT/'review/224x320-character-board.png'),'checks':checks,
    'user_approval':'pending','native_installed':False}
write(ROOT/'review/visual.json',visual)
run=json.loads((SKILL/'references/production-run.template.json').read_text())
run.update(repo=str(ROOT.parents[3]),task_record=ref(ROOT/'task.json'),
    references={'original_retto':ref(ROOT/'references/original-identity.png'),
                'material':ref(ROOT.parent/'running-v1-20261105/references/material.png')},
    body_profiles=ref(ROOT/'body-profiles.json'))
g=run['groups'][0];g.update(id='jumping-shared-flight',view_stance='frontal-neutral-takeoff-flight-landing',
    body_profile='original-frontal-click',costume_master=ref(ROOT/'raw/00.png'),
    pose_durations_ms=[150]*16,cycle_ms=2400,runtime_states=['jumping'],
    review_gif=ref(ROOT/'review/jumping.gif'),visual_review=ref(ROOT/'review/visual.json'),
    transparent_animation=ref(ROOT/'review/night.webp'),source_provenance=ref(ROOT/'sources.json'),
    wingtip_emission_landmarks=ref(ROOT/'wingtips.json'))
for i,s in enumerate(g['sources']):s.update(ref(ROOT/'character'/f'{i:02}.png'))
write(ROOT/'production-run.json',run)
