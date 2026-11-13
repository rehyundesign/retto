"""Register independently drawn sleeping bodies; no head patches, mesh or silhouette fitting."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent
SIZE=(544,544);POSE=400

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def support(im):
    a=np.asarray(im);eligible=(a[:,:,3]>200)&(a[:,:,0]>190)&(a[:,:,1]>160)&(a[:,:,2]>140)
    # The two cream forepaws are the sleep support, not the brown curled tail.
    rows=np.flatnonzero(eligible[350:510,275:365].sum(axis=1)>=7)
    assert len(rows)>0
    return int(rows[-1]+350)
def nose_x(im,y):
    a=np.asarray(im).astype(int)[y-70:y-16,285:355]
    m=(a[:,:,0]-a[:,:,1]>35)&(a[:,:,2]-a[:,:,1]>-18)&(a[:,:,3]>200)
    ys,xs=np.nonzero(m);assert len(xs)>80,'nose proxy not reliable'
    return float(xs.mean()+285)
def clean(im):
    im=im.copy();im.putalpha(im.getchannel('A').point(lambda a:0 if a<=160 else min(255,round((a-160)*255/80))))
    im=im.resize(SIZE,Image.Resampling.LANCZOS)
    alpha=np.asarray(im.getchannel('A')).copy();alpha[alpha<=16]=0
    seen=np.zeros(alpha.shape,bool);removed=0
    for y,x in zip(*np.nonzero(alpha)):
        if seen[y,x]:continue
        stack=[(y,x)];seen[y,x]=True;points=[]
        while stack:
            yy,xx=stack.pop();points.append((yy,xx))
            for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                ny,nx=yy+dy,xx+dx
                if 0<=ny<544 and 0<=nx<544 and alpha[ny,nx] and not seen[ny,nx]:seen[ny,nx]=True;stack.append((ny,nx))
        if len(points)<=8:
            for yy,xx in points:alpha[yy,xx]=0;removed+=1
    im.putalpha(Image.fromarray(alpha));return im,removed

def board(frames,bg,name):
    out=Image.new('RGB',(2176,2272),bg);d=ImageDraw.Draw(out)
    for i,im in enumerate(frames):
        b=Image.new('RGBA',SIZE,bg);b.alpha_composite(im);x=i%4*544;y=i//4*568;out.paste(b.convert('RGB'),(x,y));d.text((x+8,y+548),f'{i:02} / {i*POSE}ms',fill='#b9a37f')
    out.save(ROOT/'review'/name)
def main():
    raws=[ROOT/'raw'/f'{i:02}.png' for i in range(16)];assert all(p.exists() for p in raws)
    assert len({sha(p) for p in raws})==16
    frames=[];records=[];baseline=None;center=None
    for i,p in enumerate(raws):
        raw=Image.open(p).convert('RGBA');assert raw.size==(1254,1254),raw.size
        im,removed=clean(raw);old_y=support(im)
        old_x=nose_x(im,old_y)
        if baseline is None:baseline=old_y;center=old_x
        dy=baseline-old_y;assert abs(dy)<64,(i,dy,'support exceeds available transparent registration space')
        dx=round(center-old_x);assert abs(dx)<20,(i,dx,'camera x drift too far')
        f=Image.new('RGBA',SIZE);f.alpha_composite(im,(dx,dy))
        assert f.getchannel('A').crop((0,0,544,12)).getbbox() is None
        assert f.getchannel('A').crop((0,532,544,544)).getbbox() is None
        path=ROOT/'character'/f'{i:02}.png';f.save(path);frames.append(f)
        records.append({'id':f'{i:02}','path':f'character/{i:02}.png','sha256':sha(path),'raw_sha256':sha(p),'independent_complete_drawing':True,'source_resolution':[1254,1254],'common_resolution_scale':544/1254,'whole_character_translation_px':[dx,dy],'nose_camera_proxy_x':nose_x(f,support(f)),'support_proxy_y':support(f),'removed_small_alpha_island_pixels':removed,'anatomy':'front_left and front_right support muzzle; rear_left and rear_right tucked under torso and occluded by belly/near wing. Far wing partially behind body/near wing. Tail remains continuous at hip.','original_landmarks':'unverified; support proxy is not original registration'})
    assert len({r['sha256'] for r in records})==16
    frames[0].save(ROOT/'review/character.webp',save_all=True,append_images=frames[1:],duration=POSE,loop=0,lossless=True,method=4,exact=True)
    dark=[]
    for f in frames:
        b=Image.new('RGBA',SIZE,'#10182a');b.alpha_composite(f);dark.append(b.convert('RGB'))
    dark[0].save(ROOT/'review/character.gif',save_all=True,append_images=dark[1:],duration=POSE,loop=0,disposal=2)
    board(frames,'#10182a','character-dark-board.png');board(frames,'#edf0f5','character-light-board.png')
    # Fit the square study into the224x320 viewport without distorting it.
    comparison=Image.new('RGB',(224*4,320*4),'#10182a');d=ImageDraw.Draw(comparison)
    for i,f in enumerate(frames):
        f=f.resize((224,224),Image.Resampling.LANCZOS);b=Image.new('RGBA',(224,320),'#10182a');b.alpha_composite(f,(0,68));x=i%4*224;y=i//4*320;comparison.paste(b.convert('RGB'),(x,y));d.text((x+6,y+300),f'{i:02}',fill='#b9a37f')
    comparison.save(ROOT/'review/runtime-size-board.png')
    (ROOT/'sources.json').write_text(json.dumps(records,indent=2)+'\n')
    print(json.dumps({'independent_drawings':16,'cycle_ms':6400,'pose_ms':400,'support_y':baseline,'translations_y':[r['whole_character_translation_px'][1] for r in records]}))
if __name__=='__main__':main()
