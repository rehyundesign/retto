"""Use independently redrawn short bodies; preserve approved head/cape hardware.

Hana reference: master/independent character registration first, companion later.
Never stretch a face or a limb to repair an outfit's stature.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import json, hashlib, statistics

root = Path(__file__).resolve().parent
old = json.loads((root/'heart-size-input-v2/static-size-registration-v1.json').read_text())
old = {r['id']: r for r in old['records']}
settings = {
    'A06': {'eye':167, 'center':92, 'shift':80, 'cut':348,
            'cape':[(39,340),(304,340),(315,398),(280,428),(247,449),(175,466),(116,449),(68,431),(29,398)]},
    'A07': {'eye':171, 'center':94, 'shift':55, 'cut':386,
            'cape':[(37,374),(302,374),(311,427),(273,460),(233,480),(174,493),(112,479),(68,460),(30,422)]},
    'A14': {'eye':154, 'center':96, 'shift':70, 'cut':364,
            'cape':[(39,353),(295,353),(308,409),(268,441),(225,457),(174,468),(122,453),(68,432),(32,397)],
            'paw':[(34,299),(107,299),(137,358),(145,405),(117,438),(60,432),(32,377)]},
    'A15': {'eye':124, 'center':103, 'shift':131, 'cut':256,
            'cape':[(27,245),(310,245),(314,296),(280,329),(232,348),(173,358),(107,342),(52,322),(22,284)],
            'paw':[(43,279),(140,281),(150,330),(198,318),(264,328),(264,373),(199,380),(126,362),(47,339)]}
}
audit = []
for name,spec in settings.items():
    frozen_path = root/'heart-size-input-v2'/f'{name}.png'
    frozen = Image.open(frozen_path).convert('RGBA')
    assert hashlib.sha256(frozen_path.read_bytes()).hexdigest() == old[name]['output_sha256']
    raw_path = root/'anchors'/f'{name}-heart-compact-edit-{"v3" if name=="A15" else "v2"}.png'
    raw = Image.open(raw_path).convert('RGBA')
    raw.thumbnail((448,640),Image.Resampling.LANCZOS)
    body = Image.new('RGBA',(448,640))
    body.alpha_composite(raw,((448-raw.width)//2,(640-raw.height)//2))
    pixels = body.load()
    widths = []
    for y in range((spec['eye']+8)*2,(spec['eye']+23)*2):
        xs = [x for x in range(max(0,(spec['center']-70)*2),min(448,(spec['center']+70)*2))
              if (lambda c:c[3]>64 and c[0]>=c[1]>=c[2]+2 and c[0]-c[1]<65 and c[1]-c[2]<70)(pixels[x,y])]
        if len(xs)>35: widths.append(xs[-1]-xs[0]+1)
    scale = 228/statistics.median(widths)
    bounds = body.getchannel('A').crop((110,440,300,640)).point(lambda a:255 if a>96 else 0).getbbox()
    old_foot = 440+bounds[3]-1
    target_foot = 596 if name=='A15' else 628
    tx,ty = 174-spec['center']*2*scale,target_foot-old_foot*scale
    body = body.transform((448,640),Image.Transform.AFFINE,
             (1/scale,0,-tx/scale,0,1/scale,-ty/scale),Image.Resampling.BICUBIC)
    # The redrawn head/visor are replaced completely, including their fringe.
    # Hips, tail and supporting legs start below this replacement region.
    ImageDraw.Draw(body).rectangle((0,0,447,spec['cut']+spec['shift']+12),fill=(0,0,0,0))
    # Restore head, visor, cape, centered scarf/egg and the existing lifted paw
    # from the locked independent source; new hips/legs/tail remain below.
    source_mask = Image.new('L',(448,640))
    draw = ImageDraw.Draw(source_mask)
    draw.rectangle((0,0,447,spec['cut']),fill=255)
    draw.polygon(spec['cape'],fill=255)
    if 'paw' in spec: draw.polygon(spec['paw'],fill=255)
    source_mask = source_mask.filter(ImageFilter.GaussianBlur(2))
    mask = Image.new('L',(448,640)); mask.paste(source_mask,(0,spec['shift']))
    shifted = Image.new('RGBA',(448,640)); shifted.paste(frozen,(0,spec['shift']))
    result = Image.composite(shifted,body,mask)
    difference = ImageChops.difference(shifted,result)
    changed = sum(any(pixel) and keep==255 for pixel,keep in
                  zip(difference.get_flattened_data(),mask.get_flattened_data()))
    assert changed==0
    output = root/'anchors'/f'{name}-heart-compact-locked-v2.png'
    result.save(output)
    audit.append({'id':name,'independent_body_source':str(raw_path.relative_to(root)),
        'frozen_source':str(frozen_path.relative_to(root)),
        'head_and_costume_translation_2x':[0,spec['shift']],
        'changed_protected_head_cape_scarf_egg_pixels':changed,
        'body_uniform_scale':scale,'body_translation_2x':[tx,ty],
        'output':str(output.relative_to(root))})
(root/'heart-body-lock-audit-v2.json').write_text(json.dumps(audit,indent=2)+'\n')
print('4 compact transformed bodies assembled; approved head, cape, scarf and egg pixels preserved in protected regions.')
