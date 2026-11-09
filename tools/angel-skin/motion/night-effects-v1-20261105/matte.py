"""Same-pose white-background matte extraction; no pose or RGB edits."""
from PIL import Image, ImageDraw, ImageChops, ImageFilter

def significant_components(mask):
    width, height = mask.size
    bits = bytearray(mask.point(lambda v: 1 if v else 0).tobytes())
    keep = Image.new('L', mask.size)
    d = ImageDraw.Draw(keep)
    for seed in range(len(bits)):
        if not bits[seed]:
            continue
        bits[seed] = 0
        todo = [seed]
        component = []
        while todo:
            pos = todo.pop()
            component.append(pos)
            x, y = (pos % width, pos // width)
            for nxt in (pos - 1 if x else -1, pos + 1 if x + 1 < width else -1, pos - width if y else -1, pos + width if y + 1 < height else -1):
                if nxt >= 0 and bits[nxt]:
                    bits[nxt] = 0
                    todo.append(nxt)
        if len(component) >= 80:
            for pos in component:
                d.point((pos % width, pos // width), fill=255)
    return keep

def cutout(im):
    delta = ImageChops.difference(im, Image.new('RGB', im.size, 'white')).convert('L')
    strong = significant_components(delta.point(lambda v: 255 if v > 2 else 0))
    outside = strong.copy()
    ImageDraw.floodfill(outside, (0, 0), 128, thresh=0)
    solid = ImageChops.lighter(strong, outside.point(lambda v: 255 if v == 0 else 0))
    support = solid.filter(ImageFilter.MaxFilter(7))
    edge = ImageChops.multiply(delta.point(lambda v: min(255, v * 32)), support)
    alpha = ImageChops.lighter(solid.filter(ImageFilter.MinFilter(3)), edge)
    alpha = ImageChops.darker(alpha, alpha.filter(ImageFilter.GaussianBlur(0.35)))
    result = im.convert('RGBA')
    result.putalpha(alpha)
    return result
