from pathlib import Path
from PIL import Image,ImageDraw
import json,hashlib
import numpy as np
root=Path(__file__).resolve().parent.parent
for side in ['left','right']:
 r=root/'motion'/f'ran-interaction-{side}-v1';records=[]
 for i in range(8):
  p=r/'raw'/f'R{i:02}.png'
  if not p.exists():continue
  image=Image.open(p).convert('RGBA');box=image.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox();image=image.crop(box);image.thumbnail((84,84),Image.Resampling.LANCZOS);cell=Image.new('RGBA',(90,90));cell.alpha_composite(image,((90-image.width)//2,(90-image.height)//2));a=np.array(cell);a[a[:,:,3]==0,:3]=0;cell=Image.fromarray(a);cell.save(r/'character'/f'R{i:02}.png');records.append({'id':f'R{i:02}','source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'source':str(p),'source_bounds':box,'output':[90,90],'whole_source_only':True,'mirrored':False})
 (r/'registration.json').write_text(json.dumps(records,indent=2)+'\n')
 for theme,bg in [('light','#fffdfa'),('dark','#23232d')]:
  board=Image.new('RGB',(400,248),bg);d=ImageDraw.Draw(board)
  for record in records:
   i=int(record['id'][1:]);image=Image.open(r/'character'/f'R{i:02}.png');x=i%4*100;y=i//4*124;board.paste(image,(x+5,y+24),image);d.text((x+5,y+5),f'R{i:02}',fill='gray')
  board.save(r/f'poses-{theme}-1x.png')
 print(side,len(records))
