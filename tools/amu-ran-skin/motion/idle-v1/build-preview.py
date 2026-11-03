"""Render the idle-only review GIF from 16 independent character drawings.

Character: 3.2s / 16 drawings. Companion: 3.2s / 8 drawings. Effects: 8s
at 10Hz, independently progressing. Combined GIF closes after 16 seconds.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib, json, math

root=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
plan=json.loads((root/'plan.json').read_text())
order=plan['frame_order']
characters=[Image.open(root/'character'/f'F{i:02}.png').convert('RGBA') for i in order]
assert len({hashlib.sha256(im.tobytes()).hexdigest() for im in characters})==16
registrations=json.loads((root/'registration.json').read_text())
assert len(registrations)==16 and len({r['source_sha256'] for r in registrations})==16
source_hashes={p:sha(p) for p in (root/'raw').glob('*.png')}
master=Image.open(root/'reference/school-master.png').convert('RGBA')
companions=[]
for i in range(8):
    path=root/'companion'/f'R{i:02}-raw.png'
    im=Image.open(path).convert('RGBA')
    bounds=im.getchannel('A').point(lambda a:255 if a>8 else 0).getbbox()
    im=im.crop(bounds);im.thumbnail((90,90),Image.Resampling.LANCZOS)
    cell=Image.new('RGBA',(90,90));cell.alpha_composite(im,((90-im.width)//2,(90-im.height)//2))
    cell.save(root/'companion'/f'R{i:02}.png');companions.append(cell)
assert len({hashlib.sha256(im.tobytes()).hexdigest() for im in companions})==8

def heart(draw,x,y,size,fill):
    points=[]
    for i in range(40):
        a=i/40*math.tau
        points.append((x+size*math.sin(a)**3,y-size*(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))/16))
    draw.polygon(points,fill=fill)

def effects(t):
    t=round(t%8,8)
    back=Image.new('RGBA',(448,640));front=back.copy()
    for j in range(3):
        u=(t/8+j/3)%1
        opacity=int(130*math.sin(math.pi*u)**2)
        x=375+27*math.sin(math.tau*(u+j*.17));y=416-140*u
        heart(ImageDraw.Draw(back),x,y,4+j%2,(236,101,150,opacity))
    d=ImageDraw.Draw(front)
    for j in range(3):
        a=math.tau*(t/8+j/3);x=389+31*math.cos(a);y=357+52*math.sin(a)
        strength=int(110*(.5+.5*math.sin(a*2))**2)
        d.line([(x-3,y),(x+3,y)],fill=(245,174,122,strength),width=1)
        d.line([(x,y-3),(x,y+3)],fill=(245,174,122,strength),width=1)
    return back,front

def scene(t,character_only=False,held=False):
    i=0 if held else int((t%3.2)/.2+1e-6)%16
    if character_only:return characters[i].copy()
    back,front=effects(t)
    back.alpha_composite(characters[i])
    # A small separate guardian floats; the cat/support layer never translates.
    angle=math.tau*t/3.2
    pos=(round(357+3*math.sin(angle-.3)),round(329-5*math.sin(angle-.6)))
    index=int(((t-.2)%3.2)/.4+1e-6)%8
    back.alpha_composite(companions[index],pos)
    back.alpha_composite(front)
    return back

for i in range(80):
    for layer,im in zip(['effect_back','effect_front'],effects(i/10)):
        im.save(root/layer/f'{i:03}.png')
font=ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc',13)
for theme,bg,ink in [('light','#fffdfa','#51444d'),('dark','#23232d','#f0e7ee')]:
    frames=[];bare=[]
    for tick in range(160):
        im=scene(tick/10).resize((224,320),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',(224,320),bg);canvas.alpha_composite(im);frames.append(canvas.convert('RGB'))
    for i in range(16):
        canvas=Image.new('RGBA',(224,320),bg)
        canvas.alpha_composite(characters[i].resize((224,320),Image.Resampling.LANCZOS));bare.append(canvas.convert('RGB'))
    frames[0].save(root/f'idle-{theme}.gif',save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=2,optimize=False)
    bare[0].save(root/f'character-only-{theme}.gif',save_all=True,append_images=bare[1:],duration=200,loop=0,disposal=2,optimize=False)
    board=Image.new('RGB',(960,1408),bg);draw=ImageDraw.Draw(board)
    for i in range(16):
        x,y=i%4*240,i//4*352
        draw.text((x+8,y+6),f'F{order[i]:02} · {i*.2:.1f}s',font=font,fill=ink)
        im=scene(i*.2).resize((224,320),Image.Resampling.LANCZOS)
        board.paste(im,(x+8,y+28),im)
    board.save(root/f'frames-{theme}-1x.png')

for p,expected in source_hashes.items():assert sha(p)==expected
for name,expected in plan['frozen_sources'].items():assert sha(root/'reference'/name)==expected
for theme in ['light','dark']:
    gif=Image.open(root/f'idle-{theme}.gif')
    duration=0
    for i in range(gif.n_frames):gif.seek(i);duration+=gif.info['duration']
    assert duration==16000
assert scene(0).tobytes()==scene(16).tobytes()
assert scene(.1,held=True).tobytes()!=scene(1.1,held=True).tobytes()
assert all(a.tobytes()!=b.tobytes() for a,b in zip(effects(.1),effects(1.1)))
for i,im in enumerate(characters):
    a=im.getchannel('A')
    assert not any(a.crop(box).getbbox() for box in [(0,0,1,640),(447,0,448,640),(0,0,448,1),(0,639,448,640)]),i

manifest={'state':'idle','review_status':'awaiting user GIF review','independent_character_drawings':16,
    'unique_character_pixels':16,'independent_companion_drawings':8,'character_interval_seconds':.2,
    'character_cycle_seconds':3.2,'companion_cycle_seconds':3.2,'companion_delay_seconds':.2,
    'effect_cycle_seconds':8,'effect_samples_per_layer':80,'effect_sample_hz':10,
    'gif_cycle_seconds':16,'gif_tick_ms':100,'rendered_display':[224,320],
    'drawing_ids':[f'F{i:02}' for i in order],'intentional_character_holds':0,
    'frozen_character_effect_progression_check':True,'source_hashes_unchanged':True,
    'four_limb_contract':plan['support'],'native_changed':False,'installed':False,
    'reference':'reference/hana-idle-3.2s.gif','registration':'registration.json',
    'visual_review':{'character_action':'pending','secondary_motion':'pending','loop_seam':'pending',
        'light_dark_1x':'pending','same_scale_hana_comparison':'pending'}}
(root/'delivery.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('PASS: 16 independent cat drawings / 8 Ran drawings; 3.2s cat loop, 8s effects, 16s GIF; source locks, bounds and frozen-pose effects verified.')
