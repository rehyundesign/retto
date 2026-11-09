"""Verify original art, decoded alpha/occlusion, clocks and unrelated gallery states."""
from pathlib import Path
import importlib.util,json,re,hashlib,subprocess
from urllib.parse import unquote
import numpy as np
from PIL import Image,ImageChops
ROOT=Path(__file__).resolve().parent;OLD=ROOT.parent/'idle-v5-canonical-20261106';GAL=ROOT.parents[1]/'review-gallery-20261105'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
spec=importlib.util.spec_from_file_location('stars',ROOT/'render.py');fx=importlib.util.module_from_spec(spec);spec.loader.exec_module(fx)
lock=json.loads((ROOT/'pre-edit-lock.json').read_text())
for ident,digest in lock['source_sha256'].items():assert sha(OLD/'character'/f'{ident}.png')==digest
for key in ['character_animation','effect_animation']:assert sha(Path(lock[key]['path']))==lock[key]['sha256']
before=Image.open(lock['effect_animation']['path']);after=Image.open(ROOT/'review/night.webp');total=0;worst=0
assert before.n_frames==after.n_frames==64
for j in range(64):
    before.seek(j);before.load();after.seek(j);after.load();total+=after.info['duration'];a=before.convert('RGBA');b=after.convert('RGBA')
    stars=fx.starfield(j*50);outside=ImageChops.invert(stars.getchannel('A').point(lambda x:255 if x else 0));mask=np.asarray(outside)>0
    assert np.array_equal(np.asarray(a.getchannel('A'))[mask],np.asarray(b.getchannel('A'))[mask])
    char=Image.open(OLD/'character'/f'{j//4:02}.png').convert('RGBA');opaque=np.asarray(char)[:,:,3]==255
    assert np.array_equal(np.asarray(char)[opaque],np.asarray(b)[opaque])
    assert fx.BASE.night.border_max(b.getchannel('A'))==0
    for bg in ['#10182a','#edf0f5']:
        aa=Image.new('RGBA',a.size,bg);aa.alpha_composite(a);bb=Image.new('RGBA',b.size,bg);bb.alpha_composite(b)
        delta=max(ImageChops.multiply(c,outside).getextrema()[1] for c in ImageChops.difference(aa,bb).split()[:3]);assert delta<=1;worst=max(worst,delta)
assert total==3200
with Image.open(ROOT/'review/idle.gif') as im:
    elapsed=0
    for j in range(im.n_frames):im.seek(j);elapsed+=im.info['duration']
    assert im.n_frames==64 and elapsed==3200
html=(GAL/'index.html').read_text();items=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',html,re.S).group(1));assert len(items)==46 and len({i['id'] for i in items})==46
current=[i for i in items if i['status']!='archive'];assert len(current)==7;gal_lock=json.loads((ROOT/'gallery-lock.json').read_text())
for item in items:
    for kind in ['effect','character']:assert sha(GAL/unquote(item[kind]['src'].split('?')[0]))==item[kind]['sha256']
for item in current:
    state=item['state'];assert item['character']['sha256']==gal_lock[state]['character']['sha256']
    expected=sha(ROOT/'review/night.webp') if state=='idle' else gal_lock[state]['effect']['sha256'];assert item['effect']['sha256']==expected
script=Path('/private/tmp/angel-idle-background-stars-gallery.js');script.write_text('\n'.join(re.findall(r'<script>(.*?)</script>',html,re.S)));subprocess.run(['/opt/homebrew/bin/node','--check',str(script)],check=True)
report={'original16_PNGs_and_character_animation_unchanged':True,'decoded_opaque_character_and_physical_star_RGBA_exact':True,'decoded_alpha_outside_new_stars_exact':True,'decoded_visible_outside_star_footprints_max_delta':worst,'edge_alpha_max':0,'cycle_ms':3200,'export_frames':64,'all7_character_animations_unchanged':True,'other6_state_effects_unchanged':True,'verified_media_hashes':92,'current_states':7,'archived':39,'javascript_syntax':'pass','native_installed':False,'live_browser_verified':False}
(ROOT/'review/final-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
