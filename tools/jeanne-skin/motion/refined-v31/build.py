from pathlib import Path
from PIL import Image,ImageDraw
import json,hashlib,zipfile,shutil
p=Path(__file__).parent;root=p.parent;old=root/'drawn-inbetweens-v30'
times={'waving':[180,120,120,150,150,160,180,160,160,150,130,120,180,150,140,150],'waiting':[240,160,170,180,200,210,230,220,180,200,190,180,180,210,220,230]}
assert sum(times['waving'])==2400 and sum(times['waiting'])==3200
report={}
for state in times:
 d=p/state;d.mkdir(exist_ok=True)
 for i in range(16):
  candidate=d/f'{i:02}-source.png'
  if candidate.exists(): Image.open(candidate).convert('RGBA').resize((448,640),Image.Resampling.LANCZOS).save(d/f'{i:02}.png')
  else:shutil.copy2(old/state/f'{i:02}.png',d/f'{i:02}.png')
 for theme,color in [('dark','#181827'),('white','#fffdf8')]:
  frames=[];board=Image.new('RGB',(896,1280),color)
  for i in range(16):
   im=Image.open(d/f'{i:02}.png').convert('RGBA').resize((224,320),Image.Resampling.LANCZOS)
   bg=Image.new('RGBA',(224,320),color);bg.alpha_composite(im);frames.append(bg.convert('RGB'));board.paste(frames[-1],((i%4)*224,(i//4)*320))
  board.save(d/f'review-{theme}.png')
  for ext in ['gif','webp']:
   kwargs={'disposal':2} if ext=='gif' else {'lossless':True}
   dest=d/f'animation-{theme}.{ext}';frames[0].save(dest,save_all=True,append_images=frames[1:],duration=times[state],loop=0,**kwargs)
   dec=Image.open(dest);assert dec.n_frames==16
   ds=[]
   for i in range(16):dec.seek(i);dec.load();ds.append(dec.info['duration'])
   assert ds==times[state]
  seam=Image.new('RGB',(1120,320),color)
  for k,i in enumerate([13,14,15,0,1]):seam.paste(frames[i],(224*k,0))
  seam.save(d/f'seam-{theme}.png')
 report[state]={'timesMs':times[state],'cycleMs':sum(times[state]),'count':16,'newlyRedrawn':[i for i in range(16) if (d/f'{i:02}-source.png').exists()]}
with zipfile.ZipFile(p/'jeanne-png-frames.zip','w',zipfile.ZIP_DEFLATED) as z:
 for s in times:
  for i in range(16):z.write(p/s/f'{i:02}.png',f'{s}/{i:02}.png')
(p/'timing.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
