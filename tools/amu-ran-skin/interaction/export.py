"""Recompose only the partner layer. Character/gaze/effect PNGs remain immutable."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
from functools import lru_cache
import sys,json,hashlib,math
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(Path(__file__).resolve().parent))
import runtime as ran
sys.path.insert(0,str(ROOT/'effects'))
import accents
config=json.loads((ROOT/'review-config.json').read_text())
if len(sys.argv)>1:config=[s for s in config if s['id'] in sys.argv[1:]]
font=ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc',13)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for s in config:
 r=ROOT/s['path'];cats=[Image.open(r/'character'/f'F{i:02}.png').convert('RGBA') for i in range(16)];locks={str(p):sha(p) for p in (r/'character').glob('F*.png')}
 @lru_cache(maxsize=16)
 def fx(layer,n):return Image.open(r/('effect_'+layer)/f'{n:03}.png').convert('RGBA')
 def scene(t):
  k=int(math.floor((t%s['cycle'])/(s['cycle']/16)+1e-7))%16;sample=int(math.floor((t%8)*10+1e-7))%80
  canvas=fx('back',sample).copy();canvas.alpha_composite(cats[k]);ran.draw(canvas,s['row'],t,t);canvas.alpha_composite(fx('front',sample));accents.draw(canvas,s['row'],t,t);return canvas
 period=math.lcm(round(s['cycle']*10),80)/10
 assert scene(0).tobytes()==scene(period).tobytes(),s['id']
 for theme,bg,ink in [('light','#fffdfa','#51444d'),('dark','#23232d','#f0e7ee')]:
  frames=[]
  for i in range(round(period*20)):
   cell=Image.new('RGBA',(224,320),bg);cell.alpha_composite(scene(i/20).resize((224,320),Image.Resampling.LANCZOS));frames.append(cell.convert('RGB'))
  frames[0].save(r/f"{s['id']}-{theme}.gif",save_all=True,append_images=frames[1:],duration=50,loop=0,disposal=2,optimize=False)
  board=Image.new('RGB',(960,1408),bg);d=ImageDraw.Draw(board)
  for i in range(16):
   x,y=i%4*240,i//4*352;cell=scene(i*s['cycle']/16).resize((224,320),Image.Resampling.LANCZOS);board.paste(cell,(x+8,y+28),cell);d.text((x+8,y+6),f'F{i:02}',fill=ink,font=font)
  board.save(r/f'frames-{theme}-1x.png')
 assert all(sha(Path(p))==h for p,h in locks.items())
 delivery=json.loads((r/'delivery.json').read_text());delivery.update({'partner_interaction':'../../interaction/plan.json','partner_source_drawings':8,'partner_poses':'sleep8 reused' if s['row']==11 else ran.PLAN['rows'][str(s['row'])]['side']+'8 independent interaction poses','partner_clock':'character pose epoch; independent breathing during holds','gif_sampling_hz':20,'native_changed':True});(r/'delivery.json').write_text(json.dumps(delivery,indent=2)+'\n')
 print(s['id'],'partner GIFs and16-frame boards recomposed',flush=True)
