"""Verify rendered HTML points to the new sleep and preserves six existing motions."""
from pathlib import Path
from urllib.parse import unquote
import hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parent
GALLERY=ROOT.parents[1]/'review-gallery-20261105'
html=(GALLERY/'index.html').read_text()
items=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',html,re.S).group(1))
assert len(items)==23 and len({i['id'] for i in items})==23
current=[i for i in items if i['status']!='archive'];assert len(current)==7
assert {i['state'] for i in current}=={'idle','running','waiting','failed','waving','jumping','sleeping'}
locks=json.loads((ROOT/'other-motions-lock.json').read_text())
for item in items:
    for mode in ['effect','character']:
        v=item[mode];p=GALLERY/unquote(v['src'].split('?')[0]);assert hashlib.sha256(p.read_bytes()).hexdigest()==v['sha256']
for item in current:
    if item['state']=='sleeping':assert item['id']=='sleeping-v1-20261105' and item['effect']['ms']==6400
    else:
        for mode in ['effect','character']:assert item[mode]['sha256']==locks[item['state']][mode]
assert 'data-pending-state="sleeping"' not in html and 'data-filter="sleeping"' in html
script=Path('/private/tmp/angel-sleep-gallery.js');script.write_text('\n'.join(re.findall(r'<script>(.*?)</script>',html,re.S)))
subprocess.run(['/opt/homebrew/bin/node','--check',str(script)],check=True)
report={'current_motions':7,'archived':16,'verified_media_sources':46,'existing_six_motions_unchanged':True,'sleeping_filter_and_source_present':True,'javascript_syntax':'pass','live_browser_verified':False}
(ROOT/'review/gallery-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
