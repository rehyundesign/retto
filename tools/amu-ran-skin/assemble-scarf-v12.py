"""Keep approved Retto pixels outside the requested scarf/egg attachment zone."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter,ImageChops
import hashlib,json
r=Path(__file__).resolve().parent
base_path=r/'anchors/idle-heart-cape-pose-v9-source.png'
edit_path=r/'anchors/idle-heart-scarf-v12-edit-source.png'
base=Image.open(base_path).convert('RGBA'); edit=Image.open(edit_path).convert('RGBA')
if base.size!=edit.size:
 raise ValueError('Local edit canvas changed; regenerate without moving or resizing character')
polygon=[(330,750),(700,750),(700,915),(590,930),(575,985),(405,985),(395,925),(330,910)]
hard=Image.new('L',base.size); ImageDraw.Draw(hard).polygon(polygon,fill=255)
# The feather is constrained INSIDE the declared region, keeping locked pixels exact.
mask=ImageChops.multiply(hard,hard.filter(ImageFilter.GaussianBlur(3)))
final=Image.composite(edit,base,mask)
final.save(r/'anchors/idle-heart-scarf-v12-character.png')
mask.save(r/'scarf-v12-edit-mask.png')
outside=0; inside=0
for a,b,m in zip(base.get_flattened_data(),final.get_flattened_data(),hard.get_flattened_data()):
 if a!=b:
  if m:inside+=1
  else:outside+=1
assert outside==0 and inside>0
face=(0,0,base.width,748)
assert ImageChops.difference(base.crop(face),final.crop(face)).getbbox() is None
report={'base':'anchors/idle-heart-cape-pose-v9-source.png','edit':'anchors/idle-heart-scarf-v12-edit-source.png','output':'anchors/idle-heart-scarf-v12-character.png','allowed_polygon':polygon,'mask':'scarf-v12-edit-mask.png','canvas':list(base.size),'changed_outside_requested_zone':outside,'changed_inside_requested_zone':inside,'protected_face_region':list(face),'protected_face_changed':False,'base_sha256':hashlib.sha256(base_path.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256((r/'anchors/idle-heart-scarf-v12-character.png').read_bytes()).hexdigest(),'review':'center red scarf knot, egg connected to knot, no separate pink necklace cord; approved art restored outside local zone','production_ready':False,'installed':False}
(r/'scarf-v12-scope-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(f'Local scarf assembly: {inside} changed pixels inside zone, {outside} outside; face preserved')
