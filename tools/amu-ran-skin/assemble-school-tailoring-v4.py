"""Replace the rejected hanging jacket panel with raised-arm tailoring."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import json

root = Path(__file__).resolve().parent
old = Image.open(root/'sleeve-repair-input-v4/A02.png').convert('RGBA')
new = Image.open(root/'anchors/A02-school-tailoring-edit-v4.png').convert('RGBA')
alignment = json.loads((root/'sleeve-alignment-v4.json').read_text())
s = alignment['uniform_scale']; x,y = alignment['translation_2x']
new = new.transform(old.size, Image.Transform.AFFINE,
    (1/s,0,-x/s,0,1/s,-y/s),Image.Resampling.BICUBIC)
mask = Image.new('L',old.size)
ImageDraw.Draw(mask).polygon([(30,438),(94,438),(111,420),(126,428),
    (142,465),(137,492),(129,525),(146,546),(169,552),
    (165,571),(37,558),(27,493)],fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(1))
result = Image.composite(new,old,mask)
diff = ImageChops.difference(old,result)
assert all(not any(pixel) for pixel,allowed in zip(diff.get_flattened_data(),mask.get_flattened_data()) if not allowed)
assert not any(any(pixel) for pixel in diff.crop((45,190,296,416)).get_flattened_data())
mask.save(root/'A02-sleeve-edit-mask-v4.png')
result.save(root/'anchors/A02-school-tailoring-locked-v4.png')
print('Applied new shoulder, side and lifted diagonal hem; pixels outside local tailoring mask unchanged.')
