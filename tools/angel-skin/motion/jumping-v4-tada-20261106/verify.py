from pathlib import Path
import json,re,hashlib,subprocess
ROOT=Path(__file__).resolve().parent;GALLERY=ROOT.parents[1]/'review-gallery-20261105'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
html=(GALLERY/'index.html').read_text();items=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',html,re.S)[1]);current={i['state']:i for i in items if i['status']!='archive'};locked=json.loads((ROOT/'gallery-lock.json').read_text());count=0
for state,item in locked.items():
 for layer in ['character','effect']:
  if state=='jumping' and layer=='effect':continue
  assert current[state][layer]['sha256']==item[layer]['sha256']
for i in items:
 for layer in ['character','effect']:
  m=i[layer];p=(GALLERY/m['src'].split('?')[0]).resolve();assert sha(p)==m['sha256'];count+=1
assert current['failed']['id']=='failed-v3-pet-proportions-20261106'
assert current['jumping']['id']=='jumping-v4-tada-20261106'
js='\n'.join(re.findall(r'<script>(.*?)</script>',html,re.S));p=ROOT/'review/gallery-syntax.js';p.write_text(js);subprocess.run(['/opt/homebrew/bin/node','--check',str(p)],check=True)
r={'current_states':len(current),'cards':len(items),'media_hashes_verified':count,'all7_character_animations_unchanged':True,'other6_state_effects_unchanged':True,'failed_size_repair_current':True,'js_syntax':'pass','live_browser_verified':False,'native_installed':False};(ROOT/'review/gallery-validation.json').write_text(json.dumps(r,indent=2)+'\n');print(r)
