"""Export the idle review with separate procedural effects; never alter character sources."""
from pathlib import Path
from PIL import Image, ImageDraw
import math, hashlib, json

ROOT = Path(__file__).resolve().parent
TAU = math.tau

def effects(t):
    phase = (t / 8) % 1
    a = phase * TAU
    back = Image.new('RGBA', (224, 320))
    front = Image.new('RGBA', (224, 320))
    bd, fd = ImageDraw.Draw(back), ImageDraw.Draw(front)
    def feather(d, x, y, alpha):
        d.ellipse((x-4, y-7, x+4, y+8), fill=(255,247,234,alpha), outline=(215,197,170,alpha))
        d.line((x,y-5,x,y+8),fill=(203,183,149,alpha))
    for i in range(2):
        q=(phase+i*.47)%1
        feather(bd,36+i*142+math.sin(q*TAU)*4,269-q*36,int((.25+.35*math.sin(q*math.pi))*255))
    x,y=42+math.sin(a)*3,195
    alpha=int((.65+math.sin(a)*.15)*255)
    fd.ellipse((x-9,y-9,x+9,y+9),outline=(234,197,109,alpha),width=1)
    fd.line((x-11,y,x+11,y),fill=(234,197,109,alpha),width=1)
    fd.line((x,y-11,x,y+11),fill=(234,197,109,alpha),width=1)
    offset=math.sin(a)*3
    points=[]
    for j in range(61):
        u=j/60;v=1-u
        px=v**3*45+3*v*v*u*69+3*v*u*u*128+u**3*174
        py=v**3*(255+offset)+3*v*v*u*(273-offset)+3*v*u*u*(266+offset)+u**3*(253-offset)
        points.append((px,py))
    fd.line(points,fill=(198,41,67,204),width=3)
    feather(fd,183+math.sin(a)*4,212+math.cos(a)*10,204)
    def star(x,y,r,opacity):
        fd.polygon([(x,y-r),(x+r*.22,y-r*.22),(x+r,y),(x+r*.22,y+r*.22),(x,y+r),(x-r*.22,y+r*.22),(x-r,y),(x-r*.22,y-r*.22)],fill=(255,227,155,int(opacity*255)))
    star(163,178,3.5,.65+math.sin(a+1)*.2)
    for i in range(3):
        q=(phase+i*.31)%1
        star(48+i*56+math.sin(q*TAU)*4,242-math.sin(q*TAU)*5,1.4+math.sin(q*math.pi),.25+.4*math.sin(q*math.pi))
    return back,front

files=[ROOT/'idle-sky'/f'idle-{i:02d}.png' for i in range(16)]
assert all(f.exists() for f in files)
characters=[]
records=[]
for f in files:
    im=Image.open(f).convert('RGBA');records.append({'file':str(f),'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'decoded':hashlib.sha256(im.tobytes()).hexdigest()})
    im.thumbnail((224,320))
    cell=Image.new('RGBA',(224,320));cell.alpha_composite(im,((224-im.width)//2,(320-im.height)//2));characters.append(cell)
assert len(set(r['decoded'] for r in records))==16
for name,color in [('dark','#181827'),('white','#fffdf8')]:
    frames=[]
    for tick in range(160):
        t=tick*.1;back,front=effects(t)
        cell=Image.new('RGBA',(224,320),color)
        cell=Image.alpha_composite(cell,back)
        cell=Image.alpha_composite(cell,characters[(tick//2)%16])
        cell=Image.alpha_composite(cell,front)
        if tick==0:cell.save(ROOT/f'idle-effects-v2-{name}.png')
        frames.append(cell.convert('RGB'))
    frames[0].save(ROOT/f'idle-effects-v2-{name}.gif',save_all=True,append_images=frames[1:],duration=100,loop=0)
before=effects(.1);after=effects(.9)
assert before[1].tobytes()!=after[1].tobytes()
(ROOT/'idle-sky-validation.json').write_text(json.dumps({'characterSources':records,'drawings':16,'characterCycleSeconds':3.2,'effectCycleSeconds':8,'exportSeconds':16,'effectSamplesPerSecond':10,'fixedPoseEffectsChange':True,'browserValidation':'not run; file URL access blocked','visualStatus':'review candidate; original registration unverified'},indent=2))
print('16 unique corrected cells; character 3.2s; effect 8s; export 16s; frozen-pose effect change passed')
