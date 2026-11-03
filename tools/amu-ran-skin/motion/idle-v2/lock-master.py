"""Lock the static costume anchor to original Retto's body/head proportion.

The skill permits a <=3% uniform correction followed by identity restoration.
This is the one static master repair; motion cells are complete independent art.
"""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter,ImageChops
import runpy,sys,json,hashlib

root=Path(__file__).resolve().parent
sys.argv=['register.py','NO_FRAMES'];registration=runpy.run_path(str(root/'register.py'))
measure=registration['measure'];base=registration['base']

def registered(path):
    src=Image.open(path).convert('RGBA');im=src.copy();im.thumbnail((448,640),Image.Resampling.LANCZOS)
    ox,oy=(448-im.width)//2,(640-im.height)//2
    cell=Image.new('RGBA',(448,640));cell.alpha_composite(im,(ox,oy));m=measure(cell,'master-source')
    s=base['cheek_width']/m['cheek_width'];raw=s*im.width/src.width
    dx=ox*s+base['head_center_x']-s*m['head_center_x'];dy=oy*s+base['foot_baseline']-s*m['foot_baseline']
    return src.transform((448,640),Image.Transform.AFFINE,(1/raw,0,-dx/raw,0,1/raw,-dy/raw),Image.Resampling.BICUBIC)

compact=registered(root/'raw/F00-master-body.png')
m=measure(compact,'compact')
ratio=(base['foot_baseline']-base['eye_line'])/(m['foot_baseline']-m['eye_line'])
assert abs(ratio-1)<=.03,ratio
x=base['head_center_x']*(1-ratio);y=base['foot_baseline']*(1-ratio)
body=compact.transform((448,640),Image.Transform.AFFINE,(1/ratio,0,-x/ratio,0,1/ratio,-y/ratio),Image.Resampling.BICUBIC)
head_y=base['eye_line']-m['eye_line']
head=compact.transform((448,640),Image.Transform.AFFINE,(1,0,0,0,1,-head_y),Image.Resampling.BICUBIC)
mask=Image.new('L',(448,640));draw=ImageDraw.Draw(mask)
draw.rectangle((0,0,447,399),fill=255)
draw.polygon([(48,380),(290,380),(284,414),(245,433),(113,437),(58,415)],fill=255)
mask=mask.filter(ImageFilter.GaussianBlur(2))
result=Image.composite(head,body,mask)
post=measure(result,'locked-master')
ground_shift=base['foot_baseline']-post['foot_baseline']
if ground_shift:
    shifted=Image.new('RGBA',result.size);shifted.paste(result,(0,ground_shift));result=shifted
post=measure(result,'locked-master')
result.save(root/'reference/costume-master.png')
result.save(root/'character/F00.png')
audit={'stage':'static costume master only','whole_body_uniform_correction':ratio,
    'face_restored_at_original_size':True,'head_translation_y':head_y,
    'whole_master_final_translation_y':ground_shift,
    'original_atlas':base,'final_master':post,'motion_cell_patch_policy':'no regional replacements permitted in F01..F15',
    'source_body_and_attached_tail':'raw/F00-master-body.png',
    'separate_tail_graft':False}
(root/'master-registration.json').write_text(json.dumps(audit,indent=2)+'\n')
print(json.dumps(audit,indent=2))
