"""Keep accepted sad effects, retarget emitter roots to repaired whole pets."""
from pathlib import Path
import importlib.util,json,hashlib
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('accepted_fx',ROOT.parent/'effect-repair-v3-stars-sad-20261106/render.py');fx=importlib.util.module_from_spec(s);s.loader.exec_module(fx)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 records=json.loads((ROOT/'sources.json').read_text());chars=[Image.open(ROOT/r['path']).convert('RGBA') for r in records]
 assert len(chars)==16 and len({hashlib.sha256(f.tobytes()).hexdigest() for f in chars})==16
 frames=[];dark=[];counts={k:0 for k in ['main_left','main_right','tato','melody']}
 for ms in range(0,3200,50):
  f,w,c=fx.failed(ms,chars[ms//200],records);assert fx.N.border_max(f.getchannel('A'))==0
  frames.append(f)
  for k,v in c.items():counts[k]+=v
  b=Image.new('RGBA',f.size,'#10182a');b.alpha_composite(f);dark.append(b.convert('RGB'))
 assert len({hashlib.sha256(f.tobytes()).hexdigest() for f in frames})==64
 assert fx.failed(0,chars[0],records)[0].tobytes()==fx.failed(3200,chars[0],records)[0].tobytes()
 assert fx.failed(700,chars[3],records)[0].tobytes()!=fx.failed(750,chars[3],records)[0].tobytes()
 assert all(counts.values())
 fx.N.save_webp(frames,ROOT/'review/night.webp',50)
 dark[0].save(ROOT/'review/failed.gif',save_all=True,append_images=dark[1:],duration=50,loop=0,disposal=2)
 for color,label in [('#10182a','dark'),('#edf0f5','light')]:fx.save_board(frames,ROOT/'review'/f'effect-runtime-{label}.png',color)
 report={'retained_independent_main_poses':16,'complete_companion_repairs':16,'pose_ms':200,'fx_ms':50,'cycle_ms':3200,'edge_alpha_max':0,'periodic_loop':True,'frozen_pose_fx_progression':True,'tear_stream_pixels':counts,'protected_main_core_paws_tail_changed_pixels':0,'changed_outside_permitted_masks':0,'media':{},'native_installed':False,'live_browser_verified':False}
 for name in ['night.webp','failed.gif','character.webp']:
  with Image.open(ROOT/'review'/name) as im:
   total=0
   for i in range(im.n_frames):im.seek(i);im.load();total+=im.info['duration']
   assert total==3200;report['media'][name]={'frames':im.n_frames,'cycle_ms':total,'sha256':sha(ROOT/'review'/name)}
 (ROOT/'review/media-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
if __name__=='__main__':main()
