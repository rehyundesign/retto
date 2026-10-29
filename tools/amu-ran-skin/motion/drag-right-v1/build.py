"""Review only: independently generated whole-character gait + separate Ran/effects."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import hashlib,json,math
r=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
rows=json.loads((r/'registration.json').read_text());assert len(rows)==16
assert len({x['source_sha256'] for x in rows})==16
assert all(not x['regional_patches'] and not x['warp'] for x in rows)
cats=[Image.open(r/'character'/f'F{i:02}.png').convert('RGBA') for i in range(16)]
assert len({hashlib.sha256(im.tobytes()).hexdigest() for im in cats})==16
locked={f'F{i:02}.png':sha(r/'character'/f'F{i:02}.png') for i in range(16)}
pets=[]
for i in range(8):
 p=r.parent/'idle-v2/companion'/f'R{i:02}.png';im=Image.open(p).convert('RGBA');im.save(r/'companion'/p.name);pets.append(im)
def heart(d,x,y,s,col):
 pts=[]
 for k in range(40):
  a=k*math.tau/40;pts.append((round(x+s*math.sin(a)**3,4),round(y-s*(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))/16,4)))
 d.polygon(pts,fill=col)
def effects(t):
 t=round(t%8,8);back=Image.new('RGBA',(448,640));front=back.copy();d=ImageDraw.Draw(back)
 for i in range(4):
  u=(t/8+i/4)%1;alpha=round(115*math.sin(math.pi*u)**2)
  heart(d,round(186-115*u,4),round(337-42*u+7*math.sin(math.tau*u),4),3.5,(238,102,146,alpha))
 d=ImageDraw.Draw(front)
 for i in range(2):
  u=(t/8+i/2)%1;x=round(187-79*u,4);y=round(315-19*math.sin(math.pi*u),4);a=round(100*math.sin(math.pi*u)**2)
  d.polygon([(x,y-3),(x+2,y),(x,y+3),(x-2,y)],fill=(245,177,193,a))
 return back,front
def scene(t,bare=False,held=False):
 k=0 if held else int((t%1.6)/.1+1e-6)%16
 if bare:return cats[k].copy()
 back,front=effects(t);back.alpha_composite(cats[k])
 angle=math.tau*t/1.6;pos=(round(145+3*math.sin(angle-.5)),round(248+3*math.sin(angle-.6)))
 p=int(((t-.2)%1.6)/.2+1e-6)%8;back.alpha_composite(pets[p],pos);back.alpha_composite(front);return back
for i in range(80):
 for name,im in zip(['effect_back','effect_front'],effects(i/10)):
  b=im.getchannel('A').getbbox();assert not b or(min(b[:2])>=12 and b[2]<=436 and b[3]<=628)
  im.save(r/name/f'{i:03}.png')
font=ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc',13)
for theme,bg,ink in [('light','#fffdfa','#51444d'),('dark','#23232d','#f0e7ee')]:
 frames=[];bare=[]
 for i in range(80):
  im=scene(i/10).resize((224,320),Image.Resampling.LANCZOS);out=Image.new('RGBA',(224,320),bg);out.alpha_composite(im);frames.append(out.convert('RGB'))
 frames[0].save(r/f'drag-right-{theme}.gif',save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=2,optimize=False)
 for im in cats:
  out=Image.new('RGBA',(224,320),bg);out.alpha_composite(im.resize((224,320),Image.Resampling.LANCZOS));bare.append(out.convert('RGB'))
 bare[0].save(r/f'character-only-{theme}.gif',save_all=True,append_images=bare[1:],duration=100,loop=0,disposal=2,optimize=False)
 board=Image.new('RGB',(960,1408),bg);d=ImageDraw.Draw(board)
 compare=Image.new('RGB',(448*4,640*4),bg)
 for i,im in enumerate(cats):
  x,y=i%4*240,i//4*352;d.text((x+8,y+6),f'F{i:02} · {i*.1:.1f}s',font=font,fill=ink)
  cell=scene(i*.1).resize((224,320),Image.Resampling.LANCZOS);board.paste(cell,(x+8,y+28),cell)
  compare.paste(im,(i%4*448,i//4*640),im)
 board.save(r/f'frames-{theme}-1x.png');compare.save(r/f'character-detail-{theme}.png')
assert locked=={p:sha(r/'character'/p) for p in locked}
assert scene(0).tobytes()==scene(8).tobytes()
assert all(a.tobytes()!=b.tobytes() for a,b in zip(effects(.1),effects(1.1)))
assert scene(.1,held=True).tobytes()!=scene(1.1,held=True).tobytes()
for theme in ['light','dark']:
 im=Image.open(r/f'drag-right-{theme}.gif');dur=0
 for i in range(im.n_frames):im.seek(i);dur+=im.info['duration']
 assert dur==8000
out={'state':'drag-right','review_status':'pending visual review','character_drawings':16,'unique_source_ids':16,'unique_decoded_characters':16,'source_pose_authority':'eight original row1 gait poses plus eight independent midpoints','repeated_or_reversed_filler':0,'cat_cycle_seconds':1.6,'drawing_hold_ms':100,'effects_cycle_seconds':8,'effect_samples_per_layer':80,'effects_hz':10,'gif_seconds':8,'gif_sampling_hz':10,'pet_independent_drawings':8,'pet_clock_seconds':1.6,'pet_lag_seconds':.2,'runtime_display':[224,320],'character_source_locks':locked,'frozen_pose_effects_progress':True,'native_changed':False,'installed':False,'next_state_started':False,'strict_original_landmark_certification':'not established by source counts; diagnostic residuals and visual review retained separately'}
(r/'delivery.json').write_text(json.dumps(out,indent=2)+'\n')
print('Built 16-drawing 1.6s right-gait; combined8s GIF; source locks and effect clock verified.')
