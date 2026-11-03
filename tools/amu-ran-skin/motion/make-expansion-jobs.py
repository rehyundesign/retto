"""Prepare independently generated phases. Existing used sources are never silently replaced."""
from pathlib import Path
import json,sys
root=Path(__file__).resolve().parent;stage=sys.argv[1];states=sys.argv[2:]
phases={
'jumping':{2:'Deeper anticipation crouch than starting pose: all4 paws grounded, short knees/elbows compress, head/body lower together a little, not airborne yet.',6:'Mid-ascent: hind knees tuck toward belly, forepaws curl up, body turns a little toward Ran. Airborne, no grounded duplicate paw; bare furry hindlegs.',10:'Mid-descent: forepaws extend down halfway for landing, bare hindlegs unfold modestly under hips, still compact animal.',14:'Landing recovery: head/body ease up from deepest compression toward starting crouch, paws settle, cape/plume lag and settle.'},
'failed':{2:'Ear tips begin turning back and eyes show brief surprise; right forepaw(viewer-left) just begins leaving ground near lower belly.',6:'Concern grows gently: head tips a little, ears partly folded, actual right paw halfway extending toward Ran, no huge crying face.',10:'Confidence recovers: ears begin reopening, lifted right paw turns inward at LOWER chest, chin lifts slightly; never stand taller.',14:'Actual right paw lowers halfway toward ground, ears nearly normal, soft confident eyes with small natural blink; recover first posture.'},
'waiting':{2:'Right paw(viewer-left) just begins leaving ground, below belly, preparing to cross chest toward left arm band.',6:'Right paw halfway crosses center chest toward red LEFT upper-foreleg armband(viewer-right), almost touching it, other foreleg planted.',10:'After tap, right paw halfway withdraws from LEFT foreleg band toward center lower chest; small glance toward Ran.',14:'Right forepaw lowers from center chest toward ground, still at lower belly; cool calm blink, original compact stature.'},
'running':{2:'Begin heart-unlock: actual right paw(viewer-left) just lifts from floor to lower belly, other foreleg planted.',6:'Right paw approaches CENTER chest over red tie, halfway into Amu heart-unlock concentration. Focused but friendly eyes, no tall belly.',10:'Right paw turns a little outward from center heart area, releasing heart-unlock gesture toward Ran. Other foreleg planted, short seated torso.',14:'Actual right paw descends to lower belly/waist, eyes relax into tiny blink, return neutral. No both-arms human stance.'},
'review':{2:'Actual right paw begins reaching toward collar/lapel; heart charm still tucked and mostly hidden; head starts a gentle curious bow.',6:'Right paw draws small pink/gold heart charm a little out from lapel, partly hidden behind paw. Head looks down to inspect, round3D muzzle remains.',10:'Gently inspect/tap held tiny heart, paw/wrist rotates a little, eyes refocus toward charm, other foreleg and rear paws support.',14:'Tuck tiny heart charm behind lapel again as right paw begins lowering; charm now mostly hidden, head looks back up toward Ran.'},
'sleeping':{2:'Chin begins settling toward actual tucked forepaws, near ear loosens a little, eyes remain closed, curled body unchanged.',6:'Deeper sleep: chin settles halfway deeper on forepaws, one tiny paw tuck and tail curls fractionally closer, no stretching.',10:'Gentle inhale: tiny shoulder/chin rise, eyes closed, curled tail and forepaws softly follow; same original head/body ratio.',14:'Gentle exhale toward first pose: tucked paw relaxes and tail eases fractionally outward, near ear settles, eyes closed.'}}
common_school='Short fitted black blazer, white collar/cuffs, loose red tie, red-black plaid skirt ONLY rear hips behind forelegs. ONE red shield armband on actual LEFT upper foreleg(viewer-right front), right sleeve plain. Pink X left ear(viewer-right).'
common_heart='Broad one-piece white/pale-pink scalloped cape covering shoulders/torso, red trim, layered hip cheer skirt, white/pink cuffs ONLY actual FRONT forelegs; hindlegs bare fur, no socks/garters. White/red visor ONE red heart/plume anatomical-left(viewer-right front), centered Ran-style red scarf with ONE attached pink-black plaid heart Guardian Egg. No foot pompoms or extra necklace.'
jobs=[]
for state in states:
 r=root/(state+'-v1');(r/'requests').mkdir(exist_ok=True)
 ns=[2,6,10,14] if stage=='half' else list(range(1,16,2))
 for n in ns:
  id=f'F{n:02}'
  if (r/'raw'/(id+'.png')).exists():continue
  a,b=(n-2,(n+2)%16) if stage=='half' else (n-1,(n+1)%16)
  if state=='jumping' and n==2 and stage=='half':a=b=0
  refs=[str(r/'character'/f'F{a:02}.png')]
  if a!=b:refs.append(str(r/'character'/f'F{b:02}.png'))
  for p in refs:
   if not Path(p).exists():raise FileNotFoundError(p)
  phase=phases[state][n] if stage=='half' else 'Create the real anatomical halfway transition between these adjacent poses: actual paw/limb position, ear/eyelid expression and cloth follow-through advance a small consistent amount. Include final-to-first recovery when the second image is neutral. Do not copy either endpoint.'
  if state=='sleeping':phase+=' Keep curled sleep and CLOSED eyes throughout; independent subtle chin/paw/ear/tail articulation, not larger head or stretched breathing.'
  if state in ['waiting','running','failed','review']:phase+=' Forepaw articulation stays BELOW cheeks/eyes; one actual foreleg may raise but the other and two rear paws support, no taller torso. Preserve original short body/legs.'
  heart=state=='jumping';clothes=common_heart if heart else common_school
  prompt=f'ONE independently drawn whole transparent Retto {state} animation cell. Neighboring pose references are anatomy/costume authority. {phase} Same original-sized deep round3D muzzle/head, blue eyes if open, cream/brown short soft fur, COMPACT real cat torso and SHORT legs. Exactly4 actual feline limbs, hidden limbs plausibly occluded by torso/near limbs, no extra paw or empty hanging sleeve. {clothes} Clothing follows actual shoulder/elbow/hip joints. ONE original fluffy brown tail, unchanged volume. Full silhouette inside generous margin. No extra pet/effect/text. Not a repeated source, not crossfade or independent limb/head distortion.'
  j={'state':state,'id':id,'variant':'auto-'+stage,'phase':phase,'prompt':prompt,'refs':refs};req=r/'requests'/(id+'-auto-'+stage+'.json');req.write_text(json.dumps(j)+'\n');j['request_file']=str(req);jobs.append(j)
(root/('queue-expansion-'+stage+'.json')).write_text(json.dumps(jobs,indent=2)+'\n');print(len(jobs),'jobs',stage)
