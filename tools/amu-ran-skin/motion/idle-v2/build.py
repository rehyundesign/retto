"""Idle review from complete independent full-character poses.

No animated face, body, paw, clothes or tail replacement masks are used here.
"""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import hashlib,json,math

root=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
records=json.loads((root/'registration.json').read_text());byid={r['id']:r for r in records}
assert set(byid)=={f'F{i:02}' for i in range(16)}
assert all(byid[f'F{i:02}']['regional_grafts'] is False for i in range(1,16))
assert len({r['source_sha256'] for r in records})==16
cats=[Image.open(root/'character'/f'F{i:02}.png').convert('RGBA') for i in range(16)]
assert len({hashlib.sha256(im.tobytes()).hexdigest() for im in cats})==16
locked={root/'character'/f'F{i:02}.png':sha(root/'character'/f'F{i:02}.png') for i in range(16)}
companions=[]
for i in range(8):
    source=root.parent/'idle-v1/companion'/f'R{i:02}-raw.png'
    im=Image.open(source).convert('RGBA');im=im.crop(im.getchannel('A').point(lambda a:255 if a>8 else 0).getbbox())
    im.thumbnail((90,90),Image.Resampling.LANCZOS)
    cell=Image.new('RGBA',(90,90));cell.alpha_composite(im,((90-im.width)//2,(90-im.height)//2))
    cell.save(root/'companion'/f'R{i:02}.png');companions.append(cell)

def heart(d,x,y,s,color):
    points=[]
    for k in range(40):
        a=k*math.tau/40
        points.append((round(x+s*math.sin(a)**3,4),round(y-s*(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))/16,4)))
    d.polygon(points,fill=color)

def effects(t):
    t=round(t%8,8);back=Image.new('RGBA',(448,640));front=back.copy()
    d=ImageDraw.Draw(back)
    for j in range(3):
        u=(t/8+j/3)%1;opacity=round(110*math.sin(math.pi*u)**2)
        heart(d,round(392+19*math.sin(math.tau*(u+j*.13)),4),round(415-133*u,4),4,(238,102,146,opacity))
    d=ImageDraw.Draw(front)
    for j in range(2):
        a=math.tau*(t/8+j/2);x=round(392+25*math.cos(a),4);y=round(365+38*math.sin(a),4)
        opacity=round(95*(.5+.5*math.cos(a*2))**2)
        d.polygon([(x,y-3),(x+2,y),(x,y+3),(x-2,y)],fill=(244,175,184,opacity))
    return back,front

def scene(t,bare=False,held=False):
    k=0 if held else int((t%3.2)/.2+1e-6)%16
    if bare:return cats[k].copy()
    back,front=effects(t);back.alpha_composite(cats[k])
    angle=math.tau*t/3.2
    pos=(round(356+2*math.sin(angle-.4)),round(329-4*math.sin(angle-.5)))
    pet=int(((t-.2)%3.2)/.4+1e-6)%8
    back.alpha_composite(companions[pet],pos);back.alpha_composite(front);return back

for i in range(80):
    for name,im in zip(['effect_back','effect_front'],effects(i/10)):
        a=im.getchannel('A');bounds=a.getbbox()
        assert not bounds or (min(bounds[:2])>=12 and bounds[2]<=436 and bounds[3]<=628)
        im.save(root/name/f'{i:03}.png')
font=ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc',13)
for theme,bg,ink in [('light','#fffdfa','#51444d'),('dark','#23232d','#f0e7ee')]:
    frames=[];bare=[]
    for i in range(160):
        im=scene(i/10).resize((224,320),Image.Resampling.LANCZOS)
        c=Image.new('RGBA',(224,320),bg);c.alpha_composite(im);frames.append(c.convert('RGB'))
    frames[0].save(root/f'idle-{theme}.gif',save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=2,optimize=False)
    for im in cats:
        c=Image.new('RGBA',(224,320),bg);c.alpha_composite(im.resize((224,320),Image.Resampling.LANCZOS));bare.append(c.convert('RGB'))
    bare[0].save(root/f'character-only-{theme}.gif',save_all=True,append_images=bare[1:],duration=200,loop=0,disposal=2,optimize=False)
    board=Image.new('RGB',(960,1408),bg);draw=ImageDraw.Draw(board)
    for i in range(16):
        x,y=i%4*240,i//4*352;im=scene(i*.2).resize((224,320),Image.Resampling.LANCZOS)
        draw.text((x+8,y+6),f'F{i:02} · {i*.2:.1f}s',font=font,fill=ink);board.paste(im,(x+8,y+28),im)
    board.save(root/f'frames-{theme}-1x.png')
    # 2x character-only strip for detailed costume attachment review, not a source.
    strip=Image.new('RGB',(448*4,640*4),bg)
    for i,im in enumerate(cats):strip.paste(im,(i%4*448,i//4*640),im)
    strip.save(root/f'character-detail-{theme}.png')
for path,expected in locked.items():assert sha(path)==expected
assert scene(0).tobytes()==scene(16).tobytes()
assert all(a.tobytes()!=b.tobytes() for a,b in zip(effects(.1),effects(1.1)))
for theme in ['light','dark']:
    gif=Image.open(root/f'idle-{theme}.gif');duration=0
    for i in range(gif.n_frames):gif.seek(i);duration+=gif.info['duration']
    assert duration==16000
delivery={'state':'idle','version':'v2','review_status':'pending internal visual review then user review',
    'action':'cool casual tie adjustment; actual foreleg/shoulder/sleeve movement; glance at Ran; lower and settle',
    'character_drawings':16,'unique_source_sha256':16,'unique_decoded_characters':16,'repeated_or_reversed_filler':0,
    'complete_generated_motion_cells_without_regional_patches':15,'static_master_original_proportion_fix':'master-registration.json',
    'cat_cycle_seconds':3.2,'cat_interval_seconds':.2,'pet_independent_drawings':8,
    'effects_period_seconds':8,'effects_samples_per_layer':80,'effects_hz':10,'gif_period_seconds':16,
    'display':[224,320],'character_sources_locked':True,'frozen_character_effect_clock_verified':True,
    'native_changed':False,'installed':False,'next_state_started':False,'visual_review':'pending'}
(root/'delivery.json').write_text(json.dumps(delivery,indent=2)+'\n')
print('Built 16 complete-pose idle GIFs: body 3.2s, effects 8s, combined16s; source locks and no motion grafts verified.')
