"""Check source locks, contact gold, increased tears, loop clocks and gallery scope."""
from pathlib import Path
import json,re,hashlib,subprocess,importlib.util
from urllib.parse import unquote
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parent;GAL=ROOT.parents[1]/'review-gallery-20261105'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
spec=importlib.util.spec_from_file_location('new_fx',ROOT/'render.py');fx=importlib.util.module_from_spec(spec);spec.loader.exec_module(fx)
report={'original32_PNGs_unchanged':True,'both_character_animations_byte_identical':True,'contact_gold_pixels':{},'tear_pixel_area_ratios':{},'periodic_and_frozen_pose_effects':{}}
for state,name in fx.NAMES.items():
    old=ROOT.parent/name;lock=json.loads((ROOT/state/'pre-edit-lock.json').read_text());records=json.loads((old/'sources.json').read_text());char=Image.open(old/'character/03.png').convert('RGBA')
    for ident,digest in lock['source_sha256'].items():assert sha(old/'character'/f'{ident}.png')==digest
    for k in ['character_animation','effect_animation']:assert sha(Path(lock[k]['path']))==lock[k]['sha256']
    ch0=Image.open(old/'character/00.png').convert('RGBA')
    if state=='waiting':
        contacts=json.loads((old/'contacts.json').read_text())
        a,_=fx.waiting(0,ch0,records,contacts);b,_=fx.waiting(3200,ch0,records,contacts);assert a.tobytes()==b.tobytes()
        a,_=fx.waiting(700,char,records,contacts);b,_=fx.waiting(750,char,records,contacts);assert a.tobytes()!=b.tobytes()
        oldmovie=Image.open(lock['effect_animation']['path']);newmovie=Image.open(ROOT/state/'night.webp')
        for ms in [700,2100]:
            oldmovie.seek(ms//50);newmovie.seek(ms//50);a=oldmovie.convert('RGBA');b=newmovie.convert('RGBA');aa=Image.new('RGBA',a.size,'#10182a');aa.alpha_composite(a);bb=Image.new('RGBA',b.size,'#10182a');bb.alpha_composite(b)
            before=np.asarray(aa).astype(int);after=np.asarray(bb).astype(int);r,g,bl=[after[:,:,i] for i in range(3)]
            yellow=(r>180)&(g>140)&(bl<140)&(g>bl*1.3)&(np.max(abs(after-before),axis=2)>10);count=int(yellow.sum());assert count>300
            report['contact_gold_pixels'][str(ms)]=count
    else:
        a,_,_=fx.failed(0,ch0,records);b,_,_=fx.failed(3200,ch0,records);assert a.tobytes()==b.tobytes()
        a,_,_=fx.failed(700,char,records);b,_,_=fx.failed(750,char,records);assert a.tobytes()!=b.tobytes()
        oldcounts=json.loads((old/'review/media-validation.json').read_text())['all4_tear_streams_visible_pixel_sum'];newcounts=json.loads((ROOT/state/'validation.json').read_text())['visible_tear_pixel_sum']
        for k,n in newcounts.items():ratio=n/oldcounts[k];assert ratio>2;report['tear_pixel_area_ratios'][k]=round(ratio,2)
    report['periodic_and_frozen_pose_effects'][state]=True
html=(GAL/'index.html').read_text();items=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',html,re.S).group(1));assert len(items)==45 and len({i['id'] for i in items})==45
current=[i for i in items if i['status']!='archive'];assert len(current)==7;lock=json.loads((ROOT/'gallery-lock.json').read_text())
for item in items:
    for kind in ['character','effect']:assert sha(GAL/unquote(item[kind]['src'].split('?')[0]))==item[kind]['sha256']
for item in current:
    state=item['state'];assert item['character']['sha256']==lock[state]['character']['sha256']
    expected=sha(ROOT/state/'night.webp') if state in fx.NAMES else lock[state]['effect']['sha256'];assert item['effect']['sha256']==expected
script=Path('/private/tmp/angel-stars-sad-gallery.js');script.write_text('\n'.join(re.findall(r'<script>(.*?)</script>',html,re.S)));subprocess.run(['/opt/homebrew/bin/node','--check',str(script)],check=True)
report.update(current_states=7,archived=38,verified_media_hashes=90,all7_character_animations_unchanged=True,other5_states_effects_unchanged=True,javascript_syntax='pass',live_browser_verified=False,native_installed=False)
(ROOT/'review/final-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
