from pathlib import Path
import json,re,hashlib,subprocess
ROOT=Path(__file__).resolve().parent;GALLERY=ROOT.parents[1]/'review-gallery-20261105'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
html=(GALLERY/'index.html').read_text();items=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',html,re.S)[1]);current={i['state']:i for i in items if i['status']!='archive'};locked=json.loads((ROOT/'gallery-lock.json').read_text());count=0
for state,item in locked.items():
 for layer in ['character','effect']:
  assert current[state][layer]['sha256']==item[layer]['sha256']
for item in items:
 for layer in ['character','effect']:
  m=item[layer];assert sha((GALLERY/m['src'].split('?')[0]).resolve())==m['sha256'];count+=1
assert current['gaze']['id']=='gaze-left-v1-20261106' and not current['gaze']['nativeInstalled']
p=ROOT/'review/gallery-syntax.js';p.write_text('\n'.join(re.findall(r'<script>(.*?)</script>',html,re.S)));subprocess.run(['/opt/homebrew/bin/node','--check',str(p)],check=True)
report={'production_states_preserved':len(locked),'existing7_character_and_FX_movies_unchanged':True,'new_review_interactions':1,'cards':len(items),'media_hashes_verified':count,'JS_syntax':'pass','native_installation_this_task':False,'live_browser_verified':False}
(ROOT/'review/gallery-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
