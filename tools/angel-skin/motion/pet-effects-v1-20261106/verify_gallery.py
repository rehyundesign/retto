from pathlib import Path
from urllib.parse import unquote
import json,re,hashlib,subprocess
ROOT=Path(__file__).resolve().parent;GAL=ROOT.parents[1]/'review-gallery-20261105'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
html=(GAL/'index.html').read_text();items=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',html,re.S).group(1));lock=json.loads((ROOT/'pre-edit-lock.json').read_text())
assert len(items)==30 and len({i['id'] for i in items})==30
current=[i for i in items if i['status']!='archive'];assert len(current)==7
for item in items:
    for mode in ['effect','character']:
        v=item[mode];p=GAL/unquote(v['src'].split('?')[0]);assert sha(p)==v['sha256']
for item in current:
    state=item['state'];assert item['id']=='pet-effects-'+state
    assert item['character']['sha256']==lock[state]['character_sha256']
    assert item['effect']['sha256']==sha(ROOT/state/'night.webp')
    assert item['effect']['ms']==item['character']['ms']==lock[state]['cycle_ms']
    assert sha(Path(lock[state]['effect']))==lock[state]['effect_sha256']
    assert all(sha(Path(s['path']))==s['sha256'] for s in lock[state]['sources'])
script=Path('/private/tmp/angel-pet-effects-gallery.js');script.write_text('\n'.join(re.findall(r'<script>(.*?)</script>',html,re.S)));subprocess.run(['/opt/homebrew/bin/node','--check',str(script)],check=True)
report={'current':7,'archives':23,'media_hashes':60,'all112_character_files_preserved':True,'all7_original_character_animations_byte_identical':True,'all7_old_effect_files_preserved':True,'cadences_preserved':True,'javascript_syntax':'pass','live_browser_verified':False,'native_installed':False}
(ROOT/'gallery-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
