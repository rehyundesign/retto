"""Approved angel idle gold/feather vocabulary, reused for working ambiance.
Source SHA256: 79c144a54c29a8bf71e4e4768f54eb61388de0feb5b1995950374eb8507ade54
"""
import math
from PIL import Image, ImageDraw, ImageFilter
SIZE = (576, 544)
TAU = math.tau
CYCLE_MS = 2400

def scaled_alpha(im, opacity):
    out = im.copy()
    out.putalpha(out.getchannel('A').point(lambda v: round(v * max(0, min(1, opacity)))))
    return out

def bezier(a, b, c, d, u):
    v = 1 - u
    return (a[0] * v**3 + 3*b[0]*v*v*u + 3*c[0]*v*u*u + d[0]*u**3,
            a[1] * v**3 + 3*b[1]*v*v*u + 3*c[1]*v*u*u + d[1]*u**3)

def back_effects(ms, feather):
    t = ms / CYCLE_MS
    wind = max(0, math.cos(TAU * (2*t - .45))) ** 4
    glow = Image.new('RGBA', SIZE)
    gd = ImageDraw.Draw(glow)
    cx = SIZE[0]/2 + 18 * math.sin(TAU*t)
    cy = 250 + 12 * math.cos(TAU*t)
    gd.ellipse((cx-215, cy-190, cx+215, cy+190), fill=(255, 206, 73, round(25 + 18*wind)))
    gd.ellipse((cx-110, cy-140, cx+110, cy+140), fill=(255, 220, 120, round(20 + 22*wind)))
    layer = glow.filter(ImageFilter.GaussianBlur(36))
    haze = Image.new('RGBA', SIZE)
    hd = ImageDraw.Draw(haze)
    paths = []
    for j in range(3):
        s = math.sin(TAU*t + j*1.6)
        a = (-35, 415 - j*94 + s*9)
        b = (115, 235 - j*41 + s*18)
        c = (365, 405 - j*83 - s*16)
        d = (550, 210 - j*64 + s*12)
        pts = [bezier(a, b, c, d, k/80) for k in range(81)]
        paths.append(pts)
        hd.line(pts, fill=(255, 210, 90, 24 + round(wind*15)), width=12, joint='curve')
    layer.alpha_composite(haze.filter(ImageFilter.GaussianBlur(6)))
    fine = Image.new('RGBA', SIZE)
    fd = ImageDraw.Draw(fine)
    for j, pts in enumerate(paths):
        fd.line(pts, fill=(244, 191, 70, 26 + round(wind*18)), width=1)
    # Sparse warm glints follow the wind curves; no stationary full-screen veil.
    for j in range(13):
        q = (t + j/13) % 1
        u = (q + .02*math.sin(TAU*2*t)) % 1
        x, y = paths[j % 3][min(80, round(u*80))]
        opacity = math.sin(math.pi*q)**2
        radius = 1 + (j % 3)*.35
        fd.ellipse((x-radius, y-radius, x+radius, y+radius),
                   fill=(244, 185, 49, round(125*opacity)))
        if j % 4 == 0:
            fd.line((x-3, y, x+3, y), fill=(251, 206, 106, round(100*opacity)), width=1)
            fd.line((x, y-3, x, y+3), fill=(251, 206, 106, round(100*opacity)), width=1)
    layer.alpha_composite(fine)
    # Independent ambient feather drift inspired by Jeanne's rotating petals/
    # feathers and Hana's sparse layered glints, adapted to ivory and warm gold.
    for j in range(9):
        q = (t + j/9) % 1
        drift = q + .018*math.sin(TAU*2*t - .6)
        x = -35 + drift*612 + 8*math.sin(TAU*q + j)
        y = 40 + (j % 4)*140 + 22*math.sin(TAU*q + j*.7) - 35*q
        opacity = .76 * math.sin(math.pi*q)**2
        size = 20 + (j % 3)*7
        f = feather.copy()
        f.thumbnail((size, size), Image.Resampling.LANCZOS)
        warm = Image.new('RGBA', f.size, (229, 202, 149, 0))
        warm.putalpha(f.getchannel('A'))
        f = Image.blend(f, warm, .22)
        f = f.rotate(-30 + q*85 + 8*math.sin(TAU*t + j), Image.Resampling.BICUBIC, expand=True)
        if j % 3 == 0:
            f = f.filter(ImageFilter.GaussianBlur(.45))
        f = scaled_alpha(f, opacity)
        layer.alpha_composite(f, (round(x-f.width/2), round(y-f.height/2)))
    return layer

def palette(frames):
    sample = Image.new('RGB', (SIZE[0], SIZE[1]*len(frames)))
    for i, f in enumerate(frames):
        sample.paste(f.convert('RGB'), (0, i*SIZE[1]))
    p = sample.quantize(colors=224, method=Image.Quantize.MEDIANCUT)
    values = p.getpalette()[:224*3]
    for i in range(32):
        t = i/31
        values += [round(40+100*t), round(58+111*t), round(68+114*t)]
    p.putpalette(values)
    return p

def save_gif(frames, path, duration):
    p = palette(frames)
    ff = [f.convert('RGB').quantize(palette=p, dither=Image.Dither.FLOYDSTEINBERG) for f in frames]
    ff[0].save(path, save_all=True, append_images=ff[1:], loop=0,
               duration=duration, disposal=2, optimize=False)
