"""Add motion-attached blue bell magic and ruby wing/heart magic; retain all input art."""
from pathlib import Path
from functools import lru_cache
import math,json,hashlib,importlib.util
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('night',ROOT.parent/'night-effects-v1-20261105/render_night.py');night=importlib.util.module_from_spec(spec);spec.loader.exec_module(night)
SIZE=(544,544);BLUE=(102,202,255);RED=(255,109,143)
FEATHER=Image.open(ROOT.parent/'running-v1-20261105/effects/feather.png').convert('RGBA')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n')
@lru_cache(maxsize=40)
def glyph(kind,color,size):
    s=size*3;im=Image.new('RGBA',(s,s));d=ImageDraw.Draw(im);c=(*color,240)
    if kind=='star':
        pts=[]
        for i in range(8):
            a=i*math.pi/4;r=s*(.44 if i%2==0 else .115);pts.append((s/2+r*math.sin(a),s/2+r*math.cos(a)))
        d.polygon(pts,fill=c)
    elif kind=='heart':
        pts=[]
        for i in range(100):
            a=math.tau*i/100;x=16*math.sin(a)**3;y=13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a);pts.append((s/2+x*s*.026,s*.48-y*s*.026))
        d.polygon(pts,fill=c)
    elif kind=='note':
        base=night.music_note(size).resize((s,s),Image.Resampling.LANCZOS);im=Image.new('RGBA',(s,s),(*color,0));im.putalpha(base.getchannel('A'))
    elif kind=='feather':
        base=FEATHER.resize((s,s),Image.Resampling.LANCZOS);im=Image.new('RGBA',(s,s),(*color,0));im.putalpha(base.getchannel('A'))
    return im.resize((size,size),Image.Resampling.LANCZOS)
def stamp(layer,kind,pos,size,color,alpha=1,angle=0):
    if alpha<=0:return
    if color==BLUE:size=round(size*1.65);alpha=min(1,alpha*1.6)
    im=glyph(kind,color,size).copy()
    if angle:im=im.rotate(angle,Image.Resampling.BICUBIC,expand=True)
    im=night.opacity(im,alpha);x=round(pos[0]-im.width/2);y=round(pos[1]-im.height/2)
    glow=Image.new('RGBA',SIZE);g=Image.new('RGBA',im.size,(*color,0));g.putalpha(im.getchannel('A').point(lambda a:round(a*.5)));glow.alpha_composite(g,(x,y));layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(4)));layer.alpha_composite(im,(x,y))
def arc(layer,xy,rx,ry,color,alpha,start=0,end=360,width=1):
    if color==BLUE:alpha=min(1,alpha*1.55);width=max(2,round(width*1.75))
    im=Image.new('RGBA',SIZE);d=ImageDraw.Draw(im);x,y=xy;d.arc((x-rx,y-ry,x+rx,y+ry),start,end,fill=(*color,round(255*alpha)),width=width);layer.alpha_composite(im.filter(ImageFilter.GaussianBlur(3)));layer.alpha_composite(im)
def point(state,ms,actor,cycle):
    p=ATTACH[state];pose_ms=cycle/16;q=(ms%cycle)/pose_ms;i=int(q);u=q-i;a=p[i][actor];b=p[(i+1)%16][actor]
    return (a[0]+(b[0]-a[0])*u,a[1]+(b[1]-a[1])*u)
def envelope(q):return math.sin(math.pi*q)**2
@lru_cache(maxsize=8)
def local_edge_mask(size):
    w,h=size;y,x=np.indices((h,w));dist=np.minimum(np.minimum(x,w-1-x),np.minimum(y,h-1-y));a=np.clip(dist/46,0,1);a=a*a*(3-2*a);return Image.fromarray(np.round(a*255).astype('uint8'))
def fade(im):
    out=im.copy();out.putalpha(ImageChops.multiply(im.getchannel('A'),local_edge_mask(im.size)));return out

def effects(state,ms,cycle):
    ms%=cycle;t=ms/cycle;phase=math.tau*t;back=Image.new('RGBA',SIZE);front=Image.new('RGBA',SIZE)
    for actor,color,side in [('tato',BLUE,-1),('melody',RED,1)]:
        x,y=point(state,ms,actor,cycle);kind='star' if actor=='tato' else 'heart'
        # Emission starts at the bell or the outside of Melody's bow/winglets.
        ox=x+side*(12 if actor=='tato' else 24);oy=y+4
        if state=='idle':
            for j in range(3):
                q=(t+j/3)%1;a=envelope(q)
                px=ox+side*((45 if actor=='tato' else 10)+23*q);py=oy-25-112*q+4*math.sin(math.tau*q)
                stamp(front,kind,(px,py),(12 if actor=='tato' else 9)+j%2*3,color,.70*a,15*math.sin(phase+j))
            if actor=='tato':
                q=(t*2)%1;arc(back,(ox-28,oy),12+26*q,10+18*q,color,.52*envelope(q),100,260,2);arc(back,(x,y+51),23+4*math.sin(phase),6,color,.25+.12*math.sin(phase)**2,0,180)
            else:stamp(back,'feather',(ox+10,oy-10+4*math.sin(phase)),19,color,.35,22*math.sin(phase))
        elif state=='running':
            for j in range(4):
                q=(t+j/4)%1;a=envelope(q);endx=224 if actor=='tato' else 323
                px=(1-q)**2*ox+2*(1-q)*q*(ox+side*(180 if actor=='tato' else 55))+q*q*endx;py=(1-q)**2*oy+2*(1-q)*q*(oy-145)+q*q*(oy-40)
                stamp(front,'note',(px,py),15,color,.78*a,side*12*math.sin(phase+j))
                if j%2==0:stamp(back,kind,(px+side*12,py+12),8,color,.45*a)
        elif state=='waiting':
            for j in range(3):
                q=(t*2+j/3)%1;a=envelope(q)
                if actor=='tato':arc(back,(ox-25,oy-5),12+42*q,12+35*q,color,.48*a,110,250,2)
                else:stamp(front,'heart',(ox+10+32*q,oy-12-55*q),11+round(3*q),color,.78*a,10*math.sin(phase+j))
            stamp(front,kind,(ox+side*18,oy+18),11,color,.35+.20*math.sin(phase*2)**2)
        elif state=='failed':
            # Recoil scatters, then the reassurance light gathers and settles by the paws.
            calm=(1-math.cos(phase))/2
            for j in range(3):
                a=phase+j*math.tau/3;r=24-12*calm
                px=ox+side*(18+r*.5*math.cos(a));py=oy+24+10*math.sin(a)
                stamp(back,kind,(px,py),10,color,.24+.36*calm,12*math.sin(a))
            arc(back,(ox+side*7,oy+49),20+8*calm,5+2*calm,color,.28+.20*calm,5,175)
            if actor=='tato':
                stamp(front,'star',(ox-58,oy+5+3*math.sin(phase)),12,color,.42+.23*calm)
                arc(front,(x-8,y+65),27,6,color,.28+.20*calm,0,180)
        elif state=='waving':
            for j in range(4):
                q=(t+j/4)%1;a=envelope(q)
                px=ox+side*((36 if actor=='tato' else 10)+38*q)+8*math.sin(math.pi*q);py=oy-105*q
                stamp(front,kind,(px,py),12+j%2*3,color,.88*a,side*20*q)
                if actor=='melody' and j%2==0:stamp(back,'feather',(px+7,py+20),21,color,.42*a,25+40*q)
            q=t;arc(back,(ox+side*6,oy-10),20+22*q,20+36*q,color,.32*envelope(q),90 if side<0 else 270,270 if side<0 else 450)
        elif state=='jumping':
            # Trail particles retain the emission location at birth, following the actual flight.
            for born in [450,600,750,900,1050,1200,1350,1500]:
                age=ms-born
                if not 0<=age<650:continue
                q=age/650;a=envelope(q)
                source=min(15,born//150)
                if actor=='tato':px,py=JUMP_FEET[source]['attachment_proxies']['tato_foot'];g='star'
                else:
                    px,py=point(state,born,actor,cycle);px+=30;py-=4;g='feather' if born%300==0 else 'heart'
                stamp(back,g,(px+side*(7+18*q),py+42*q),15 if g!='feather' else 22,color,.9*a,side*(15+35*q))
            q=(ms-1650)/500
            if 0<=q<1:
                feet=JUMP_FEET[11]['attachment_proxies']['tato_foot' if actor=='tato' else 'melody_foot']
                arc(front,feet,10+28*q,3+5*q,color,.66*envelope(q),0,360,2)
        elif state=='sleeping':
            # No energetic bursts: colored breathing halos and one slowly drifting dream mote each.
            breathe=(1-math.cos(phase))/2
            arc(back,(ox,oy+10),24+3*breathe,6+2*breathe,color,.16+.16*breathe,10,175)
            for j in range(2):
                q=(t+j/2)%1;a=envelope(q)
                stamp(front,kind,(ox+side*(8+12*q),oy-(35 if actor=='tato' else 60)-(65 if actor=='tato' else 80)*q),8+j*2,color,.46*a,10*math.sin(phase+j))
    return fade(back),fade(front)

def compose(base,char,back,front):
    # Back effects are physically behind all retained subjects/effects; front flecks avoid bodies.
    protect=char.getchannel('A').point(lambda a:255 if a>4 else 0).filter(ImageFilter.MaxFilter(11))
    front=front.copy();front.putalpha(ImageChops.multiply(front.getchannel('A'),ImageChops.invert(protect)))
    opaque=base.getchannel('A').point(lambda a:0 if a==255 else 255)
    front.putalpha(ImageChops.multiply(front.getchannel('A'),opaque))
    out=back.copy();out.alpha_composite(base);out.alpha_composite(front)
    a=np.asarray(base);b=np.asarray(out);m=a[:,:,3]==255
    assert np.array_equal(a[m],b[m]),'Opaque subject/prop/star pixels must stay exact'
    return out,front

def render_state(state,lock):
    global SIZE
    out=ROOT/state;src=Path(lock['effect']);character=Path(lock['character'])
    with Image.open(src) as dimensions:SIZE=dimensions.size
    assert sha(src)==lock['effect_sha256'] and sha(character)==lock['character_sha256']
    chars=[]
    with Image.open(character) as im:
        for i in range(16):im.seek(i);im.load();chars.append(im.convert('RGBA'))
    originals=[];durations=[]
    with Image.open(src) as im:
        for i in range(im.n_frames):im.seek(i);im.load();originals.append(im.convert('RGBA'));durations.append(im.info['duration'])
    cycle=lock['cycle_ms'];assert sum(durations)==cycle;pose_ms=cycle//16
    frames=[];backs=[];fronts=[];dark=[];hashes=[];elapsed=0
    for base,dt in zip(originals,durations):
        b,f=effects(state,elapsed,cycle);final,f=compose(base,chars[min(15,elapsed//pose_ms)],b,f)
        assert night.border_max(final.getchannel('A'))==0
        frames.append(final);backs.append(b);fronts.append(f);hashes.append(hashlib.sha256(b.tobytes()+f.tobytes()).hexdigest())
        bg=Image.new('RGBA',SIZE,'#10182a');bg.alpha_composite(final);dark.append(bg.convert('RGB'));elapsed+=dt
    for name,ims in [('night.webp',frames),('pet-back.webp',backs),('pet-front.webp',fronts)]:night.save_webp(ims,out/name,durations[0])
    dark[0].save(out/'preview.gif',save_all=True,append_images=dark[1:],duration=durations,loop=0,disposal=2)
    frames[len(frames)//3].save(out/'preview.png')
    for label,color in [('dark','#10182a'),('light','#edf0f5')]:
        w,h=SIZE;board=Image.new('RGB',(w*4,(h+24)*4),color);d=ImageDraw.Draw(board)
        for i in range(16):
            idx=round(i*pose_ms/durations[0]);tile=Image.new('RGBA',SIZE,color);tile.alpha_composite(frames[idx]);x=i%4*w;y=i//4*(h+24);board.paste(tile.convert('RGB'),(x,y));d.text((x+8,y+h+4),str(i),fill='#b9a37f')
        board.save(out/f'poses-{label}.png')
    checks={}
    for name in ['night.webp','preview.gif']:
        total=0
        with Image.open(out/name) as im:
            assert im.n_frames==len(frames)
            for i in range(im.n_frames):
                im.seek(i);im.load();total+=im.info['duration']
                if name.endswith('webp'):
                    decoded=im.convert('RGBA');assert night.border_max(decoded.getchannel('A'))==0
                    for color in ['#10182a','#edf0f5']:
                        a=Image.new('RGBA',SIZE,color);a.alpha_composite(decoded);b=Image.new('RGBA',SIZE,color);b.alpha_composite(frames[i]);assert max(c.getextrema()[1] for c in ImageChops.difference(a,b).split()[:3])<=1
            assert total==cycle;checks[name]={'frames':im.n_frames,'cycle_ms':total,'sha256':sha(out/name)}
    assert sha(src)==lock['effect_sha256'] and sha(character)==lock['character_sha256']
    assert all(sha(Path(s['path']))==s['sha256'] for s in lock['sources'])
    b0,f0=effects(state,0,cycle);b1,f1=effects(state,cycle,cycle);assert b0.tobytes()==b1.tobytes() and f0.tobytes()==f1.tobytes()
    frozen=[]
    for t in [cycle//3,cycle//3+50]:
        b,f=effects(state,t,cycle);frozen.append(hashlib.sha256(b.tobytes()+f.tobytes()).hexdigest())
    assert len(set(frozen))==2
    report={'state':state,'render_code_sha256':sha(Path(__file__)),'mode':'effect-repair','character_files_unchanged':True,'character_drawings':16,'opaque_subject_prop_star_pixels_changed':0,'new_effect_edge_alpha_max':0,'old_cycle_ms':cycle,'new_cycle_ms':cycle,'effect_sample_ms':durations[0],'new_effect_samples':len(set(hashes)),'frozen_pose_effect_progression':True,'effect_loop_periodic':True,'media':checks,'native_installed':False,'original_registration':'inherited unverified'}
    write(out/'validation.json',report);print(json.dumps({'state':state,'cycle_ms':cycle,'characters_preserved':True}),flush=True)
    return frames,durations
LOCK=json.loads((ROOT/'render-inputs.json').read_text())
ATTACH={state:json.loads((ROOT/state/'attachments.json').read_text())['points'] for state in LOCK}
JUMP_FEET=json.loads((ROOT.parent/'jumping-v2-trio-flight-20261105/sources.json').read_text())
if __name__=='__main__':
    for state,lock in LOCK.items():
        if not (ROOT/state/'validation.json').exists() or json.loads((ROOT/state/'validation.json').read_text()).get('render_code_sha256')!=sha(Path(__file__)):render_state(state,lock)
