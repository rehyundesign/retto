from pathlib import Path
from PIL import Image,ImageDraw
import subprocess,sys
root=Path(__file__).resolve().parent
for state in ['jumping','failed','waiting','running','review','sleeping']:
 r=root/(state+'-v1')
 if len(list((r/'raw').glob('F*.png')))!=16:
  print('pending',state,flush=True);continue
 script=root/'register-sleep.py' if state=='sleeping' else root/'register-front.py';args=[] if state=='sleeping' else [state+'-v1']
 run=subprocess.run([sys.executable,str(script),*args],capture_output=True,text=True)
 if run.returncode:print(run.stderr,flush=True);raise SystemExit(run.returncode)
 for theme,bg in [('light','#fffdfa'),('dark','#23232d')]:
  board=Image.new('RGB',(960,1408),bg);d=ImageDraw.Draw(board)
  for i in range(16):
   im=Image.open(r/'character'/f'F{i:02}.png').resize((224,320),Image.Resampling.LANCZOS);x,y=i%4*240,i//4*352;board.paste(im,(x+8,y+25),im);d.text((x+8,y+6),f'F{i:02}',fill='gray')
  board.save(r/f'character-{theme}-1x.png')
 print('registered and character boards ready:',state,flush=True)
