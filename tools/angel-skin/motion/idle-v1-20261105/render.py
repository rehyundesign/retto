"""Assemble independent complete-character drawings; never warp or patch anatomy.

The fixed review camera is wider than the current app cell. This is a motion
study, not a native atlas. White inspection mattes remain on character sources.
"""
from pathlib import Path
import hashlib
import json
import math
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
CROP = (0, 320, 1024, 1408)
SIZE = (512, 544)
POSE_MS = 200
CYCLE_MS = 16 * POSE_MS


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def assemble_characters():
    images = []
    records = []
    prior_path = ROOT / 'sources.json'
    prior = {r['id']: r for r in json.loads(prior_path.read_text())} if prior_path.exists() else {}
    for i in range(16):
        src = ROOT / 'raw' / ('00-clean.png' if i == 0 else f'{i:02}.png')
        dst = ROOT / 'character' / f'{i:02}.png'
        if not src.exists():
            # Reproduce the GIF from committed independent drawing cells.
            record = prior.get(f'{i:02}')
            if not record or not dst.exists() or sha(dst) != record['sha256']:
                raise ValueError(f'{dst}: missing or changed independent source')
            cell = Image.open(dst).convert('RGB')
            images.append(cell)
            records.append(record)
            continue
        im = Image.open(src).convert('RGB')
        if im.size != (1024, 1536):
            raise ValueError(f'{src}: unexpected camera {im.size}')
        # A supported-foot proxy is evidence about baseline drift only.
        # It does not locate anatomical landmarks or certify registration.
        gray = im.convert('L')
        rows = []
        for y in range(1210, 1340):
            hits = sum(gray.getpixel((x, y)) < 240 for x in range(485, 590))
            if hits >= 10:
                rows.append(y)
        if not rows:
            raise ValueError(f'{src}: grounded forepaw proxy missing')
        # Register the character-only scene before adding any separate prop.
        # No scaling by costume bounds, anatomical warping, or head patches.
        dy = 1288 - max(rows)
        if abs(dy) > 40:
            raise ValueError(f'{src}: unexpected floor correction {dy}')
        registered = Image.new('RGB', im.size, 'white')
        registered.paste(im, (0, dy))
        cell = registered.crop(CROP).resize(SIZE, Image.Resampling.LANCZOS)
        cell.save(dst)
        images.append(cell)
        records.append({'id': f'{i:02}', 'raw_sha256': sha(src),
                        'path': f'character/{i:02}.png', 'sha256': sha(dst),
                        'decoded_sha256': hashlib.sha256(cell.tobytes()).hexdigest(),
                        'supported_forepaw_proxy_y_raw': max(rows),
                        'character_only_translation_raw': [0, dy]})
    if len({r['decoded_sha256'] for r in records}) != 16:
        raise ValueError('Missing distinct decoded drawings')
    (ROOT / 'sources.json').write_text(json.dumps(records, indent=2) + '\n')
    return images, records


def shared_palette(frames):
    # Retain rare blue-grey iris tones when generating a common GIF palette.
    sample = Image.new('RGB', (512, 544 * len(frames)))
    for i, frame in enumerate(frames):
        sample.paste(frame.convert('RGB'), (0, 544 * i))
    pal = sample.quantize(colors=224, method=Image.Quantize.MEDIANCUT)
    values = pal.getpalette()[:224 * 3]
    for i in range(32):
        t = i / 31
        values += [round(40 + 100 * t), round(58 + 111 * t), round(68 + 114 * t)]
    pal.putpalette(values)
    return pal


def gif(frames, path, duration):
    pal = shared_palette(frames)
    indexed = [f.convert('RGB').quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG) for f in frames]
    indexed[0].save(path, save_all=True, append_images=indexed[1:],
                    duration=duration, loop=0, optimize=False, disposal=2)


def feather_asset():
    src = ROOT / 'effects' / 'feather-raw.png'
    if not src.exists():
        ready = ROOT / 'effects' / 'feather.png'
        return Image.open(ready).convert('RGBA') if ready.exists() else None
    feather = Image.open(src).convert('RGBA')
    # Remove only the externally connected flat inspection matte. No character
    # pixels, anatomy, identity regions or generated poses are altered here.
    ImageDraw.floodfill(feather, (0, 0), (0, 0, 0, 0), thresh=8)
    box = feather.getchannel('A').getbbox()
    if not box:
        raise ValueError('Empty feather prop')
    feather = feather.crop(box)
    feather.thumbnail((50, 50), Image.Resampling.LANCZOS)
    feather.save(ROOT / 'effects' / 'feather.png')
    return feather


FEATHER_KEYS = [
    (330, 970), (325, 990), (320, 1015), (310, 1040),
    (280, 1045), (255, 940), (210, 1070), (220, 1120),
    (270, 1060), (500, 1030), (735, 1060), (710, 1055),
    (705, 1005), (875, 900), (950, 820), (990, 760),
]


def effect_at(ms, feather, records):
    layer = Image.new('RGBA', SIZE)
    if feather is None:
        return layer
    phase = ms / POSE_MS
    i = min(15, int(phase))
    u = phase - i
    a = FEATHER_KEYS[i]
    b = FEATHER_KEYS[min(i + 1, 15)]
    # Interpolate a separate prop path, never interpolate character drawings.
    x = (a[0] + (b[0] - a[0]) * u) / 2
    dy_a = records[i]['character_only_translation_raw'][1]
    dy_b = records[min(i + 1, 15)]['character_only_translation_raw'][1]
    y = (a[1] + (b[1] - a[1]) * u + dy_a + (dy_b - dy_a) * u - CROP[1]) / 2
    alpha = min(1, ms / 150, max(0, (CYCLE_MS - ms) / 450))
    prop = feather.rotate(18 * math.sin(ms / CYCLE_MS * 2 * math.pi),
                          Image.Resampling.BICUBIC, expand=True)
    prop.putalpha(prop.getchannel('A').point(lambda v: round(v * alpha)))
    layer.alpha_composite(prop, (round(x - prop.width / 2), round(y - prop.height / 2)))
    return layer


def main():
    (ROOT / 'review').mkdir(exist_ok=True)
    frames, records = assemble_characters()
    gif(frames, ROOT / 'review' / 'character.gif', POSE_MS)
    board = Image.new('RGB', (SIZE[0] * 4, (SIZE[1] + 24) * 4), '#eef0f4')
    for i, frame in enumerate(frames):
        x, y = (i % 4) * SIZE[0], (i // 4) * (SIZE[1] + 24)
        board.paste(frame, (x, y + 24))
        ImageDraw.Draw(board).text((x + 8, y + 5), f'{i:02}', fill='#172133')
    board.save(ROOT / 'review' / 'all-poses.png')
    feather = feather_asset()
    if feather is not None:
        playback = []
        for ms in range(0, CYCLE_MS, 50):
            frame = frames[ms // POSE_MS].convert('RGBA')
            fx = effect_at(ms, feather, records)
            frame.alpha_composite(fx)
            playback.append(frame.convert('RGB'))
        gif(playback, ROOT / 'review' / 'idle.gif', 50)
    with Image.open(ROOT / 'review' / 'character.gif') as im:
        times = []
        for i in range(im.n_frames):
            im.seek(i)
            times.append(im.info['duration'])
    report = {'distinct_independent_character_sources': len(records),
              'unique_decoded_character_images': len({r['decoded_sha256'] for r in records}),
              'character_playback_count': 16, 'character_pose_ms': POSE_MS,
              'cycle_ms': CYCLE_MS, 'decoded_character_gif_ms': sum(times),
              'effect_sample_ms': 50 if feather is not None else None,
              'preview_canvas': list(SIZE), 'native_cell': [448, 640],
              'native_display_fit': 'unverified; wider review camera only',
              'original_body_landmark_registration': 'unverified; no fabricated measurements',
              'installed': False,
              'foot_proxy_range_raw': [min(r['supported_forepaw_proxy_y_raw'] for r in records),
                                       max(r['supported_forepaw_proxy_y_raw'] for r in records)]}
    (ROOT / 'review' / 'technical-checks.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
