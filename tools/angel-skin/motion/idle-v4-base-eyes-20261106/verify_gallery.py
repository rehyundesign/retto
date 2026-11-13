from pathlib import Path
from urllib.parse import unquote
import json,re,hashlib,subprocess
ROOT=Path(__file__).resolve().parent;GAL=ROOT.parents[1]/'review-gallery-20261105'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
html=(GAL/'index.html').read_text();items=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',html,re.S).group(1));lock=json.loads((ROOT/'gallery-lock.json').read_text())
assert len(items)==39 and len({i['id'] for i in items})==39
current=[i for i in items if i['status']!='archive'];assert len(current)==7
for item in items:
    for mode in ['effect','character']:
        v=item[mode];p=GAL/unquote(v['src'].split('?')[0]);assert sha(p)==v['sha256']
for item in current:
    state=item['state']
    if state=='idle':
        assert item['id']=='idle-v4-base-eyes-20261106'
        for mode,name in [('effect','night.webp'),('character','character.webp')]:assert item[mode]['sha256']==sha(ROOT/'review'/name)
        assert item['effect']['ms']==item['character']['ms']==3200
    else:
        for mode in ['effect','character']:assert item[mode]['sha256']==lock[state][mode]['sha256']
script=Path('/private/tmp/angel-base-eyes-gallery.js');script.write_text('\n'.join(re.findall(r'<script>(.*?)</script>',html,re.S)));subprocess.run(['/opt/homebrew/bin/node','--check',str(script)],check=True)
report={'current':7,'archived':32,'media_hashes_verified':78,'default_eye_ratio_idle_selected':True,'other6_motions_byte_identical':True,'javascript_syntax':'pass','native_installed':False,'live_browser_verified':False};(ROOT/'review/gallery-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
