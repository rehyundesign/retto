"""Pose-linked contact accents. Ambient PNG clocks remain independent during holds."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
import json,math
PLAN=json.loads((Path(__file__).resolve().parent.parent/'interaction/plan.json').read_text())
ROOT=Path(__file__).resolve().parent.parent

def draw(canvas,row,pose_time,effect_time,gaze=False):
 if gaze:return canvas
 plan=PLAN;spec=plan['effects'][str(row)]
 if spec['strength']==0:return canvas
 phase=(max(0,pose_time)/plan['rows'][str(row)]['cycle'])%1;delta=abs(phase-spec['peak']);delta=min(delta,1-delta);power=max(0,1-delta/spec['width'])**2*spec['strength']
 if power<.01:return canvas
 x,y=spec['anchor'];image=Image.new('RGBA',canvas.size);d=ImageDraw.Draw(image);mode=spec['mode'];pink=(255,82,154)
 if mode=='ring':
  for j in range(2):
   rx=22+22*power+j*9;ry=4+5*power+j*2;d.ellipse((x-rx,y-ry,x+rx,y+ry),outline=(*pink,round(150*power/(j+1))),width=2)
 else:
  for radius,alpha in [(18,45),(11,85),(4,200)]:d.ellipse((x-radius,y-radius,x+radius,y+radius),fill=(*pink,round(alpha*power)))
  if mode=='signal':
   for j in range(2):
    radius=15+j*9+power*4;d.arc((x-radius,y-radius,x+radius,y+radius),280,75,fill=(*pink,round(130*power)),width=2)
  for j in range(3):
   angle=(j-1)*.8;distance=12+15*power;px=x+(-1 if x<224 else 1)*math.cos(angle)*distance;py=y+math.sin(angle)*distance;r=5+power*3
   if mode=='glint':d.polygon([(px,py-r),(px+r*.45,py),(px,py+r),(px-r*.45,py)],fill=(255,224,183,round(245*power)))
   else:
    points=[(px+r*math.sin(a)**3,py-r*(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))/16) for a in [i*math.tau/32 for i in range(32)]];d.polygon(points,fill=(*pink,round(245*power)))
 if mode!='ring':d.polygon([(x,y-5),(x+2.5,y),(x,y+5),(x-2.5,y)],fill=(255,244,250,round(230*min(1,power))))
 glow=image.filter(ImageFilter.GaussianBlur(3 if mode=='ring' else 4));glow.alpha_composite(image);canvas.alpha_composite(glow);return canvas
