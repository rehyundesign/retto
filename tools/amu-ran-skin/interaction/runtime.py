"""One companion response contract for PNG exports; JS/Swift consume the same JSON."""
from pathlib import Path
import json,math
from functools import lru_cache
from PIL import Image
ROOT=Path(__file__).resolve().parent.parent
PLAN=json.loads((Path(__file__).with_name('plan.json')).read_text())

def sample(row,pose_time,effect_time,gaze_direction=None,held=False):
 track=PLAN['rows'][str(row)];side=track['side']
 if gaze_direction is not None:
  side='right';x,y=(315,365 if row==3 else 350);pose=int(max(0,effect_time)/.8)%2
 else:
  phase=0 if held else (max(0,pose_time)/track['cycle']*16)%16
  if abs(phase-round(phase))<1e-7:phase=round(phase)%16
  i=int(math.floor(phase));u=phase-math.floor(phase);a=track['frames'][i];b=track['frames'][(i+1)%16];u=u*u*(3-2*u)
  x=a['x']+(b['x']-a['x'])*u;y=a['y']+(b['y']-a['y'])*u;pose=a['pose']
  if held:pose=int(max(0,effect_time)/.8)%2
 amount=.4 if side=='sleep' else (.35 if pose==3 else 1.1)
 y+=amount*math.sin(max(0,effect_time)*math.tau/(6.4 if side=='sleep' else 1.6))
 return side,pose,math.floor(x+.5),math.floor(y+.5)

@lru_cache(maxsize=24)
def sprite(side,pose):
 path=(ROOT/'motion/sleeping-v1/companion'/f'R{pose:02}.png' if side=='sleep' else ROOT/'motion'/f'ran-interaction-{side}-v1/character'/f'R{pose:02}.png')
 return Image.open(path).convert('RGBA')

def draw(canvas,row,pose_time,effect_time,gaze_direction=None,held=False):
 side,pose,x,y=sample(row,pose_time,effect_time,gaze_direction,held)
 canvas.alpha_composite(sprite(side,pose),(x,y))
 return canvas
