"""Positive shared flight: independently drawn trio plus action-timed moonlight wake."""
from pathlib import Path
import hashlib,importlib.util,json,math
from PIL import Image,ImageChops,ImageDraw,ImageFilter

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('angel_night',ROOT.parent/'night-effects-v1-20261105/render_night.py')
night=importlib.util.module_from_spec(spec);spec.loader.exec_module(night)
SIZE=(544,544);POSE_MS=150;CYCLE=2400;STEP=50
STAR=Image.open(ROOT.parent/'idle-v2-20261105/effects/star.png').convert('RGBA')
FEATHER=Image.open(ROOT.parent/'running-v1-20261105/effects/feather.png').convert('RGBA')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def bell(age,lifetime):
    return math.sin(math.pi*age/lifetime)**2 if 0<=age<lifetime else 0
def at(records,ms,key):return records[min(15,int(ms//POSE_MS))]['attachment_proxies'][key]

def effects(ms,records,wingtips):
    ms%=CYCLE;t=ms/CYCLE
    back=night.night_atmosphere(ms,SIZE,CYCLE)
    ambient=Image.new('RGBA',SIZE)
    for j in range(5):
        q=(t+j/5)%1
        night.stamp(ambient,FEATHER,(40+j*112+8*math.sin(math.tau*q+j),440-350*q),
                     17+j%2*3,.24*math.sin(math.pi*q)**2,20*math.sin(math.tau*q+j),halo=False)
    back.alpha_composite(ambient)
    # Three distinct wakes originate behind each actual source's feet at birth.
    for actor,key in enumerate(['tato_foot','main_foot','melody_foot']):
        for k,born in enumerate([600,750,900,1050,1200,1350]):
            age=ms-born;alpha=bell(age,600)
            if not alpha:continue
            x,y=at(records,born,key)
            x+=(-1 if actor==0 else 1)*9*math.sin(age/600*math.pi)+4*math.sin(k)
            y+=age*.055
            night.stamp(back,STAR,(x,y),9+(k%3)*2,alpha*.7,18*math.sin(age/250+k))
    # A quiet crescent grows with the lift, staying behind the right upper wing.
    glow=bell(ms-525,1125)
    if glow:night.stamp(back,night.crescent(66),(387,116),66,glow*.58,-15)
    # Real wingtip emitter locations are reviewed per independent drawing.
    for i,born in enumerate([600,900,1200,1500]):
        age=ms-born;alpha=bell(age,600)
        if not alpha:continue
        source=min(15,born//POSE_MS)
        for side in range(2):
            x,y=wingtips[str(source)][side]
            direction=-1 if side==0 else 1
            night.stamp(back,FEATHER,(x+direction*age*.035,y+age*.055),
                         24,alpha*.7,direction*(18+age*.04),halo=False)
    # Contact light starts at phase11, never before the trio reaches support.
    landing=Image.new('RGBA',SIZE);d=ImageDraw.Draw(landing)
    q=(ms-1650)/450
    if 0<=q<=1:
        for key in ['tato_foot','main_foot','melody_foot']:
            x,y=at(records,1650,key);radius=10+34*q;alpha=round(135*math.sin(math.pi*q)**2)
            d.arc((x-radius,y-5-radius*.15,x+radius,y+5+radius*.15),0,175,
                  fill=(255,227,163,alpha),width=2)
        halo=landing.filter(ImageFilter.GaussianBlur(5));back.alpha_composite(halo);back.alpha_composite(landing)
    return night.fade_edges(back),Image.new('RGBA',SIZE)

def main():
    records=json.loads((ROOT/'sources.json').read_text())
    tip_record=json.loads((ROOT/'wingtips.json').read_text());tips=tip_record['points']
    frames=[Image.open(ROOT/r['path']).convert('RGBA') for r in records]
    assert all(sha(ROOT/r['path'])==r['sha256'] for r in records)
    assert all(records[int(i)]['sha256']==h for i,h in tip_record['source_sha256'].items())
    full=[];dark=[];effect_hashes=[];border=[]
    for ms in range(0,CYCLE,STEP):
        back,front=effects(ms,records,tips);effect_hashes.append(hashlib.sha256(back.tobytes()+front.tobytes()).hexdigest())
        border.append(night.border_max(back.getchannel('A')))
        out=back.copy();out.alpha_composite(frames[ms//POSE_MS]);out.alpha_composite(front);full.append(out)
        bg=Image.new('RGBA',SIZE,'#10182a');bg.alpha_composite(out);dark.append(bg.convert('RGB'))
    assert max(border)==0 and len(set(effect_hashes))>16
    assert effects(0,records,tips)[0].tobytes()==effects(CYCLE,records,tips)[0].tobytes()
    night.save_webp(full,ROOT/'review/night.webp',STEP)
    dark[0].save(ROOT/'review/jumping.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2)
    full[21].save(ROOT/'review/preview.png')
    compare=Image.new('RGB',(544*4,568*4),'#10182a');d=ImageDraw.Draw(compare)
    for i in range(16):
        compare.paste(dark[i*3],(i%4*544,i//4*568));d.text((i%4*544+8,i//4*568+548),str(i),fill='#c8ae7d')
    compare.save(ROOT/'review/effect-dark-board.png')
    frozen=[]
    for ms in (900,1000):
        b,f=effects(ms,records,tips);b.alpha_composite(frames[6]);b.alpha_composite(f);frozen.append(hashlib.sha256(b.tobytes()).hexdigest())
    assert len(set(frozen))==2
    report={'independent_character_drawings':16,'pose_ms':POSE_MS,'effect_sample_ms':STEP,
      'cycle_ms':CYCLE,'changing_effect_samples':len(set(effect_hashes)),
      'frozen_pose_effect_progression':True,'effect_loop_periodic':True,'effects_border_alpha_max':0,
      'original_registration':'unverified','native_installed':False,'media':{}}
    for name in ['night.webp','character.webp','jumping.gif','character.gif']:
        total=0;unique=set()
        with Image.open(ROOT/'review'/name) as im:
            for i in range(im.n_frames):
                im.seek(i);im.load();total+=im.info['duration']
                if name.endswith('.webp'):
                    decoded=im.convert('RGBA');expected=full[i] if name=='night.webp' else frames[i]
                    assert night.border_max(decoded.getchannel('A'))==0
                    for color in ['#10182a','#edf0f5']:
                        a=Image.new('RGBA',SIZE,color);a.alpha_composite(decoded)
                        b=Image.new('RGBA',SIZE,color);b.alpha_composite(expected)
                        assert max(c.getextrema()[1] for c in ImageChops.difference(a,b).split()[:3])<=1
                    if name=='character.webp':unique.add(hashlib.sha256(decoded.tobytes()).hexdigest())
            assert total==CYCLE
            if unique:assert len(unique)==16
            report['media'][name]={'frames':im.n_frames,'cycle_ms':total,'sha256':sha(ROOT/'review'/name)}
    (ROOT/'review/media-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))
if __name__=='__main__':main()
