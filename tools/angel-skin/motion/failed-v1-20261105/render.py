"""Failure reassurance: independent trio drawings over continuous warm light/feathers."""
from pathlib import Path
import hashlib
import json
import math
from PIL import Image, ImageDraw, ImageFilter
import ambient

ROOT = Path(__file__).resolve().parent
SIZE = (576, 544)
POSE_MS = 200
CYCLE_MS = 3200
SAMPLE_MS = 50


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def recovery_light(ms):
    """A background wash rises as Retto lifts its head after reassurance.

    Illumination is behind the trio; it is not a claimed attached contact
    emitter. The envelope finishes before the neutral loop bridge.
    """
    result = Image.new('RGBA', SIZE)
    age = ms - 1200
    if not 0 <= age < 1600:
        return result
    q = age/1600
    fade = math.sin(math.pi*q)**1.5
    haze = Image.new('RGBA', SIZE)
    hd = ImageDraw.Draw(haze)
    cx, cy = SIZE[0]/2, 405-145*q
    hd.ellipse((cx-170, cy-90, cx+170, cy+90),
               fill=(255, 217, 110, round(35*fade)))
    hd.ellipse((cx-90, cy-125, cx+90, cy+125),
               fill=(255, 229, 153, round(24*fade)))
    result.alpha_composite(haze.filter(ImageFilter.GaussianBlur(27)))
    fine = Image.new('RGBA', SIZE)
    dd = ImageDraw.Draw(fine)
    # Matching side glints rise together around both comforting companions.
    for side in (-1, 1):
        for j in range(5):
            x = cx+side*(119+14*j+12*math.sin(math.pi*q+j*.5))
            y = 478-190*q-j*24
            opacity = round((78-j*8)*fade)
            dd.ellipse((x-1, y-1, x+1, y+1),
                       fill=(246, 194, 71, opacity))
            if j % 2 == 0:
                dd.line((x-3, y, x+3, y), fill=(255, 217, 125, opacity))
                dd.line((x, y-3, x, y+3), fill=(255, 217, 125, opacity))
    result.alpha_composite(fine)
    return result


def all_effects(ms, feather):
    result = ambient.back_effects(ms, feather)
    result.alpha_composite(recovery_light(ms))
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
    ambient.save_gif(playback, ROOT/'review/failed.gif', SAMPLE_MS)
    frozen = all_effects(1250, feather).tobytes() != all_effects(1300, feather).tobytes()
    assert 1250//POSE_MS == 1300//POSE_MS and frozen
    after = {r['id']: sha(ROOT/r['path']) for r in records}
    assert before == after
    with Image.open(ROOT/'review/failed.gif') as im:
        duration, count = 0, im.n_frames
        for i in range(count):
            im.seek(i)
            duration += im.info['duration']
    assert count == CYCLE_MS//SAMPLE_MS and duration == CYCLE_MS
    report = {'state': 'failed', 'character_sources': 16,
              'character_pose_ms': POSE_MS, 'cycle_ms': CYCLE_MS,
              'GIF_frames': count, 'GIF_decoded_ms': duration,
              'effect_sample_ms': SAMPLE_MS,
              'unique_effect_samples': len(set(effects)),
              'character_hashes_unchanged_during_effects': before == after,
              'effects_move_with_frozen_character': frozen,
              'whole_character_method': 'independent complete drawings; no head/body assembly or anatomical warps',
              'recovery_illumination_onset_ms': 1200,
              'illumination_layer': 'rising background wash and paired glints, not an attached emitter',
              'played_with_prop': None, 'preview_canvas': list(SIZE),
              'original_anatomical_registration': 'unverified',
              'native_registered': False, 'installed': False}
    (ROOT/'review/technical-checks.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
