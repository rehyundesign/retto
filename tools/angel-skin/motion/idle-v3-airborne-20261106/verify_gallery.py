from pathlib import Path
from urllib.parse import unquote
import json,re,hashlib,subprocess
ROOT=Path(__file__).resolve().parent;GAL=ROOT.parents[1]/'review-gallery-20261105'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
html=(GAL/'index.html').read_text();items=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',html,re.S).group(1));old=json.loads((ROOT/'source-lock.json').read_text())
assert len(items)==38 and len({i['id'] for i in items})==38
current=[i for i in items if i['status']!='archive'];assert len(current)==7
for item in items:
    for mode in ['effect','character']:
        media=item[mode];p=GAL/unquote(media['src'].split('?')[0]);assert sha(p)==media['sha256']
for item in current:
    state=item['state']
    if state=='idle':
        assert item['id']=='idle-v3-airborne-20261106'
        for mode,name in [('effect','night.webp'),('character','character.webp')]:assert item[mode]['sha256']==sha(ROOT/'review'/name)
    else:
        for mode in ['effect','character']:assert item[mode]['sha256']==old[state][mode]['sha256'],state+' changed unexpectedly'
assert next(i for i in current if i['state']=='idle')['effect']['ms']==3200
script=Path('/private/tmp/angel-new-idle-gallery.js');script.write_text('\n'.join(re.findall(r'<script>(.*?)</script>',html,re.S)));subprocess.run(['/opt/homebrew/bin/node','--check',str(script)],check=True)
report={'current_motions':7,'archived':31,'media_hashes_verified':76,'new_idle_selected':True,'other6_motions_byte_identical':True,'jumping_sleeping_running_preserved':True,'javascript_syntax':'pass','live_browser_verified':False,'native_installed':False}
(ROOT/'review/gallery-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
