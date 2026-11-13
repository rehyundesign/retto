"""Small slowly drifting yellow stars behind immutable approved idle drawings."""
from pathlib import Path
import importlib.util,json,hashlib,math
import numpy as np
from PIL import Image,ImageDraw,ImageChops
ROOT=Path(__file__).resolve().parent;OLD=ROOT.parent/'idle-v5-canonical-20261106'
def load(name,path):
    s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
BASE=load('approved_idle',OLD/'render.py')
GOLD=load('gold_star_helpers',ROOT.parent/'effect-repair-v3-stars-sad-20261106/render.py')
SIZE=(544,544);CYCLE=3200;STEP=50
# Irregular open-air placement; sizes stay smaller than the physical play star.
STARS=[(88,94,14,.15),(154,60,11,.8),(246,32,17,1.9),(353,73,13,2.8),
       (445,93,15,4.0),(505,178,12,.6),(506,338,14,3.0),(473,477,11,1.7),
       (331,511,12,3.6),(124,501,14,5.2),(33,375,13,2.3),(31,203,10,4.8)]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def starfield(ms):
    p=math.tau*(ms%CYCLE)/CYCLE;layer=Image.new('RGBA',SIZE)
    for j,(x,y,size,phase) in enumerate(STARS):
        x+=math.sin(p+phase)*(2+j%3);y+=math.cos(p+phase*.8)*(3+j%4)
        pulse=(.5+.5*math.sin(p+phase))**2;alpha=.24+.61*pulse
        GOLD.gold_stamp(layer,(x,y),size,alpha,7*math.sin(p+phase+.5))
    # Sparse tiny gold dust adds depth without a dense glitter curtain.
    for j,(x,y) in enumerate([(60,155),(205,63),(410,54),(484,295),(72,437)]):
        q=(ms%CYCLE)/CYCLE;a=math.tau*q+j
        BASE.stamp(layer,'star',(x+2*math.sin(a),y+4*math.cos(a)),5,(255,233,161),.2+.25*math.sin(a)**2)
    return BASE.edge(layer)
def compose(ms,char,records,extra=True):
    back,front=BASE.effects(ms,records)
    if extra:back.alpha_composite(starfield(ms))
    return BASE.compose(back,char,front)
def board(frames,bg,path):
    out=Image.new('RGB',(896,992),bg);d=ImageDraw.Draw(out)
    for i in range(16):
        cell=Image.new('RGBA',SIZE,bg);cell.alpha_composite(frames[i*4]);x=i%4*224;y=i//4*248;out.paste(cell.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));d.text((x+6,y+228),str(i),fill='#b9a37f')
    out.save(path)
def main():
    lock=json.loads((ROOT/'pre-edit-lock.json').read_text())
    assert sha(OLD/'render.py')==lock['renderer_sha256'];assert sha(OLD/'sources.json')==lock['sources_sha256']
    records=json.loads((OLD/'sources.json').read_text());chars=[Image.open(OLD/r['path']).convert('RGBA') for r in records]
    assert all(sha(OLD/r['path'])==lock['source_sha256'][r['id']] for r in records)
    movie=Image.open(lock['effect_animation']['path']);frames=[];dark=[];hashes=[];visible=[]
    for j,ms in enumerate(range(0,CYCLE,STEP)):
        char=chars[ms//200];before=compose(ms,char,records,False);after=compose(ms,char,records)
        stars=starfield(ms);outside=np.asarray(stars.getchannel('A'))==0
        assert np.array_equal(np.asarray(before)[outside],np.asarray(after)[outside])
        opaque=np.asarray(char)[:,:,3]==255;assert np.array_equal(np.asarray(char)[opaque],np.asarray(after)[opaque])
        movie.seek(j);movie.load();old=movie.convert('RGBA')
        for color in ['#10182a','#edf0f5']:
            a=Image.new('RGBA',SIZE,color);a.alpha_composite(before);b=Image.new('RGBA',SIZE,color);b.alpha_composite(old)
            assert max(c.getextrema()[1] for c in ImageChops.difference(a,b).split()[:3])<=1
        assert BASE.night.border_max(after.getchannel('A'))==0
        a=Image.new('RGBA',SIZE,'#10182a');a.alpha_composite(before);b=Image.new('RGBA',SIZE,'#10182a');b.alpha_composite(after)
        aa=np.asarray(a.resize((224,224),Image.Resampling.LANCZOS)).astype(int);bb=np.asarray(b.resize((224,224),Image.Resampling.LANCZOS)).astype(int)
        r,g,bl=[bb[:,:,k] for k in range(3)];gold=(r>100)&(g>80)&(g>bl*1.25)&(np.max(abs(aa-bb),axis=2)>8);visible.append(int(gold.sum()))
        frames.append(after);dark.append(b.convert('RGB'));hashes.append(hashlib.sha256(stars.tobytes()).hexdigest())
    assert len(set(hashes))==64 and min(visible)>15
    assert starfield(0).tobytes()==starfield(CYCLE).tobytes()
    assert compose(700,chars[3],records).tobytes()!=compose(750,chars[3],records).tobytes()
    BASE.night.save_webp(frames,ROOT/'review/night.webp',STEP)
    dark[0].save(ROOT/'review/idle.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2)
    dark[12].save(ROOT/'review/preview-dark.png')
    for color,label in [('#10182a','dark'),('#edf0f5','light')]:board(frames,color,ROOT/'review'/f'runtime-{label}.png')
    for ident,digest in lock['source_sha256'].items():assert sha(OLD/'character'/f'{ident}.png')==digest
    for key in ['character_animation','effect_animation']:assert sha(Path(lock[key]['path']))==lock[key]['sha256']
    report={'mode':'effect-repair','character_drawings_retained':16,'character_PNGs_and_animation_byte_identical':True,'opaque_character_and_physical_star_RGBA_unchanged':True,'original_ambient_and_pet_effects_reconstructed_with_max_RGB_delta':1,'changes_only_under_new_background_star_footprints':True,'new_stars_layer':'behind character','edge_alpha_max':0,'cycle_ms':CYCLE,'pose_ms':200,'effect_ms':50,'distinct_starfield_samples':64,'periodic_loop':True,'frozen_pose_effect_progression':True,'visible_added_gold_pixels_at224px':[min(visible),max(visible)],'native_installed':False,'night_sha256':sha(ROOT/'review/night.webp'),'gif_sha256':sha(ROOT/'review/idle.gif')}
    (ROOT/'review/validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
if __name__=='__main__':main()
