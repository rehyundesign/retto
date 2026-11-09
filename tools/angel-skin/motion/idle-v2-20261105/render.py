"""Render locked character poses with independent golden light/feather clocks."""
from pathlib import Path
import hashlib
import json
import math
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
SIZE = (544, 544)
POSE_MS = 200
CYCLE_MS = 3200
SAMPLE_MS = 50
TAU = math.tau
STAR_KEYS = [
    (330, 970), (325, 990), (320, 1015), (310, 1040),
    (280, 1045), (255, 940), (210, 1070), (220, 1120),
    (270, 1060), (500, 1030), (735, 1060), (710, 1055),
    (705, 1005), (875, 900), (950, 820), (990, 760),
]


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def prop_asset():
    ready = ROOT / 'effects/star.png'
    if ready.exists():
        return Image.open(ready).convert('RGBA')
    im = Image.open(ROOT / 'effects/star-raw.png').convert('RGBA')
    ImageDraw.floodfill(im, (0, 0), (0, 0, 0, 0), thresh=7)
    box = im.getchannel('A').getbbox()
    if not box:
        raise ValueError('Blank star prop')
    im = im.crop(box)
    im.thumbnail((36, 36), Image.Resampling.LANCZOS)
    im.save(ready)
    return im


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
    cx = 272 + 18 * math.sin(TAU*t)
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


def star_effect(ms, star, records):
    phase = ms / POSE_MS
    i = min(15, int(phase)); u = phase-i
    a = STAR_KEYS[i]; b = STAR_KEYS[min(15, i+1)]
    dy_a = records[i]['character_only_translation_raw'][1]
    dy_b = records[min(15, i+1)]['character_only_translation_raw'][1]
    x = (a[0] + (b[0]-a[0])*u)/2 + 16
    y = (a[1] + (b[1]-a[1])*u + dy_a + (dy_b-dy_a)*u - 320)/2
    opacity = min(1, ms/150, max(0, (CYCLE_MS-ms)/450))
    out = Image.new('RGBA', SIZE)
    halo = Image.new('RGBA', SIZE)
    hd = ImageDraw.Draw(halo)
    hd.ellipse((x-25, y-25, x+25, y+25), fill=(255, 205, 55, round(68*opacity)))
    out.alpha_composite(halo.filter(ImageFilter.GaussianBlur(9)))
    prop = star.rotate(12*math.sin(TAU*ms/CYCLE_MS), Image.Resampling.BICUBIC, expand=True)
    prop = scaled_alpha(prop, opacity)
    out.alpha_composite(prop, (round(x-prop.width/2), round(y-prop.height/2)))
    # A small glint only at the actual handoff beats, centred on the current prop.
    contact = max(math.exp(-((ms-beat)/90)**2) for beat in (800, 1400, 2200))
    if contact > .05:
        d = ImageDraw.Draw(out)
        for angle in (0, math.pi/2):
            dx, dy = math.cos(angle)*5, math.sin(angle)*5
            d.line((x+20-dx, y-15-dy, x+20+dx, y-15+dy),
                   fill=(255, 218, 120, round(190*contact*opacity)), width=1)
    return out


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


def main():
    records = json.loads((ROOT/'sources.json').read_text())
    assert [r['id'] for r in records] == [f'{i:02}' for i in range(16)]
    frames = []
    for record in records:
        p = ROOT/record['path']
        assert sha(p) == record['sha256'], 'Character changed after source lock'
        frames.append(Image.open(p).convert('RGBA'))
    before = {r['id']: sha(ROOT/r['path']) for r in records}
    star = prop_asset()
    feather = Image.open(ROOT/'effects/feather.png').convert('RGBA')
    review = ROOT/'review'
    white = []
    for frame in frames:
        bg = Image.new('RGBA', SIZE, 'white'); bg.alpha_composite(frame); white.append(bg)
    save_gif(white, review/'character.gif', POSE_MS)
    playback = []
    effect_hashes = []
    for ms in range(0, CYCLE_MS, SAMPLE_MS):
        back = back_effects(ms, feather)
        front = star_effect(ms, star, records)
        image = Image.new('RGBA', SIZE, (255, 251, 244, 255))
        image.alpha_composite(back)
        image.alpha_composite(frames[ms//POSE_MS])
        image.alpha_composite(front)
        playback.append(image.convert('RGB'))
        effect_hashes.append(hashlib.sha256(back.tobytes()+front.tobytes()).hexdigest())
        if ms % 400 == 0:
            image.save(review/f'composite-{ms:04}.png')
    save_gif(playback, review/'idle.gif', SAMPLE_MS)
    # Verify that effects advance while one character pose is held.
    a = back_effects(0, feather); b = back_effects(100, feather)
    frozen_effect_moves = a.tobytes() != b.tobytes()
    after = {r['id']: sha(ROOT/r['path']) for r in records}
    assert before == after and frozen_effect_moves
    decoded_ms = 0
    with Image.open(review/'idle.gif') as im:
        n = im.n_frames
        for i in range(n):
            im.seek(i); decoded_ms += im.info['duration']
    assert decoded_ms == CYCLE_MS
    report = {'independent_character_sources': 16, 'character_pose_ms': POSE_MS,
              'cycle_ms': CYCLE_MS, 'GIF_decoded_ms': decoded_ms, 'GIF_frames': n,
              'effect_sample_ms': SAMPLE_MS, 'unique_effect_samples': len(set(effect_hashes)),
              'character_hashes_unchanged_during_effects': before == after,
              'effects_move_with_frozen_character': frozen_effect_moves,
              'played_with_object': 'yellow five-point star, no played-with feather',
              'background_effects': 'warm yellow glow/wind wisps/glints and9 drifting ivory feathers',
              'wingbeat_cycles_per_loop': 2, 'wing_method': 'independent image_gen costume redraws; no rigid fan rotation/warping',
              'preview_canvas': list(SIZE), 'native_registered': False, 'installed': False}
    (review/'technical-checks.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
