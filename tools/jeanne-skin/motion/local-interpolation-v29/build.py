from pathlib import Path
from PIL import Image
import json,hashlib,zipfile,argparse

parser=argparse.ArgumentParser();parser.add_argument('--variant',default='');args=parser.parse_args()
script_root=Path(__file__).resolve().parent;root=script_root.parent;p=script_root/args.variant if args.variant else script_root
report={'model':'FILM PyTorch CPU' if args.variant=='film' else 'RIFE4.6 ncnn CPU','nativeAppPlayback':'not checked','originalAbsoluteRegistration':'not certified','states':[],'scope':'existing16 integrated drawings preserved;16 inferred midpoints added per state; no new independent key poses'}
for state,total_ms in [('waving',2400),('waiting',3200)]:
 d=p/state;frames=[];raw=[]
 for i in range(32):
  im=Image.open(d/f'{i:02}.png').convert('RGBA');assert im.size==(448,640)
  raw.append(im.copy());frames.append(im.resize((224,320),Image.Resampling.LANCZOS))
  if i%2==0:
   original=Image.open(root/'integrated-repair-v27'/state/f'{i//2:02}.png').convert('RGBA')
   assert im.tobytes()==original.tobytes(),(state,i)
 durations=[75]*32 if state=='waving' else [100]*32
 raw[0].save(d/'animation-transparent.webp',save_all=True,append_images=raw[1:],duration=durations,loop=0,lossless=True)
 for theme,color in [('dark','#181827'),('white','#fffdf8')]:
  flattened=[];board=Image.new('RGB',(896,1280),color)
  for i,im in enumerate(frames):
   bg=Image.new('RGBA',(224,320),color);bg.alpha_composite(im);flattened.append(bg.convert('RGB'))
   if i%2:board.paste(flattened[-1],((i//2%4)*224,(i//2//4)*320))
  board.save(d/f'midpoints-{theme}.png')
  gif_times=[70,80]*16 if state=='waving' else [100]*32
  for ext in ['gif','webp']:
   kwargs={'disposal':2} if ext=='gif' else {'lossless':True}
   times=gif_times if ext=='gif' else durations
   dest=d/f'animation-{theme}.{ext}'
   flattened[0].save(dest,save_all=True,append_images=flattened[1:],duration=times,loop=0,**kwargs)
   decoded=Image.open(dest);assert decoded.n_frames==32,(dest,decoded.n_frames)
   dt=[]
   for i in range(32):decoded.seek(i);decoded.load();dt.append(decoded.info['duration'])
   assert sum(dt)==total_ms,(dest,dt)
  seam=Image.new('RGB',(1344,320),color)
  for k,i in enumerate([28,29,30,31,0,1]):seam.paste(flattened[i],(k*224,0))
  seam.save(d/f'loop-{theme}.png')
 report['states'].append({'id':state,'originalIndependentDrawings':16,'modelInferredMidpoints':16,'playbackFrames':32,'cycleMs':total_ms,'originalPixelsPreserved':True,'matting':'paired black/white RGB inference; reconstructed soft alpha','sourceHashes':[hashlib.sha256((root/'integrated-repair-v27'/state/f'{i:02}.png').read_bytes()).hexdigest() for i in range(16)]})
with zipfile.ZipFile(p/'jeanne-png-frames.zip','w',zipfile.ZIP_DEFLATED) as z:
 for state in ['waving','waiting']:
  for i in range(32):z.write(p/state/f'{i:02}.png',f'{state}/{i:02}.png')
(p/'validation.json').write_text(json.dumps(report,indent=2))
print('64 RGBA PNGs;32 original cells pixel-exact;32 inferred midpoints;GIF/WebP frame counts and durations pass')
