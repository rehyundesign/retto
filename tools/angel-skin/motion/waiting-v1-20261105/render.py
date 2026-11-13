"""Input waiting: independent trio drawings over continuous warm light/feathers."""
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


def invitation_light(ms):
    """A restrained background aura opens with the shared invitation.

    This is illumination behind the trio, not a particle emitter attached to
    a bell, paw, or wing. No unmeasured fixed point is presented as an attachment.
    Each envelope finishes before the neutral return so it has no seam reset.
    """
    haze = Image.new('RGBA', SIZE)
    detail = Image.new('RGBA', SIZE)
    hd, dd = ImageDraw.Draw(haze), ImageDraw.Draw(detail)
    for birth, life, strength in ((800, 1100, 1.0), (1800, 1000, .65)):
        age = ms-birth
        if not 0 <= age < life:
            continue
        q = age/life
        fade = math.sin(math.pi*q)**2*strength
        # Paired equal illumination gives both companions the same emphasis.
        for side in (-1, 1):
            cx, cy = SIZE[0]/2 + side*(178+10*q), 366-35*q
            rx, ry = 36+16*q, 50+18*q
            hd.ellipse((cx-rx, cy-ry, cx+rx, cy+ry),
                       fill=(255, 215, 107, round(27*fade)))
            for j in range(3):
                angle = -math.pi/2 + side*(.8+j*.5)
                x = cx+math.cos(angle)*(30+24*q)
                y = cy+math.sin(angle)*(44+26*q)
                a = round(108*fade*(1-j*.16))
                dd.line((x-2, y, x+2, y), fill=(244, 193, 67, a))
                dd.line((x, y-2, x, y+2), fill=(244, 193, 67, a))
    result = haze.filter(ImageFilter.GaussianBlur(13))
    result.alpha_composite(detail)
    return result


def all_effects(ms, feather):
    result = ambient.back_effects(ms, feather)
    result.alpha_composite(invitation_light(ms))
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
    ambient.save_gif(playback, ROOT/'review/waiting.gif', SAMPLE_MS)
    frozen = all_effects(1250, feather).tobytes() != all_effects(1300, feather).tobytes()
    assert 1250//POSE_MS == 1300//POSE_MS and frozen
    after = {r['id']: sha(ROOT/r['path']) for r in records}
    assert before == after
    with Image.open(ROOT/'review/waiting.gif') as im:
        duration, count = 0, im.n_frames
        for i in range(count):
            im.seek(i)
            duration += im.info['duration']
    assert count == CYCLE_MS//SAMPLE_MS and duration == CYCLE_MS
    report = {'state': 'waiting', 'character_sources': 16,
              'character_pose_ms': POSE_MS, 'cycle_ms': CYCLE_MS,
              'GIF_frames': count, 'GIF_decoded_ms': duration,
              'effect_sample_ms': SAMPLE_MS,
              'unique_effect_samples': len(set(effects)),
              'character_hashes_unchanged_during_effects': before == after,
              'effects_move_with_frozen_character': frozen,
              'whole_character_method': 'independent complete drawings; no head/body assembly or anatomical warps',
              'invitation_illumination_onsets_ms': [800, 1800],
              'illumination_layer': 'paired background aura, not an attached emitter',
              'played_with_prop': None, 'preview_canvas': list(SIZE),
              'original_anatomical_registration': 'unverified',
              'native_registered': False, 'installed': False}
    (ROOT/'review/technical-checks.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
