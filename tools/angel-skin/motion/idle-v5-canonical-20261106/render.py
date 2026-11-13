"""New idle: integral hand-held star and fresh flight-attached companion effects."""
from pathlib import Path
from functools import lru_cache
import hashlib,importlib.util,json,math
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('night',ROOT.parent/'night-effects-v1-20261105/render_night.py');night=importlib.util.module_from_spec(spec);spec.loader.exec_module(night)
SIZE=(544,544);POSE=200;STEP=50;CYCLE=3200;BLUE=(102,202,255);RED=(255,109,143)
FEATHER=Image.open(ROOT.parent/'running-v1-20261105/effects/feather.png').convert('RGBA')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
@lru_cache(maxsize=32)
def sprite(kind,color,size):
    s=size*3;im=Image.new('RGBA',(s,s));d=ImageDraw.Draw(im)
    if kind=='star':
        pts=[]
        for j in range(8):
            a=j*math.pi/4;r=s*(.44 if j%2==0 else .12);pts.append((s/2+r*math.sin(a),s/2+r*math.cos(a)))
        d.polygon(pts,fill=(*color,245))
    elif kind=='heart':
        pts=[]
        for j in range(100):
            a=math.tau*j/100;pts.append((s/2+16*math.sin(a)**3*s*.026,s*.48-(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))*s*.026))
        d.polygon(pts,fill=(*color,235))
    elif kind=='feather':im.putalpha(FEATHER.resize((s,s),Image.Resampling.LANCZOS).getchannel('A'));rgb=Image.new('RGBA',(s,s),(*color,0));rgb.putalpha(im.getchannel('A'));im=rgb
    return im.resize((size,size),Image.Resampling.LANCZOS)
def stamp(layer,kind,xy,size,color,alpha,angle=0):
    im=sprite(kind,color,size).copy()
    if angle:im=im.rotate(angle,Image.Resampling.BICUBIC,expand=True)
    im=night.opacity(im,alpha);x=round(xy[0]-im.width/2);y=round(xy[1]-im.height/2);glow=Image.new('RGBA',SIZE);g=Image.new('RGBA',im.size,(*color,0));g.putalpha(im.getchannel('A').point(lambda a:round(a*.5)));glow.alpha_composite(g,(x,y));layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(4)));layer.alpha_composite(im,(x,y))
def at(records,ms,key):return records[int((ms%CYCLE)//POSE)]['attachment_proxies'][key]
def edge(im):
    w,h=im.size;y,x=np.indices((h,w));dist=np.minimum(np.minimum(x,w-1-x),np.minimum(y,h-1-y));q=np.clip(dist/42,0,1);q=q*q*(3-2*q);out=im.copy();out.putalpha(ImageChops.multiply(im.getchannel('A'),Image.fromarray(np.round(q*255).astype('uint8'))));return out

def effects(ms,records):
    ms%=CYCLE;t=ms/CYCLE;phase=math.tau*t
    back=night.night_atmosphere(ms,SIZE,CYCLE);back=night.opacity(back,.75);front=Image.new('RGBA',SIZE)
    night.stamp(back,night.crescent(50),(382,113+3*math.sin(phase)),50,.48,-18+4*math.sin(phase))
    # A physical star is already drawn in the gripping paws; only its glow/glints are added.
    sx,sy=at(records,ms,'star');halo=Image.new('RGBA',SIZE);d=ImageDraw.Draw(halo)
    d.ellipse((sx-27,sy-27,sx+27,sy+27),fill=(255,220,98,round(24+12*math.sin(phase*2)**2)));back.alpha_composite(halo.filter(ImageFilter.GaussianBlur(12)))
    for j in range(3):
        a=phase*2+j*math.tau/3;stamp(front,'star',(sx+25*math.cos(a),sy+20*math.sin(a)),7,(255,226,142),.24+.20*math.sin(a)**2)
    # Airborne wakes retain actual birth positions instead of dragging a rigid trail with the pet.
    for actor,key,color in [('tato','tato_magic_emitter',BLUE),('melody','melody_magic_emitter',RED)]:
        side=-1 if actor=='tato' else 1
        for age in [0,100,200,300,400]:
            q=age/500;px,py=at(records,ms-age,key);kind='star' if actor=='tato' else ('heart' if age%200==0 else 'feather')
            px+=side*(4+18*q);py+=22*q;alpha=(1-q)**1.5*(.7+.18*math.sin(phase+age/200)**2)
            stamp(back,kind,(px,py),15 if kind!='feather' else 22,color,alpha,side*(10+30*q))
        ex,ey=at(records,ms,key);q=(t*2)%1
        # One readable outside-body accent is continuous while poses hold.
        stamp(front,'star' if actor=='tato' else 'heart',(ex+side*11,ey-34-22*q),17 if actor=='tato' else 12,color,.45+.35*math.sin(math.pi*q)**2,12*math.sin(phase))
        if actor=='tato':
            rings=Image.new('RGBA',SIZE);dr=ImageDraw.Draw(rings);r=14+22*q;dr.arc((ex-r,ey+29-r*.35,ex+r,ey+29+r*.35),90,270,fill=(*BLUE,round(145*math.sin(math.pi*q)**2)),width=2);back.alpha_composite(rings.filter(ImageFilter.GaussianBlur(3)));back.alpha_composite(rings)
    # Sparse slow ivory feathers retain the dreamlike night language of the skin.
    for j in range(4):
        q=(t+j/4)%1;night.stamp(back,FEATHER,(42+j*145+9*math.sin(math.tau*q+j),110+320*q),18,.27*math.sin(math.pi*q)**2,20*math.sin(phase+j),halo=False)
    return edge(back),edge(front)
def compose(back,char,front):
    protect=char.getchannel('A').point(lambda a:255 if a>4 else 0).filter(ImageFilter.MaxFilter(7));front=front.copy();front.putalpha(ImageChops.multiply(front.getchannel('A'),ImageChops.invert(protect)))
    out=back.copy();out.alpha_composite(char);out.alpha_composite(front)
    a=np.asarray(char);b=np.asarray(out);m=a[:,:,3]==255;assert np.array_equal(a[m],b[m]),'opaque character/physical-star pixels changed'
    return out

def main():
    records=json.loads((ROOT/'sources.json').read_text());chars=[Image.open(ROOT/r['path']).convert('RGBA') for r in records];assert all(sha(ROOT/r['path'])==r['sha256'] for r in records)
    frames=[];dark=[];hashes=[]
    for ms in range(0,CYCLE,STEP):
        b,f=effects(ms,records);out=compose(b,chars[ms//POSE],f);assert night.border_max(out.getchannel('A'))==0
        frames.append(out);hashes.append(hashlib.sha256(b.tobytes()+f.tobytes()).hexdigest());bg=Image.new('RGBA',SIZE,'#10182a');bg.alpha_composite(out);dark.append(bg.convert('RGB'))
    assert len(set(hashes))==64
    b0,f0=effects(0,records);b1,f1=effects(CYCLE,records);assert b0.tobytes()==b1.tobytes() and f0.tobytes()==f1.tobytes()
    night.save_webp(frames,ROOT/'review/night.webp',STEP);dark[0].save(ROOT/'review/idle.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2);frames[20].save(ROOT/'review/preview.png')
    for color,label in [('#10182a','dark'),('#edf0f5','light')]:
        board=Image.new('RGB',(896,992),color);d=ImageDraw.Draw(board)
        for i in range(16):
            tile=Image.new('RGBA',SIZE,color);tile.alpha_composite(frames[i*4]);tile=tile.resize((224,224),Image.Resampling.LANCZOS);x=i%4*224;y=i//4*248;board.paste(tile.convert('RGB'),(x,y));d.text((x+6,y+228),str(i),fill='#b9a37f')
        board.save(ROOT/'review'/f'effect-runtime-{label}.png')
    frozen=[]
    for ms in [700,750]:b,f=effects(ms,records);frozen.append(hashlib.sha256(compose(b,chars[3],f).tobytes()).hexdigest())
    assert len(set(frozen))==2
    report={'new_complete_independent_drawings':16,'pose_ms':POSE,'cycle_ms':CYCLE,'effect_sample_ms':STEP,'unique_effect_samples':64,'effect_loop_periodic':True,'frozen_pose_effect_progression':True,'outer_edge_alpha_max':0,'opaque_character_prop_RGBA_changed_pixels':0,'original_registration':'unverified','native_installed':False,'media':{}}
    for name in ['character.webp','character.gif','night.webp','idle.gif']:
        total=0;unique=set()
        with Image.open(ROOT/'review'/name) as im:
            for i in range(im.n_frames):
                im.seek(i);im.load();total+=im.info['duration']
                if name.endswith('webp'):
                    decoded=im.convert('RGBA');expected=chars[i] if name=='character.webp' else frames[i];assert night.border_max(decoded.getchannel('A'))==0
                    for color in ['#10182a','#edf0f5']:
                        a=Image.new('RGBA',SIZE,color);a.alpha_composite(decoded);b=Image.new('RGBA',SIZE,color);b.alpha_composite(expected);assert max(c.getextrema()[1] for c in ImageChops.difference(a,b).split()[:3])<=1
                    unique.add(hashlib.sha256(decoded.tobytes()).hexdigest())
            assert total==CYCLE
            if name=='character.webp':assert len(unique)==16
            report['media'][name]={'frames':im.n_frames,'cycle_ms':total,'sha256':sha(ROOT/'review'/name)}
    (ROOT/'review/media-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report,flush=True)
if __name__=='__main__':main()
