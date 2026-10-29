"""Compose reviewed independent cells; animation drawings are never warped or patched."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import hashlib,json,math,sys
import numpy as np
root=Path(__file__).resolve().parent
name=sys.argv[1];r=root/(name+'-v1')
entry=next(x for x in json.loads((root.parent/'full-motion-plan.json').read_text())['remaining_states'] if x['id']==name)
cycle=entry['seconds'];dt=cycle/16;heart_outfit=entry['costume']=='heart'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
paths=[r/'character'/f'F{i:02}.png' for i in range(16)]
cats=[Image.open(p).convert('RGBA') for p in paths]
locks={str(p):sha(p) for p in paths}
assert len({hashlib.sha256(im.tobytes()).hexdigest() for im in cats})==16
source_hashes={sha(r/'raw'/f'F{i:02}.png') for i in range(16)}
assert len(source_hashes)==16
pets=[]
for i in range(8):
    source=root/'ran-sleep-v1/raw'/f'R{i:02}.png' if name=='sleeping' else root/'idle-v2/companion'/f'R{i:02}.png'
    im=Image.open(source).convert('RGBA');im=im.crop(im.getchannel('A').point(lambda a:255 if a>8 else 0).getbbox())
    im.thumbnail((90,90),Image.Resampling.LANCZOS);cell=Image.new('RGBA',(90,90));cell.alpha_composite(im,((90-im.width)//2,(90-im.height)//2))
    ar=np.array(cell);ar[ar[:,:,3]==0,:3]=0;cell=Image.fromarray(ar)
    cell.save(r/'companion'/f'R{i:02}.png');pets.append(cell)

def draw_heart(d,x,y,size,color):
    points=[]
    for k in range(48):
        a=k*math.tau/48;points.append((x+size*math.sin(a)**3,y-size*(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))/16))
    d.polygon(points,fill=color)

def clean(im):
    a=np.array(im);a[a[:,:,3]==0,:3]=0;return Image.fromarray(a)

def effects(t):
    t=round(t%8,8);back=Image.new('RGBA',(448,640));front=back.copy();d=ImageDraw.Draw(back)
    count=5 if heart_outfit else 3
    for j in range(count):
        u=(t/8+j/count)%1;opacity=round((135 if heart_outfit else 90)*math.sin(math.pi*u)**2)
        if name=='jumping':x,y=75+295*(j/(count-1)),611-70*u
        elif name=='sleeping':x,y=365+20*math.sin(u*math.tau+j),443-80*u;opacity=round(opacity*.55)
        else:x,y=390+21*math.sin(u*math.tau+j),445-170*u
        draw_heart(d,x,y,5 if heart_outfit else 3.5,(243,112,157,opacity))
    if heart_outfit:
        # A thin ribbon lives behind the silhouette, leaving face and limbs readable.
        points=[(390+21*math.sin(t*math.tau/8+k*.22),420+k*2.4) for k in range(60)]
        d.line(points,fill=(244,118,159,70),width=2)
    if name=='waving':
        for j in range(3):
            u=(t/8+j/3)%1;a=round(155*math.sin(math.pi*u)**2)
            draw_heart(d,38+12*math.sin(math.tau*u+j),553-170*u,4+2*math.sin(math.pi*u),(246,117,166,a))
    if name=='jumping':
        u=(t/8)%1;a=round(90*math.sin(math.pi*u)**2)
        d.ellipse((115-18*u,607-5*u,245+18*u,617+5*u),outline=(255,173,206,a),width=2)
    elif name=='failed':
        u=(t/8)%1;a=round(100*math.sin(math.pi*u)**2)
        for j in range(5):
            a0=j*math.tau/5;x=389+math.cos(a0)*(8+27*u);y=365+math.sin(a0)*(8+27*u)
            d.ellipse((x-2,y-2,x+2,y+2),outline=(247,166,190,a),width=1)
    elif name=='waiting':
        for j in range(3):
            u=(t/8+j/3)%1;radius=6+19*u;a=round(95*math.sin(math.pi*u)**2)
            d.arc((229-radius,506-radius,229+radius,506+radius),290,75,fill=(251,149,188,a),width=2)
    elif name=='running':
        u=t/8;a=round(65+30*math.sin(math.tau*u))
        d.ellipse((26,460,316,532),outline=(248,153,190,a),width=1)
        for j in range(3):
            v=math.tau*(u+j/3);draw_heart(d,171+145*math.cos(v),496+36*math.sin(v),3,(248,153,190,110))
    elif name=='review':
        u=t/8;radius=14+3*math.sin(math.tau*u)
        d.arc((153-radius,476-radius,153+radius,476+radius),u*360,u*360+235,fill=(255,196,171,105),width=1)
    elif name=='sleeping':
        u=t/8;x=370+12*math.sin(math.tau*u);y=342-8*math.cos(math.tau*u)
        d.arc((x-10,y-13,x+10,y+13),60,280,fill=(230,174,211,75),width=2)
    d=ImageDraw.Draw(front)
    if name=='waiting':
        for j in range(3):
            u=(t/8+j/3)%1;radius=6+15*u;a=round(105*math.sin(math.pi*u)**2)
            d.arc((280-radius,506-radius,280+radius,506+radius),290,75,fill=(251,149,188,a),width=1)
    elif name=='review':
        for j in range(2):
            a=math.tau*(t/8+j/2);x=153+20*math.cos(a);y=467+11*math.sin(a);op=round(135*math.sin(a)**2)
            d.polygon([(x,y-3),(x+2,y),(x,y+3),(x-2,y)],fill=(255,214,181,op))
    for j in range(2):
        a=math.tau*(t/8+j/2);x=397+21*math.cos(a);y=(390 if heart_outfit else 356)+34*math.sin(a)
        opacity=round(120*(.5+.5*math.cos(2*a))**2)
        if name=='sleeping':opacity=round(opacity*.4);y+=80
        d.polygon([(x,y-4),(x+2,y),(x,y+4),(x-2,y)],fill=(255,210,228,opacity))
    if name in ['running','review','waiting']:
        x,y={'running':(169,496),'review':(153,476),'waiting':(235,507)}[name]
        a=math.tau*t/8;glow=round(70*math.sin(a)**2)
        d.ellipse((x-5,y-5,x+5,y+5),outline=(255,179,206,glow),width=1)
    return clean(back),clean(front)

def scene(t,bare=False,held=False):
    k=0 if held else int((t%cycle)/dt+1e-7)%16
    if bare:return cats[k].copy()
    sample=math.floor((t%8)*10+1e-7)%80
    back,front=effects(sample/10);back.alpha_composite(cats[k]);phase=math.tau*t/cycle
    x,y=(344,396) if heart_outfit else (350,329)
    amplitude=3
    if name=='sleeping':x,y,amplitude=350,378,.5
    if name=='jumping':y+=round((entry['lowest_paw_targets_2x'][int(((t-dt)%cycle)/dt)%16]-629)*.45)
    pos=(round(x+amplitude*.5*math.sin(phase-.4)),round(y-amplitude*math.sin(phase-.6)))
    pet=int(((t-dt)%cycle)/(cycle/8)+1e-7)%8
    back.alpha_composite(pets[pet],pos);back.alpha_composite(front);return back

for i in range(80):
    for layer,im in zip(['effect_back','effect_front'],effects(i/10)):
        bounds=im.getchannel('A').getbbox();assert not bounds or (min(bounds[:2])>=12 and bounds[2]<=436 and bounds[3]<=628)
        im.save(r/layer/f'{i:03}.png')
ticks=round(cycle*20);period=math.lcm(round(cycle*10),80)/10
font=ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc',13)
for theme,bg,ink in [('light','#fffdfa','#51444d'),('dark','#23232d','#f0e7ee')]:
    for bare,label,duration in [(True,'character-only',cycle),(False,name,period)]:
        frames=[]
        for i in range(round(duration*20)):
            im=scene(i/20,bare=bare).resize((224,320),Image.Resampling.LANCZOS)
            cell=Image.new('RGBA',(224,320),bg);cell.alpha_composite(im);frames.append(cell.convert('RGB'))
        frames[0].save(r/f'{label}-{theme}.gif',save_all=True,append_images=frames[1:],duration=50,loop=0,disposal=2,optimize=False)
    for bare,label in [(True,'character'),(False,'frames')]:
        board=Image.new('RGB',(960,1408),bg);d=ImageDraw.Draw(board)
        for i in range(16):
            x,y=i%4*240,i//4*352;im=scene(i*dt,bare=bare).resize((224,320),Image.Resampling.LANCZOS)
            d.text((x+8,y+6),f'F{i:02} · {i*dt:.2f}s',font=font,fill=ink);board.paste(im,(x+8,y+28),im)
        board.save(r/f'{label}-{theme}-1x.png')
assert all(sha(Path(p))==h for p,h in locks.items())
assert scene(0).tobytes()==scene(period).tobytes()
assert all(a.tobytes()!=b.tobytes() for a,b in zip(effects(.1),effects(1.1)))
delivery={'state':name,'action':entry['theme'],'character_drawings':16,'unique_source_sha256':len(source_hashes),'unique_decoded_characters':16,
          'repeated_or_reversed_filler':0,'cat_cycle_seconds':cycle,'cat_interval_seconds':dt,'pet_independent_drawings':8,
          'effects_period_seconds':8,'effects_samples_per_layer':80,'effects_hz':10,'gif_period_seconds':period,'gif_sampling_hz':20,
          'character_sources_locked':locks,'frozen_character_effect_clock_verified':True,'native_changed':False,'installed':False,
          'visual_review':'pending','original_mask_certification':False,'display':[224,320]}
(r/'delivery.json').write_text(json.dumps(delivery,indent=2)+'\n');print(name,'built',cycle,'seconds, composite',period,'seconds')
