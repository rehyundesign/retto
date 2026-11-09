"""Sixteen independent complete poses: alpha cleanup and rigid whole-character registration."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent
SIZE=(544,544);POSE=200;GROUND=484
STAR_KEYS=[(129,326),(143,316),(160,311),(194,317),(228,329),(271,333),(291,328),(332,321),(374,318),(411,309),(424,292),(388,299),(293,320),(212,327),(161,332),(135,330)]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,indent=2)+'\n')
def comps(mask,minimum=2):
    seen=np.zeros(mask.shape,bool);h,w=mask.shape;out=[]
    for y,x in zip(*np.nonzero(mask)):
        if seen[y,x]:continue
        seen[y,x]=True;todo=[(y,x)];points=[]
        while todo:
            yy,xx=todo.pop();points.append((yy,xx))
            for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                ny,nx=yy+dy,xx+dx
                if 0<=ny<h and 0<=nx<w and mask[ny,nx] and not seen[ny,nx]:seen[ny,nx]=True;todo.append((ny,nx))
        if len(points)>=minimum:out.append(points)
    return out

def clean(im):
    im=im.copy();im.putalpha(im.getchannel('A').point(lambda a:0 if a<=160 else min(255,round((a-160)*255/80))))
    im=im.resize(SIZE,Image.Resampling.LANCZOS);a=np.asarray(im.getchannel('A')).copy();a[a<=16]=0
    # Keep actual bodies/props, remove detached generated background dust only.
    cs=comps(a>0,1);removed=0
    for c in cs:
        if len(c)<=8:
            for y,x in c:a[y,x]=0;removed+=1
    im.putalpha(Image.fromarray(a));return im,removed

def support(im):
    a=np.asarray(im).astype(int);eligible=(a[:,:,3]>180)&(a[:,:,0]>190)&(a[:,:,1]>165)&(a[:,:,2]>145)
    rows=np.flatnonzero(eligible[390:525,180:350].sum(1)>=8);assert len(rows)>0,'no main support';return int(rows[-1]+390)
def landmarks(im,i):
    a=np.asarray(im).astype(int);r,g,b,alpha=[a[:,:,k] for k in range(4)];yy,xx=np.indices(alpha.shape)
    gold=(r>170)&(g>175)&(r>g*1.01)&(g>b*1.55)&(b<170)&(alpha>200)
    cs=comps(gold,20);assert cs,'yellow star missing'
    expected=STAR_KEYS[i]
    def centroid(c):return [float(np.mean([x for y,x in c])),float(np.mean([y for y,x in c]))]
    target=max(cs,key=len)
    star=centroid(target)
    # Flight emitters follow actual dark dot/^ eyes, and actual red bow respectively.
    # Frame11's Tato is high in the air; measure its actual eyes rather than
    # retaining the old ground-level detector window or a fixed effect origin.
    eye_top=120 if i==11 else 210
    eye_right=150 if i==11 else 175
    eye=(r<95)&(g<95)&(b<100)&(alpha>220)&(xx<eye_right)&(xx>15)&(yy>eye_top)&(yy<400)
    dark=sorted(comps(eye,2),key=lambda c:centroid(c)[1]);assert len(dark)>=2
    e=dark[:2];tx=float(np.mean([centroid(c)[0] for c in e]));ty=float(np.mean([centroid(c)[1] for c in e]))
    red=(r>100)&(r>g*1.8)&(r>b*1.15)&(g<140)&(b<170)&(xx>365)&(yy>220)&(alpha>200)
    cs=comps(red,15);assert cs,'Melody bow missing';c=max(cs,key=len);top=min(y for y,x in c);bottom=max(y for y,x in c);upper=[(y,x) for y,x in c if y<=top+(bottom-top)*.55];mx,my=centroid(upper)
    return {'star':[round(v,2) for v in star],'tato_eyes_proxy':[round(tx,2),round(ty,2)],'tato_magic_emitter':[round(tx-38,2),round(ty+65,2)],'melody_magic_emitter':[round(mx+38,2),round(my+8,2)]}

def board(frames,bg,name,runtime=False):
    w=224 if runtime else 544;h=248 if runtime else 568;out=Image.new('RGB',(w*4,h*4),bg);d=ImageDraw.Draw(out)
    for i,im in enumerate(frames):
        b=Image.new('RGBA',SIZE,bg);b.alpha_composite(im)
        if runtime:b=b.resize((224,224),Image.Resampling.LANCZOS)
        x=i%4*w;y=i//4*h;out.paste(b.convert('RGB'),(x,y));d.text((x+6,y+w+4),f'{i:02}',fill='#b9a37f')
    out.save(ROOT/'review'/name)
def main():
    raws=[ROOT/'raw'/f'{i:02}.png' for i in range(16)];assert all(p.exists() for p in raws)
    assert len({sha(p) for p in raws})==16
    frames=[];records=[]
    for i,p in enumerate(raws):
        raw=Image.open(p).convert('RGBA');assert raw.width==raw.height,raw.size
        im,n=clean(raw);y=support(im);dy=GROUND-y;assert abs(dy)<64,(i,dy)
        f=Image.new('RGBA',SIZE);f.alpha_composite(im,(0,dy));assert support(f)==GROUND
        path=ROOT/'character'/f'{i:02}.png';f.save(path);frames.append(f)
        records.append({'id':f'{i:02}','path':f'character/{i:02}.png','sha256':sha(path),'raw_path':str(p.resolve()),'raw_sha256':sha(p),'prompt_sha256':sha(ROOT/'prompts'/('07-repair.txt' if i==7 else f'{i:02}.txt')),'independent_complete_body_drawing':True,'resolution_scale':544/raw.width,'whole_character_translation_px':[0,dy],'main_support_proxy_y':GROUND,'removed_detached_alpha_pixels':n,'attachment_proxies':landmarks(f,i),'anatomical_landmarks':'unverified; support/color proxies are display registration/emitters, not original certification'})
    frames[0].save(ROOT/'review/character.webp',save_all=True,append_images=frames[1:],duration=POSE,loop=0,lossless=True,method=4,exact=True)
    dark=[]
    for f in frames:
        b=Image.new('RGBA',SIZE,'#10182a');b.alpha_composite(f);dark.append(b.convert('RGB'))
    dark[0].save(ROOT/'review/character.gif',save_all=True,append_images=dark[1:],duration=POSE,loop=0,disposal=2)
    for bg,label in [('#10182a','dark'),('#edf0f5','light')]:
        board(frames,bg,f'character-{label}-board.png');board(frames,bg,f'runtime-{label}.png',True)
    write(ROOT/'sources.json',records);print({'independent_drawings':16,'cycle_ms':3200,'support_y':GROUND,'translations_y':[r['whole_character_translation_px'][1] for r in records]},flush=True)
if __name__=='__main__':main()
