"""Final gaze path: built-in image edits isolate natural complete heads.
Only uniform head registration onto a fixed master body is applied here.
No diagonal/elliptical face trims, face repainting, or animation grafts.
"""
from pathlib import Path
from PIL import Image,ImageDraw
import numpy as np
import json,hashlib,sys,math
root=Path(__file__).resolve().parent;yy,xx=np.indices((640,448))
def contained(path):
 im=Image.open(path).convert('RGBA');im.thumbnail((448,640),Image.Resampling.LANCZOS);c=Image.new('RGBA',(448,640));c.alpha_composite(im,((448-im.width)//2,(640-im.height)//2));return c
def fur(a):
 r,g,b=[a[:,:,i].astype(float) for i in range(3)]
 return (g-b>5)&(r-g>-3)&(r-g<65)&(g>120)&(r>145)&(a[:,:,3]>80)
for costume in (sys.argv[1:] or ['school','heart']):
 r=root/f'gaze-{costume}-v1';heads=root/f'gaze-{costume}-head-v1';master=root/'idle-v2/reference/costume-master.png' if costume=='school' else root.parent/'registered-static-v2/A06.png'
 previous=json.loads((r/'registration.json').read_text());target_neck=previous[0].get('target_neck_y',previous[0]['fixed_body_from_y']-2)
 basear=np.array(contained(master));basear[basear[:,:,3]==0,:3]=0;body=basear.copy()
 rr,gg,bb=[basear[:,:,i].astype(float) for i in range(3)]
 # Preserve the real garment contour above the old neck, instead of slicing a band.
 # Wardrobe material is neutral/cool/red; the original head fur is warm cream/brown.
 garment=((bb-gg>=-2)|((rr<110)&(gg<110)&(bb<110)))&(basear[:,:,3]>8)&(yy>=390)&(yy<469)
 garment[(yy<418)&(xx>95)&(xx<255)]=False
 connected=np.zeros((640,448),bool);stack=[(468,int(x)) for x in np.flatnonzero(garment[468])]
 for py,px in stack:connected[py,px]=True
 while stack:
  py,px=stack.pop()
  for ny,nx in [(py-1,px),(py+1,px),(py,px-1),(py,px+1),(py-1,px-1),(py-1,px+1),(py+1,px-1),(py+1,px+1)]:
   if 390<=ny<469 and 0<=nx<448 and garment[ny,nx] and not connected[ny,nx]:connected[ny,nx]=True;stack.append((ny,nx))
 neck_bridge=fur(basear)&(yy>=418)&(yy<target_neck+4)&(xx>124)&(xx<221)
 body[(yy<469)&~connected&~neck_bridge]=0
 collar_front=basear.copy();collar_front[~connected|(yy<target_neck)]=0
 records=[]
 for i in range(16):
  p=heads/'raw'/f'G{i:02}.png';c=contained(p);a=np.array(c);fy,fx=np.nonzero(fur(a));sourcebox=(int(fx.min()),int(fy.min()),int(fx.max()+1),int(fy.max()+1))
  original=contained(root.parent/'gaze/reference'/f'base-{i:02}.png');of=fur(np.array(original))&(yy<430)&(yy>150);oy,ox=np.nonzero(of)
  original_direction_width=int(ox.max()-ox.min()+1)
  # Original gaze cells use a taller seated body. This fixed compact-body group
  # keeps the approved neutral head volume, with modest true-profile foreshortening.
  target_width=228-23*abs(math.sin(i*math.tau/16))
  source_width=sourcebox[2]-sourcebox[0];s=target_width/source_width
  target_cx=float((ox.min()+ox.max())/2);source_cx=(sourcebox[0]+sourcebox[2]-1)/2;dx=target_cx-source_cx*s
  # Pale fur tips can be almost white; use the actual isolated outline for neck height.
  outline=c.getchannel('A').point(lambda v:255 if v>16 else 0).getbbox()
  # Discard detached almost-transparent matting specks outside the visible outline.
  a[(yy>outline[3]+3)|(yy<outline[1]-3)|(xx<outline[0]-3)|(xx>outline[2]+3)]=0
  c=Image.fromarray(a)
  dy=target_neck+12-(outline[3]-1)*s  # natural fur tucks behind the front collar/scarf
  head=c.transform((448,640),Image.Transform.AFFINE,(1/s,0,-dx/s,0,1/s,-dy/s),Image.Resampling.BICUBIC)
  out=Image.fromarray(body.copy());out.alpha_composite(head);out.alpha_composite(Image.fromarray(collar_front));ar=np.array(out);ar[ar[:,:,3]==0,:3]=0;out=Image.fromarray(ar);out.save(r/'character'/f'G{i:02}.png')
  # The natural isolated head can overlap the collar by a few fur-tip pixels.
  safe_y=max(target_neck+8,head.getchannel('A').getbbox()[3])
  assert safe_y<=target_neck+20, (costume,i,'unexpected garment/body in isolated head')
  assert np.array_equal(ar[469:],basear[469:])
  records.append({'id':f'G{i:02}','full_pose_source':str(r/'raw'/f'G{i:02}.png'),'head_cutout_source':str(p),'head_source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'body_master':str(master),'head_fur_source_box':sourcebox,'original_direction_fur_width':original_direction_width,'canonical_compact_stance_fur_width':target_width,'uniform_head_scale':s,'translation':[dx,dy],'fixed_body_from_y':469,'target_neck_y':target_neck,'natural_outline_preserved':True,'regional_face_trims':False,'gaze_head_neck_only_exception':True,'animated_frame':False,'visual_review':'pending'})
 (r/'registration.json').write_text(json.dumps(records,indent=2)+'\n')
 for theme,bg in [('light','#fffdfa'),('dark','#23232d')]:
  board=Image.new('RGB',(960,1408),bg);d=ImageDraw.Draw(board)
  for i in range(16):
   im=Image.open(r/'character'/f'G{i:02}.png').resize((224,320),Image.Resampling.LANCZOS);x,y=i%4*240,i//4*352;board.paste(im,(x+8,y+25),im);d.text((x+8,y+6),f'G{i:02}',fill='gray')
  board.save(r/f'directions-{theme}-1x.png')
 print(costume,'16 naturally isolated heads, fixed lower body')
