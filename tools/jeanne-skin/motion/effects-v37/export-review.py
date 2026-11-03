from pathlib import Path
from PIL import Image, ImageDraw
import json, hashlib
ROOT=Path(__file__).parent
m=json.loads((ROOT/'manifest.json').read_text())
out=ROOT/'exports';out.mkdir(exist_ok=True)
def pose(s,t):
    q=t%s['cycle']
    for i,d in enumerate(s['times']):
        if q<d:return i
        q-=d
    return len(s['times'])-1
def composite(s,t,color,freeze=None):
    i=pose(s,t) if freeze is None else freeze
    e=int((t%s['effectCycle'])/s['effectInterval'])%len(s['effects'])
    im=Image.new('RGBA',(448,640),color)
    for file in [s['effects'][e]['back'],s['characters'][i],s['effects'][e]['front']]:im.alpha_composite(Image.open(ROOT/file).convert('RGBA'))
    a=s['anchors'][i]
    if a:
        peak=.4 if s['id'] in ['running','waving'] else .25
        gi=int(((t/s['cycle']+.25-peak)%1)*40)%40
        glow=Image.open(ROOT/'glow'/f'{gi:02}.png').convert('RGBA')
        strength=.22 if s['id']=='sleeping' else 1 if s['id']=='running' else .85 if s['id']=='waving' else .45
        glow.putalpha(glow.getchannel('A').point(lambda v:round(v*strength)))
        im.alpha_composite(glow,(round(a[0]-80),round(a[1]-80)))
    return im.resize((224,320),Image.Resampling.LANCZOS).convert('RGB')
summary=[]
for s in m['states']:
    if not s['ready'] or s['id'] not in ['idle','running','waving']:continue
    for theme,color in [('dark','#181827'),('white','#fffdf8')]:
        frames=[composite(s,i*.05,color) for i in range(len(s['effects']))]
        frames[0].save(out/f"{s['id']}-{theme}.gif",save_all=True,append_images=frames[1:],duration=50,loop=0,disposal=2)
        frames[0].save(out/f"{s['id']}-{theme}.webp",save_all=True,append_images=frames[1:],duration=50,loop=0,lossless=True)
        board=Image.new('RGB',(896,672),color);d=ImageDraw.Draw(board)
        for k in range(8):
            t=s['effectCycle']*k/8;tile=composite(s,t,color)
            board.paste(tile,(k%4*224,k//4*336));d.text((k%4*224+8,k//4*336+321),f'{t:.2f}s',fill='#888888')
        board.save(out/f"{s['id']}-effects-{theme}.png")
    # A frozen character must not freeze the separately timed effects.
    a=composite(s,.35,'#181827',0);b=composite(s,1.15,'#181827',0)
    assert a.tobytes()!=b.tobytes(),s['id']
    frozen=Image.new('RGB',(448,320));frozen.paste(a,(0,0));frozen.paste(b,(224,0));frozen.save(out/f"{s['id']}-frozen-pose-check.png")
    summary.append({'state':s['id'],'characterCount':len(s['characters']),'characterCycle':s['cycle'],'effectCycle':s['effectCycle'],'effectFps':20,'exportFrames':len(s['effects']),'exportDurationMs':len(s['effects'])*50,'frozenPoseEffectProgression':True,'nativeInstallation':'not performed'})
    print(s['id'],'exported',flush=True)
(ROOT/'export-check.json').write_text(json.dumps(summary,indent=2))
