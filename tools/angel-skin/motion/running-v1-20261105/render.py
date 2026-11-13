"""Working motion: a character-driven bilateral gust and continuous gold ambiance."""
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
    # Locate an actual warm ivory patch on the visible wing, not a free-floating
    # fixed screen coordinate. This is an FX attachment, not a body landmark.
    points = []
    xs = range(25, 180) if side == -1 else range(390, 555)
    for y in range(115, 330):
        for x in xs:
            r, g, b, a = frame.getpixel((x, y))
            if a > 180 and r > 175 and g > 160 and b > 130 and r >= g >= b+2 and r-g < 45:
                points.append((x, y))
    if len(points) < 20:
        raise ValueError('No visible wing patch for the gust attachment')
    lo, hi = min(x for x, y in points), max(x for x, y in points)
    target = lo + (hi-lo)*(.72 if side == -1 else .28)
    band = [p for p in points if abs(p[0]-target) < 7]
    if not band:
        band = points
    y = statistics.median(y for x, y in band)
    return min(band, key=lambda p: abs(p[0]-target)+abs(p[1]-y))


def particle_path(origin, side, q, phase=0):
    return (origin[0] + side*(125*q + 8*math.sin(math.pi*q+phase)*q),
            origin[1] + 100*q + 16*math.sin(math.pi*q))


def gust_effect(ms, feather, attachments):
    soft = Image.new('RGBA', SIZE)
    fine = Image.new('RGBA', SIZE)
    sd, fd = ImageDraw.Draw(soft), ImageDraw.Draw(fine)
    # Three releases originate on the real wing drawings at stroke onset/peak.
    # Each release keeps its birth point as the wing subsequently recovers.
    for source_pose in (6, 7, 8):
        age = ms - source_pose*POSE_MS
        if not (0 <= age < 900):
            continue
        q = age/900
        envelope = math.sin(math.pi*q)**1.2
        for side in (-1, 1):
            origin = attachments[str(source_pose)][str(side)]
            tail = max(0, q-.22)
            pts = [particle_path(origin, side, tail+(q-tail)*k/18) for k in range(19)]
            sd.line(pts, fill=(255, 209, 79, round(75*envelope)), width=9, joint='curve')
            fd.line(pts, fill=(246, 193, 62, round(90*envelope)), width=1, joint='curve')
            for j in range(3):
                u = max(0, q-j*.035)
                x, y = particle_path(origin, side, u, j*.4)
                radius = 1.3 + (j % 2)*.5
                fd.ellipse((x-radius, y-radius, x+radius, y+radius),
                           fill=(247, 191, 51, round(145*envelope*(1-j*.18))))
    layer = soft.filter(ImageFilter.GaussianBlur(4))
    layer.alpha_composite(fine)
    # A few drifting feathers follow the same down/out wind after the main beat.
    age = ms - 7*POSE_MS
    if 0 <= age < 1050:
        q = age/1050
        for side in (-1, 1):
            origin = attachments['7'][str(side)]
            x, y = particle_path(origin, side, q)
            f = feather.copy(); f.thumbnail((27, 27), Image.Resampling.LANCZOS)
            f = f.rotate(side*(-20 + 90*q), Image.Resampling.BICUBIC, expand=True)
            f = ambient.scaled_alpha(f, .8*math.sin(math.pi*q)**1.3)
            layer.alpha_composite(f, (round(x-f.width/2), round(y-f.height/2)))
    return layer


def all_effects(ms, feather, attachments):
    # The approved ambiance continues through holds; the extra forceful gust is
    # specifically timed to the working character's wing stroke and pet response.
    result = ambient.back_effects(ms, feather)
    result.alpha_composite(gust_effect(ms, feather, attachments))
    return result


def main():
    records = json.loads((ROOT/'sources.json').read_text())
    assert [r['id'] for r in records] == [f'{i:02}' for i in range(16)]
    frames = []
    before = {}
    for r in records:
        p = ROOT/r['path']; assert sha(p) == r['sha256']
        before[r['id']] = sha(p); frames.append(Image.open(p).convert('RGBA'))
    attachments = {}
    for i in (6, 7, 8):
        attachments[str(i)] = {str(side):list(wing_emitter(frames[i],side)) for side in (-1,1)}
    (ROOT/'review/wing-attachments.json').write_text(json.dumps(attachments,indent=2)+'\n')
    feather = Image.open(ROOT/'effects/feather.png').convert('RGBA')
    white = []
    for f in frames:
        im=Image.new('RGBA',SIZE,'white');im.alpha_composite(f);white.append(im)
    ambient.save_gif(white,ROOT/'review/character.gif',POSE_MS)
    playback=[];effect_hashes=[]
    for ms in range(0,CYCLE_MS,SAMPLE_MS):
        fx=all_effects(ms,feather,attachments)
        im=Image.new('RGBA',SIZE,(255,251,244,255));im.alpha_composite(fx)
        im.alpha_composite(frames[ms//POSE_MS]);playback.append(im.convert('RGB'))
        effect_hashes.append(hashlib.sha256(fx.tobytes()).hexdigest())
        if ms % 300 == 0:
            im.save(ROOT/'review'/f'composite-{ms:04}.png')
    ambient.save_gif(playback,ROOT/'review/running.gif',SAMPLE_MS)
    # Two times inside the SAME150ms character interval, not different poses.
    frozen_moves=all_effects(950,feather,attachments).tobytes()!=all_effects(1000,feather,attachments).tobytes()
    after={r['id']:sha(ROOT/r['path']) for r in records}
    assert before==after and frozen_moves
    with Image.open(ROOT/'review/running.gif') as im:
        duration=0;count=im.n_frames
        for i in range(count):im.seek(i);duration+=im.info['duration']
    assert duration==CYCLE_MS
    report={'state':'running','character_sources':16,'character_pose_ms':POSE_MS,
            'cycle_ms':CYCLE_MS,'GIF_frames':count,'GIF_decoded_ms':duration,
            'effect_sample_ms':SAMPLE_MS,'unique_effect_samples':len(set(effect_hashes)),
            'character_hashes_unchanged_during_effects':before==after,
            'effects_move_with_frozen_character':frozen_moves,
            'whole_character_method':'independent complete drawings; no head/body assembly or anatomical warps',
            'gust_birth_poses':[6,7,8],'attachment_method':'ivory pixels on each actual stroke drawing',
            'played_with_prop':None,'preview_canvas':list(SIZE),
            'original_anatomical_registration':'unverified','native_registered':False,'installed':False}
    (ROOT/'review/technical-checks.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))


if __name__=='__main__':
    main()
