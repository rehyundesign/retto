"""Same-pose boundary matte repair. Retain all drawings, framing and effect clocks."""
from pathlib import Path
import hashlib,importlib.util,json
import numpy as np
from PIL import Image,ImageChops,ImageDraw,ImageFilter
from holes import clean

ROOT=Path(__file__).resolve().parent
OLD=ROOT.parent/'night-effects-v1-20261105'
spec=importlib.util.spec_from_file_location('night',OLD/'render_night.py')
night=importlib.util.module_from_spec(spec);spec.loader.exec_module(night)
STATES=['idle','waiting','failed','waving','jumping']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n')

def matte(im,state,ident):
    regions=json.loads((ROOT/'protected-white-fur.json').read_text())['regions'].get(f'{state}/{ident:02}',[])
    fixed,mask,components=clean(im,regions)
    old=np.asarray(im);new=np.asarray(fixed)
    assert np.array_equal(old[:,:,:3],new[:,:,:3]), 'Every original RGB pixel must remain exact'
    return fixed,{'background_hole_pixels':int(np.count_nonzero(mask)),
        'background_components':components,'alpha_noise_pixels':int(np.count_nonzero((old[:,:,3]>0)&(old[:,:,3]<=16))),
        'RGB_changed_pixels':0,'opaque_interior_RGB_changed_pixels':0,'max_interior_displacement_px':0}

def render_state(state):
    out=ROOT/state;(out/'character').mkdir(parents=True,exist_ok=True)
    folder,pose_ms,motif=night.SPECS[state];source=ROOT.parent/folder
    records=json.loads((source/'sources.json').read_text())
    originals=[source/r['path'] for r in records]
    inputs=[ROOT.parent/'matte-repair-v2-20261105'/state/'character'/f'{i:02}.png' for i in range(16)]
    lock={str(p):sha(p) for p in originals+inputs+[OLD/state/'night.webp',OLD/state/'character.webp']}
    write(out/'pre-edit-lock.json',lock)
    frames=[Image.open(p).convert('RGBA') for p in originals]
    fixed=[];changes=[]
    for i,im in enumerate(frames):
        im,report=matte(Image.open(inputs[i]).convert('RGBA'),state,i);im.save(out/'character'/f'{i:02}.png');fixed.append(im)
        changes.append({'id':f'{i:02}',**report,'source_sha256':sha(originals[i]),'input_sha256':sha(inputs[i]),'repaired_sha256':sha(out/'character'/f'{i:02}.png')})
    module,star,old=night.load_original(state,folder,records,frames)
    size=frames[0].size;cycle=16*pose_ms;playback=[]
    for ms in range(0,cycle,50):
        back,front=old(ms)
        sky=night.night_atmosphere(ms,size,cycle);sky.alpha_composite(back)
        sky.alpha_composite(night.point_effect(state,ms,size,cycle,star))
        if state=='idle':front=night.fade_idle_glow(front,module,star,records,ms,cycle)
        cell=night.fade_edges(sky);cell.alpha_composite(fixed[ms//pose_ms]);cell.alpha_composite(front)
        playback.append(cell)
    night.save_webp(playback,out/'night.webp',50);night.save_webp(fixed,out/'character.webp',pose_ms)
    dark=[]
    for f in playback:
        bg=Image.new('RGBA',size,'#131d32');bg.alpha_composite(f);dark.append(bg.convert('RGB'))
    dark[0].save(out/'preview.gif',save_all=True,append_images=dark[1:],duration=50,loop=0,disposal=2)
    playback[0].save(out/'preview.png')
    for label,color in [('dark','#131d32'),('light','#edf0f5')]:
        board=Image.new('RGB',(size[0]*4,(size[1]+24)*4),color);d=ImageDraw.Draw(board)
        for i,f in enumerate(fixed):
            tile=Image.new('RGBA',size,color);tile.alpha_composite(f)
            x=i%4*size[0];y=i//4*(size[1]+24);board.paste(tile.convert('RGB'),(x,y));d.text((x+8,y+size[1]+4),str(i),fill='#a08060')
        board.save(out/f'poses-{label}.png')
    assert all(sha(Path(p))==h for p,h in lock.items())
    checks={}
    for name in ['night.webp','character.webp','preview.gif']:
        total=0;edges=[];decoded=[]
        with Image.open(out/name) as im:
            for i in range(im.n_frames):
                im.seek(i);im.load();total+=im.info['duration']
                if name.endswith('webp'):
                    frame=im.convert('RGBA');edges.append(night.border_max(frame.getchannel('A')))
                    if name=='character.webp':decoded.append(hashlib.sha256(frame.tobytes()).hexdigest())
            assert total==cycle
            if edges:assert max(edges)==0
            if decoded:assert len(set(decoded))==16
            checks[name]={'frames':im.n_frames,'cycle_ms':total,'border_alpha_max':max(edges) if edges else None,'sha256':sha(out/name)}
    write(out/'validation.json',{'state':state,'mode':'effect-repair','method':'remove opaque neutral-white negative-space pockets and alpha<=16 background noise; preserve EVERY input RGB pixel and pose',
        'pose_count':16,'pose_ms':pose_ms,'effect_sample_ms':50,'original_files_unchanged':True,
        'protected_interior_RGB_changed_pixels':0,'pose_geometry_changed':False,'changes':changes,
        'media':checks,'native_installed':False,'original_landmark_registration':'unverified'})
    print(json.dumps({'state':state,'source_drawings':16,'clock_ms':cycle,'protected_interior_RGB_changed_pixels':0}),flush=True)

if __name__=='__main__':
    ROOT.mkdir(exist_ok=True)
    for state in STATES:render_state(state)
