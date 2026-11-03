"""Independent eight-second ambient heart/ribbon layers, rendered at2x for clean edges."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
import math,json
import numpy as np
ROOT=Path(__file__).resolve().parent.parent
CONFIG=json.loads((ROOT/'review-config.json').read_text())
TAU=math.tau;S=2

def heart(d,x,y,r,c):
 points=[((x+r*math.sin(a)**3)*S,(y-r*(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))/16)*S) for a in [i*TAU/48 for i in range(48)]];d.polygon(points,fill=c)

def glint(d,x,y,r,c):
 d.polygon([(x*S,(y-r)*S),((x+r*.45)*S,y*S),(x*S,(y+r)*S),((x-r*.45)*S,y*S)],fill=c)

def layers(row,t):
 back=Image.new('RGBA',(448*S,640*S));front=back.copy();d=ImageDraw.Draw(back)
 strong=row in [3,4];color=(246,69,141);count=6 if strong else (2 if row==11 else 4)
 for j in range(count):
  u=(t/8+j/count)%1;opacity=round((235 if strong else (110 if row==11 else 185))*math.sin(math.pi*u)**1.1)
  side=-1 if j%2==0 else 1;x=(40 if side<0 else 397)+13*math.sin(TAU*u+j);y=(585 if row!=11 else 540)-(180 if row!=11 else 85)*u
  if row in [1,2]:x=55+130*u;x=x if row==1 else 448-x;y=575+10*math.sin(TAU*u+j)
  heart(d,x,y,11 if strong else (5 if row==11 else 7),(*color,opacity))
 if strong or row in [1,2,7]:
  for ribbon in range(2 if strong else 1):
   points=[]
   for i in range(100):
    u=i/99;x=48+350*u;y=540+30*math.sin(TAU*u+t*TAU/8+ribbon*.6)+ribbon*8
    if row in [1,2]:x=34+190*u;y=550+14*math.sin(TAU*u+t*TAU/8);x=x if row==1 else 448-x
    points.append((x*S,y*S))
   d.line(points,fill=(247,114,164,130 if strong else 65),width=2*S,joint='curve')
   d.line([(x,y-S) for x,y in points],fill=(255,222,236,70),width=S)
 if strong:
  points=[]
  for i in range(97):
   a=i*TAU/96;points.append(((180+150*math.sin(a)**3)*S,(510+8*math.sin(t*TAU/8)-65*(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))/16)*S))
  d.line(points,fill=(249,131,181,95),width=2*S,joint='curve')
 if row==11:
  x,y=61,450;d.arc(((x-10)*S,(y-13)*S,(x+10)*S,(y+13)*S),55,290,fill=(243,185,215,100),width=2*S)
 d=ImageDraw.Draw(front)
 for j in range(3 if strong else 2):
  u=(t/8+j/3)%1;x=(34 if j%2==0 else 410)+8*math.sin(TAU*u+j);y=525+48*math.cos(TAU*u+j);a=round((240 if strong else 200)*math.sin(TAU*u)**2)
  if row in [1,2]:x=(55+130*u) if row==1 else (393-130*u);y=602+6*math.sin(TAU*u)
  if row==11:x,y,a=45+20*math.sin(TAU*u),505-30*u,round(a*.65)
  glint(d,x,y,7 if strong else (4 if row==11 else 5),(255,173,207,a))
  glint(d,x,y,1.5,(255,251,254,a))
 output=[]
 for image in [back,front]:
  # Soft glow remains on the independent effect layer, never repaints character sources.
  glow=image.filter(ImageFilter.GaussianBlur(4*S));glow.alpha_composite(image);image=glow.resize((448,640),Image.Resampling.LANCZOS);a=np.array(image);a[:12]=0;a[-12:]=0;a[:,:12]=0;a[:,-12:]=0;a[a[:,:,3]==0,:3]=0;output.append(Image.fromarray(a))
 return output

if __name__=='__main__':
 for item in CONFIG:
  for i in range(80):
   for layer,image in zip(['back','front'],layers(item['row'],i/10)):image.save(ROOT/item['path']/('effect_'+layer)/f'{i:03}.png')
  print(item['id'],'ambient heart/ribbon layers exported',flush=True)
