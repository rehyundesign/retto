from pathlib import Path
from PIL import Image,ImageDraw
import json,hashlib
p=Path(__file__).parent
frames=[]
for i in range(16):
 f=p/f'{i:02}-source.png';assert f.exists(),f
 im=Image.open(f).convert('RGBA').resize((448,640),Image.Resampling.LANCZOS);im.save(p/f'{i:02}.png')
assert len({hashlib.sha256((p/f'{i:02}-source.png').read_bytes()).hexdigest() for i in range(16)})==16
for theme,color in [('dark','#181827'),('white','#fffdf8')]:
 frames=[];board=Image.new('RGB',(896,1344),color);draw=ImageDraw.Draw(board)
 for i in range(16):
  im=Image.open(p/f'{i:02}.png').resize((224,320));bg=Image.new('RGBA',(224,320),color);bg.alpha_composite(im);frames.append(bg.convert('RGB'));board.paste(frames[-1],(i%4*224,i//4*336));draw.text((i%4*224+8,i//4*336+320),str(i),fill='#888888')
 board.save(p/f'review-{theme}.png')
 for ext in ['gif','webp']:
  kwargs={'disposal':2} if ext=='gif' else {'lossless':True}
  f=p/f'animation-{theme}.{ext}';frames[0].save(f,save_all=True,append_images=frames[1:],duration=150,loop=0,**kwargs)
  dec=Image.open(f);assert dec.n_frames==16
  for i in range(16):dec.seek(i);dec.load();assert dec.info['duration']==150
(p/'manifest.json').write_text(json.dumps({'state':'running','row':7,'frames':16,'durationMs':2400,'integrated':True,'sourceHashes':[hashlib.sha256((p/f'{i:02}-source.png').read_bytes()).hexdigest() for i in range(16)]},indent=2))
import zipfile
with zipfile.ZipFile(p/'jeanne-running-png.zip','w',zipfile.ZIP_DEFLATED) as z:
    for i in range(16):z.write(p/f'{i:02}.png',f'running/{i:02}.png')
print('16 complete running frames,2.4s GIF/WebP and PNG package exported')
