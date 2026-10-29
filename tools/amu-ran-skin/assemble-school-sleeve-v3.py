"""Apply regenerated tailoring only; retain the approved face and body pixels."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import json

root = Path(__file__).resolve().parent
old = Image.open(root/'sleeve-repair-input-v3/A02.png').convert('RGBA')
new = Image.open(root/'anchors/A02-school-sleeve-edit-v3.png').convert('RGBA')
alignment = json.loads((root/'sleeve-alignment-v3.json').read_text())
s = alignment['uniform_scale']; x,y = alignment['translation_2x']
new = new.transform(old.size, Image.Transform.AFFINE,
    (1/s,0,-x/s,0,1/s,-y/s),Image.Resampling.BICUBIC)
# Tailoring from shoulder through bent sleeve; remove the misplaced skirt flap.
# The raised paw and entire head remain outside this clothing coverage region.
mask = Image.new('L',old.size)
ImageDraw.Draw(mask).polygon([(30,438),(94,438),(111,420),(126,428),
    (144,455),(148,488),(129,550),(42,546),(27,493)], fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(1))
result = Image.composite(new,old,mask)
diff = ImageChops.difference(old,result)
assert all(not any(pixel) for pixel,allowed in zip(diff.get_flattened_data(),mask.get_flattened_data()) if not allowed)
assert not any(any(pixel) for pixel in diff.crop((45,190,296,416)).get_flattened_data())
mask.save(root/'A02-sleeve-edit-mask-v3.png')
result.save(root/'anchors/A02-school-sleeve-locked-v3.png')
print('PASS: regenerated sleeve integrated; head, raised paw and all pixels outside tailoring mask preserved.')
