"""Completion greeting: independent trio drawings over continuous warm light/feathers."""
from pathlib import Path
import hashlib
import json
import math
from PIL import Image, ImageDraw, ImageFilter
import ambient

ROOT = Path(__file__).resolve().parent
SIZE = (576, 544)
POSE_MS = 150
CYCLE_MS = 2400
SAMPLE_MS = 50


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def completion_sweep(ms):
    """A gold crescent sweeps behind the upper trio during the greeting.

    Background moonlight motif; not a point emitter attached to the paw.
    It begins after the lift and fades before the four-footed return.
    """
    result = Image.new('RGBA', SIZE)
    age = ms-450
    if not 0 <= age < 1500:
        return result
    q = age/1500
    envelope = math.sin(math.pi*q)**1.25
    haze = Image.new('RGBA', SIZE)
    fine = Image.new('RGBA', SIZE)
    hd, fd = ImageDraw.Draw(haze), ImageDraw.Draw(fine)
    theta = math.radians(200+140*q)
    length = math.radians(10+23*math.sin(math.pi*q))
    def point(a):
        return (SIZE[0]/2+225*math.cos(a), 245+190*math.sin(a))
    pts = [point(theta-length+length*i/44) for i in range(45)]
    hd.line(pts, fill=(255, 215, 101, round(82*envelope)),
            width=12, joint='curve')
    fd.line(pts, fill=(248, 198, 77, round(130*envelope)),
            width=1, joint='curve')
    for j in range(7):
        x, y = point(theta-length*j/7)
        a = round(150*envelope*(1-j*.11))
        fd.ellipse((x-1.2, y-1.2, x+1.2, y+1.2),
                   fill=(251, 207, 93, a))
        if j % 3 == 0:
            fd.line((x-3, y, x+3, y), fill=(255, 224, 146, a))
            fd.line((x, y-3, x, y+3), fill=(255, 224, 146, a))
    result.alpha_composite(haze.filter(ImageFilter.GaussianBlur(5)))
    result.alpha_composite(fine)
    return result


def all_effects(ms, feather):
    result = ambient.back_effects(ms, feather)
    result.alpha_composite(completion_sweep(ms))
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
    feather = Image.open(ROOT/'effects/feather.png').convert('RGBA')
    white = []
    for f in frames:
        im = Image.new('RGBA', SIZE, 'white')
        im.alpha_composite(f)
        white.append(im)
    ambient.save_gif(white, ROOT/'review/character.gif', POSE_MS)
    playback, effects = [], []
    for ms in range(0, CYCLE_MS, SAMPLE_MS):
        fx = all_effects(ms, feather)
        im = Image.new('RGBA', SIZE, (255, 251, 244, 255))
        im.alpha_composite(fx)
        im.alpha_composite(frames[ms//POSE_MS])
        playback.append(im.convert('RGB'))
        effects.append(hashlib.sha256(fx.tobytes()).hexdigest())
        if ms % 400 == 0:
            im.save(ROOT/'review'/f'composite-{ms:04}.png')
    ambient.save_gif(playback, ROOT/'review/waving.gif', SAMPLE_MS)
    frozen = all_effects(1250, feather).tobytes() != all_effects(1300, feather).tobytes()
    assert 1250//POSE_MS == 1300//POSE_MS and frozen
    after = {r['id']: sha(ROOT/r['path']) for r in records}
    assert before == after
    with Image.open(ROOT/'review/waving.gif') as im:
        duration, count = 0, im.n_frames
        for i in range(count):
            im.seek(i)
            duration += im.info['duration']
    assert count == CYCLE_MS//SAMPLE_MS and duration == CYCLE_MS
    report = {'state': 'waving', 'character_sources': 16,
              'character_pose_ms': POSE_MS, 'cycle_ms': CYCLE_MS,
              'GIF_frames': count, 'GIF_decoded_ms': duration,
              'effect_sample_ms': SAMPLE_MS,
              'unique_effect_samples': len(set(effects)),
              'character_hashes_unchanged_during_effects': before == after,
              'effects_move_with_frozen_character': frozen,
              'whole_character_method': 'independent complete drawings; no head/body assembly or anatomical warps',
              'completion_sweep_onset_ms': 450,
              'illumination_layer': 'gold crescent behind trio, not an attached emitter',
              'played_with_prop': None, 'preview_canvas': list(SIZE),
              'original_anatomical_registration': 'unverified',
              'native_registered': False, 'installed': False}
    (ROOT/'review/technical-checks.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
