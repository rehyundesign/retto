"""Slow celestial lullaby; character drawings and two time-driven effects stay separate."""
from pathlib import Path
import hashlib,importlib.util,json,math
from PIL import Image,ImageDraw,ImageFilter,ImageChops
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('angel_night',ROOT.parent/'night-effects-v1-20261105/render_night.py')
night=importlib.util.module_from_spec(spec);spec.loader.exec_module(night)
SIZE=(544,544);POSE=400;CYCLE=6400;STEP=100
STAR=Image.open(ROOT.parent/'idle-v2-20261105/effects/star.png').convert('RGBA')
FEATHER=Image.open(ROOT.parent/'running-v1-20261105/effects/feather.png').convert('RGBA')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def effects(ms):
    t=(ms%CYCLE)/CYCLE;phase=math.tau*t
    back=night.night_atmosphere(ms%CYCLE,SIZE,CYCLE)
    back=night.opacity(back,.75)
    # The sleeping canopy breathes gently in phase with the resting bodies.
    canopy=Image.new('RGBA',SIZE);d=ImageDraw.Draw(canopy)
    breathe=(1-math.cos(phase))/2
    d.ellipse((128-4*breathe,266-3*breathe,423+4*breathe,501),fill=(119,113,191,round(15+9*breathe)))
    back.alpha_composite(canopy.filter(ImageFilter.GaussianBlur(35)))
    # A recognizable moon with a slowly swaying chain of warm stars, away from faces.
    moon=(286+3*math.sin(phase),237+2*math.cos(phase))
    night.stamp(back,night.crescent(59),moon,59,.70+ .08*math.sin(phase),-12+3*math.sin(phase))
    for j in range(3):
        x=212+j*74+4*math.sin(phase+j*.7);y=231+19*math.sin(j*1.5)+3*math.sin(phase+j)
        night.stamp(back,STAR,(x,y),9+j%2*3,.28+.18*(1+math.sin(phase+j))/2,8*math.sin(phase+j))
    # Tiny golden music notes drift up from the moon as a silent visual lullaby.
    for j in range(3):
        q=(t+j/3)%1;alpha=.28*math.sin(math.pi*q)**2
        night.stamp(back,night.music_note(18),(270+48*math.sin(q*math.pi+j*.8),230-102*q),18,alpha,12*math.sin(phase+j))
    # Two softly released feathers behind the sleeping wings; never in front of eyes.
    for j in range(4):
        q=(t+j/4)%1;side=-1 if j%2==0 else 1
        x=272+side*(130+30*q)+8*math.sin(math.tau*q+j);y=290+158*q
        night.stamp(back,FEATHER,(x,y),19+j%2*3,.25*math.sin(math.pi*q)**2,side*(10+30*q),halo=False)
    return night.fade_edges(back),Image.new('RGBA',SIZE)
def board(frames,bg,path,scale=544,cellheight=568):
    out=Image.new('RGB',(scale*4,cellheight*4),bg);d=ImageDraw.Draw(out)
    for i,im in enumerate(frames):
        b=Image.new('RGBA',SIZE,bg);b.alpha_composite(im)
        if scale!=544:b=b.resize((scale,scale),Image.Resampling.LANCZOS)
        x=i%4*scale;y=i//4*cellheight;out.paste(b.convert('RGB'),(x,y));d.text((x+6,y+scale+3),f'{i:02}',fill='#b9a37f')
    out.save(path)
def main():
    records=json.loads((ROOT/'sources.json').read_text());frames=[Image.open(ROOT/r['path']).convert('RGBA') for r in records]
    assert all(sha(ROOT/r['path'])==r['sha256'] for r in records)
    backs=[];fronts=[];full=[];dark=[];effect_hashes=[]
    for ms in range(0,CYCLE,STEP):
        b,f=effects(ms);assert night.border_max(b.getchannel('A'))==night.border_max(f.getchannel('A'))==0
        backs.append(b);fronts.append(f);effect_hashes.append(hashlib.sha256(b.tobytes()+f.tobytes()).hexdigest())
        out=b.copy();out.alpha_composite(frames[ms//POSE]);out.alpha_composite(f);full.append(out)
        base=Image.new('RGBA',SIZE,'#10182a');base.alpha_composite(out);dark.append(base.convert('RGB'))
    assert len(set(effect_hashes))==64
    assert effects(0)[0].tobytes()==effects(CYCLE)[0].tobytes()
    for name,ims in [('effects/back.webp',backs),('effects/front.webp',fronts),('review/night.webp',full)]:night.save_webp(ims,ROOT/name,STEP)
    dark[0].save(ROOT/'review/sleeping.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2)
    full[28].save(ROOT/'review/preview.png')
    board([full[i*4] for i in range(16)],'#10182a',ROOT/'review/effect-dark-board.png')
    board([full[i*4] for i in range(16)],'#edf0f5',ROOT/'review/effect-light-board.png')
    frozen=[]
    for ms in [1500,1600]:
        b,f=effects(ms);b.alpha_composite(frames[4]);frozen.append(hashlib.sha256(b.tobytes()).hexdigest())
    assert len(set(frozen))==2
    report={'independent_drawings':16,'pose_ms':POSE,'cycle_ms':CYCLE,'effect_ms':STEP,'effect_unique_samples':64,'effect_outer_edge_alpha_max':0,'frozen_pose_effect_progression':True,'effect_loop_periodic':True,'original_registration':'unverified','native_installed':False,'media':{}}
    for name in ['review/character.webp','review/character.gif','review/night.webp','review/sleeping.gif']:
        total=0;unique=set()
        with Image.open(ROOT/name) as im:
            n=im.n_frames
            for i in range(n):
                im.seek(i);im.load();total+=im.info['duration']
                if name.endswith('.webp'):
                    decoded=im.convert('RGBA');expected=frames[i] if name.endswith('character.webp') else full[i]
                    assert night.border_max(decoded.getchannel('A'))==0
                    for color in ['#10182a','#edf0f5']:
                        a=Image.new('RGBA',SIZE,color);a.alpha_composite(decoded)
                        b=Image.new('RGBA',SIZE,color);b.alpha_composite(expected)
                        assert max(c.getextrema()[1] for c in ImageChops.difference(a,b).split()[:3])<=1
                    unique.add(hashlib.sha256(decoded.tobytes()).hexdigest())
            assert total==CYCLE
            if name.endswith('character.webp'):assert n==16 and len(unique)==16
            report['media'][name]={'frames':n,'cycle_ms':total,'sha256':sha(ROOT/name)}
    (ROOT/'review/media-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
