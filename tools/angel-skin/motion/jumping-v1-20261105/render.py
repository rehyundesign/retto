"""Click reaction: articulated low hop, wing lift and a contact-timed gold ring."""
from pathlib import Path
import hashlib
import json
import math
import statistics
from PIL import Image, ImageDraw, ImageFilter
import ambient

ROOT = Path(__file__).resolve().parent
SIZE = (576, 544)
POSE_MS = 150
CYCLE_MS = 2400
SAMPLE_MS = 50


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def wing_emitter(frame, side):
    """Choose an actual ivory wing pixel on the lift drawing, not empty space."""
    xs = range(25, 180) if side == -1 else range(390, 555)
    points = []
    for y in range(65, 330):
        for x in xs:
            r, g, b, a = frame.getpixel((x, y))
            if a > 180 and r > 175 and g > 160 and b > 130 and r >= g >= b+2 and r-g < 45:
                points.append((x, y))
    if len(points) < 20:
        raise ValueError('Lift pose has no visible ivory wing attachment')
    lo, hi = min(x for x, y in points), max(x for x, y in points)
    target = lo+(hi-lo)*(.72 if side == -1 else .28)
    band = [p for p in points if abs(p[0]-target) < 7]
    y = statistics.median(y for x, y in band)
    return min(band, key=lambda p: abs(p[0]-target)+abs(p[1]-y))


def landing_support(frame):
    """Observed contact-frame sole proxy; not original anatomical registration."""
    points = []
    for y in range(435, 520):
        row = []
        for x in range(186, 371):
            r, g, b, a = frame.getpixel((x, y))
            if a > 180 and (r+g+b)/3 < 240:
                row.append(x)
        if len(row) >= 8:
            points.append((y, row))
    if not points:
        raise ValueError('Landing pose has no supported main-paw sole proxy')
    floor = points[-1][0]
    xs = [x for y, row in points if y >= floor-5 for x in row]
    return [(min(xs)+max(xs))/2, floor]


def lift_path(origin, side, q):
    return (origin[0]+side*(90*q+8*math.sin(math.pi*q)),
            origin[1]-65*q-15*math.sin(math.pi*q))


def action_effects(ms, feather, attachments):
    layer = Image.new('RGBA', SIZE)
    haze = Image.new('RGBA', SIZE)
    fine = Image.new('RGBA', SIZE)
    hd, fd = ImageDraw.Draw(haze), ImageDraw.Draw(fine)
    # The particles retain their real birth point on the authored lift pose.
    age = ms-5*POSE_MS
    if 0 <= age < 900:
        q = age/900
        fade = math.sin(math.pi*q)**1.3
        for side in (-1, 1):
            origin = attachments['lift'][str(side)]
            tail = max(0, q-.25)
            pts = [lift_path(origin, side, tail+(q-tail)*k/24) for k in range(25)]
            hd.line(pts, fill=(255, 211, 90, round(70*fade)), width=8, joint='curve')
            fd.line(pts, fill=(246, 192, 65, round(100*fade)), width=1, joint='curve')
            for j in range(4):
                x, y = lift_path(origin, side, max(0, q-j*.03))
                fd.ellipse((x-1.2, y-1.2, x+1.2, y+1.2),
                           fill=(250, 201, 77, round(145*fade*(1-j*.16))))
            x, y = lift_path(origin, side, q)
            f = feather.copy()
            f.thumbnail((27, 27), Image.Resampling.LANCZOS)
            f = f.rotate(side*(-35+100*q), Image.Resampling.BICUBIC, expand=True)
            f = ambient.scaled_alpha(f, .7*fade)
            layer.alpha_composite(f, (round(x-f.width/2), round(y-f.height/2)))
    age = ms-11*POSE_MS
    if 0 <= age < 600:
        q = age/600
        fade = math.sin(math.pi*q)**1.3
        cx, cy = attachments['landing']
        rx, ry = 35+78*q, 4+10*q
        box = (cx-rx, cy-ry+3, cx+rx, cy+ry+3)
        hd.ellipse(box, outline=(255, 211, 95, round(85*fade)), width=7)
        fd.ellipse(box, outline=(246, 194, 68, round(125*fade)), width=1)
        for j in range(7):
            a = math.tau*j/7
            x = cx+rx*math.cos(a)
            y = cy+3+ry*math.sin(a)-8*q
            fd.ellipse((x-1, y-1, x+1, y+1), fill=(250, 207, 91, round(125*fade)))
    layer.alpha_composite(haze.filter(ImageFilter.GaussianBlur(4)))
    layer.alpha_composite(fine)
    return layer


def all_effects(ms, feather, attachments):
    result = ambient.back_effects(ms, feather)
    result.alpha_composite(action_effects(ms, feather, attachments))
    return result


def main():
    records = json.loads((ROOT/'sources.json').read_text())
    assert [r['id'] for r in records] == [f'{i:02}' for i in range(16)]
    frames, before = [], {}
    for r in records:
        p = ROOT/r['path']
        assert sha(p) == r['sha256']
        before[r['id']] = sha(p)
        im = Image.open(p).convert('RGBA')
        assert im.size == SIZE
        frames.append(im)
    attachments = {'lift': {str(s): list(wing_emitter(frames[5], s)) for s in (-1, 1)},
                   'landing': landing_support(frames[11]),
                   'source_poses': {'lift': '05', 'landing': '11'}}
    (ROOT/'review/effect-attachments.json').write_text(json.dumps(attachments, indent=2)+'\n')
    feather = Image.open(ROOT/'effects/feather.png').convert('RGBA')
    white = []
    for f in frames:
        im = Image.new('RGBA', SIZE, 'white')
        im.alpha_composite(f)
        white.append(im)
    ambient.save_gif(white, ROOT/'review/character.gif', POSE_MS)
    playback, effects = [], []
    for ms in range(0, CYCLE_MS, SAMPLE_MS):
        fx = all_effects(ms, feather, attachments)
        im = Image.new('RGBA', SIZE, (255, 251, 244, 255))
        im.alpha_composite(fx)
        im.alpha_composite(frames[ms//POSE_MS])
        playback.append(im.convert('RGB'))
        effects.append(hashlib.sha256(fx.tobytes()).hexdigest())
        if ms in (0, 450, 750, 1050, 1500, 1650, 1800, 2250):
            im.save(ROOT/'review'/f'composite-{ms:04}.png')
    ambient.save_gif(playback, ROOT/'review/jumping.gif', SAMPLE_MS)
    frozen = all_effects(1250, feather, attachments).tobytes() != all_effects(1300, feather, attachments).tobytes()
    assert 1250//POSE_MS == 1300//POSE_MS and frozen
    after = {r['id']: sha(ROOT/r['path']) for r in records}
    assert before == after
    with Image.open(ROOT/'review/jumping.gif') as im:
        duration, count = 0, im.n_frames
        for i in range(count):
            im.seek(i)
            duration += im.info['duration']
    assert count == CYCLE_MS//SAMPLE_MS and duration == CYCLE_MS
    report = {'state': 'jumping', 'character_sources': 16,
              'character_pose_ms': POSE_MS, 'cycle_ms': CYCLE_MS,
              'GIF_frames': count, 'GIF_decoded_ms': duration,
              'effect_sample_ms': SAMPLE_MS, 'unique_effect_samples': len(set(effects)),
              'character_hashes_unchanged_during_effects': before == after,
              'effects_move_with_frozen_character': frozen,
              'whole_character_method': 'independent complete drawings, constant neutral-camera calibration; no head/body assembly, anatomical warp or per-pose regrounding',
              'lift_emission_pose': 5, 'landing_ring_pose': 11,
              'landing_ring_origin': attachments['landing'],
              'played_with_prop': None, 'preview_canvas': list(SIZE),
              'original_anatomical_registration': 'unverified',
              'native_registered': False, 'installed': False}
    (ROOT/'review/technical-checks.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
