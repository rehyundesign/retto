from pathlib import Path
import json,hashlib,re,subprocess,sys
from PIL import Image
ROOT=Path(__file__).resolve().parent;GALLERY=ROOT.parents[1]/'review-gallery-20261105';OLD=ROOT.parent/'failed-v2-tears-20261106'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
html=(GALLERY/'index.html').read_text();items=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',html,re.S)[1]);current={v['state']:v for v in items if v['status']!='archive'}
lock=json.loads((ROOT/'gallery-lock.json').read_text());preserved=[]
for state,rec in lock.items():
 if state=='failed':continue
 for layer,m in rec.items():
  path=(GALLERY/m['src'].split('?')[0]).resolve();assert sha(path)==m['sha256'];assert current[state][layer]['sha256']==m['sha256'];assert current[state][layer]['ms']==m['ms']
 preserved.append(state)
pre=json.loads((ROOT/'pre-edit-lock.json').read_text());assert sha(OLD/'sources.json')==pre['source_records_sha256']
for ident,h in pre['source_sha256'].items():assert sha(OLD/'character'/f'{ident}.png')==h
assert sha(ROOT.parent/'effect-repair-v3-stars-sad-20261106/failed/night.webp')==pre['current_effect_sha256']
checked=0
for item in items:
 for layer in ['effect','character']:
  m=item[layer];p=(GALLERY/m['src'].split('?')[0]).resolve();assert p.exists() and sha(p)==m['sha256'];checked+=1
js='\n'.join(re.findall(r'<script>(.*?)</script>',html,re.S));temp=ROOT/'review/gallery-syntax.js';temp.write_text(js);subprocess.run(['/opt/homebrew/bin/node','--check',str(temp)],check=True)
report={'current_states':len(current),'gallery_cards':len(items),'media_hashes_verified':checked,'other_states_preserved':preserved,'old_failed_sources_and_effect_unchanged':True,'javascript_syntax':'pass','live_browser_verified':False,'native_installed':False}
(ROOT/'review/gallery-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
