"""Register16 complete trio drawings; never fit silhouette or assemble body parts."""
from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parent
SIZE=(544,544)
POSE_MS=150
GROUND=484
HEAD_OFFSET=[0,0,5,10,0,-15,-24,-27,-25,-17,-7,0,8,3,0,0]
AIR=set(range(5,11))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def foot(im,x0,x1):
    a=im.getchannel('A')
    # Cream/pink feet only: a trailing brown tail or red bow is not a foot.
    pixels=im.load()
    eligible=lambda x,y: pixels[x,y][3]>128 and pixels[x,y][0]>190 and pixels[x,y][1]>165 and pixels[x,y][2]>145
    y=next(y for y in range(539,269,-1) if sum(eligible(x,y) for x in range(x0,x1))>=5)
    xs=[x for yy in range(y-2,y+1) for x in range(x0,x1) if eligible(x,yy)]
    return [round(sum(xs)/len(xs),1),y]
def ear(im):
    a=im.getchannel('A')
    return next(y for y in range(16,220) if sum(v>=240 for v in a.crop((145,y,375,y+1)).tobytes())>=5)
def board(frames,bg,name):
    out=Image.new('RGB',(544*4,568*4),bg);d=ImageDraw.Draw(out)
    for i,im in enumerate(frames):
        tile=Image.new('RGBA',SIZE,bg);tile.alpha_composite(im)
        x=i%4*544;y=i//4*568;out.paste(tile.convert('RGB'),(x,y));d.text((x+10,y+548),f'{i:02} / {i*POSE_MS}ms',fill='#a38a64')
    out.save(ROOT/'review'/name)
def main():
    raws=[ROOT/'raw'/f'{i:02}.png' for i in range(16)]
    assert all(p.exists() for p in raws)
    assert len({sha(p) for p in raws})==16
    frames=[];records=[];anchor_ear=None
    for i,p in enumerate(raws):
        raw=Image.open(p).convert('RGBA');assert raw.size==(1254,1254)
        # Technical alpha cleanup of the SAME drawing: discard generated haze.
        raw.putalpha(raw.getchannel('A').point(lambda a:0 if a<=160 else min(255,round((a-160)*255/80))))
        im=raw.resize(SIZE,Image.Resampling.LANCZOS)
        old_ear=ear(im);old_foot=foot(im,190,320)
        if anchor_ear is None:anchor_ear=old_ear
        dy=(anchor_ear+HEAD_OFFSET[i]-old_ear) if i in AIR else GROUND-old_foot[1]
        final=Image.new('RGBA',SIZE);final.alpha_composite(im,(0,dy))
        path=ROOT/'character'/f'{i:02}.png';final.save(path);frames.append(final)
        attachments={'main_foot':foot(final,190,320),'tato_foot':foot(final,25,155),'melody_foot':foot(final,400,475)}
        records.append({'id':f'{i:02}','path':f'character/{i:02}.png','sha256':sha(path),'raw_sha256':sha(p),
           'source_size':list(raw.size),'common_resolution_scale':544/1254,'whole_character_translation_px':[0,dy],
           'ear_proxy_before_y':old_ear,'foot_proxy_before':old_foot,'airborne':i in AIR,
           'attachment_proxies':attachments,'original_anatomical_landmarks':'unverified; ear/contact proxies support rigid registration only'})
    frames[0].save(ROOT/'review/character.webp',save_all=True,append_images=frames[1:],duration=POSE_MS,loop=0,lossless=True,method=4,exact=True)
    dark=[]
    for f in frames:
        bg=Image.new('RGBA',SIZE,'#10182a');bg.alpha_composite(f);dark.append(bg.convert('RGB'))
    dark[0].save(ROOT/'review/character.gif',save_all=True,append_images=dark[1:],duration=POSE_MS,loop=0,disposal=2)
    board(frames,'#10182a','character-dark-board.png');board(frames,'#edf0f5','character-light-board.png')
    # Retain actual display-size comparison; front view is a declared new stance.
    prior=Image.open(ROOT.parent/'matte-repair-v3-holes-20261105/idle/character/00.png').convert('RGBA')
    out=Image.new('RGB',(544*3,544),'#10182a')
    for col,im in enumerate([prior,frames[0],frames[7]]):
        bg=Image.new('RGBA',SIZE,'#10182a');bg.alpha_composite(im);out.paste(bg.convert('RGB'),(col*544,0))
    out.save(ROOT/'review/idle-neutral-apex-comparison.png')
    (ROOT/'sources.json').write_text(json.dumps(records,indent=2)+'\n')
    print(json.dumps({'independent_drawings':16,'pose_ms':POSE_MS,'cycle_ms':16*POSE_MS,'registrations_y':[r['whole_character_translation_px'][1] for r in records]}))
if __name__=='__main__':main()
