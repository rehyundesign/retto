"""Effect-only night-sky revision. Original character sources remain read-only."""
from pathlib import Path
from functools import lru_cache
import argparse
import hashlib
import importlib.util
import json
import math
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
MOTION = ROOT.parent
SPECS = {
    'idle': ('idle-v2-20261105', 200, 'existing yellow-star handoff; night ambiance and edge fade only'),
    'running': ('running-v1-20261105', 150, 'crescent with progressing orbiting star and music notes, responding to the wing stroke'),
    'waiting': ('waiting-v1-20261105', 200, 'paired star-and-note signals brighten with BOTH companions offering hands'),
    'failed': ('failed-v1-20261105', 200, 'scattered light and notes gather into a star after the comforting contact'),
    'waving': ('waving-v1-20261105', 150, 'crescent arc and star-note finale unfold with the forepaw greeting'),
    'jumping': ('jumping-v1-20261105', 150, 'existing unfinished click draft; night ambiance and edge fade only, no new motion or point motif'),
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n')


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def smooth(t):
    t = max(0, min(1, t))
    return t*t*(3-2*t)


def opacity(im, factor):
    out = im.copy()
    out.putalpha(out.getchannel('A').point(lambda a: round(a*max(0, min(1, factor)))))
    return out


@lru_cache(maxsize=2)
def edge_mask(size):
    w, h = size
    mask = Image.new('L', size)
    values = []
    for y in range(h):
        fy = smooth(min(y, h-1-y)/94)
        for x in range(w):
            fx = smooth(min(x, w-1-x)/94)
            radius = math.hypot((x-(w-1)/2)/(w*.53), (y-(h-1)/2)/(h*.53))
            radial = 1-smooth((radius-.52)/.53)
            values.append(round(255*fx*fy*radial))
    mask.putdata(values)
    return mask


def fade_edges(im):
    out = im.copy()
    out.putalpha(ImageChops.multiply(out.getchannel('A'), edge_mask(im.size)))
    return out


def fade_idle_glow(front, module, star, records, ms, cycle):
    """Fade the prop halo at cell edges while preserving every actual star pixel."""
    phase = ms/module.POSE_MS
    i = min(15, int(phase)); u = phase-i
    a, b = module.STAR_KEYS[i], module.STAR_KEYS[min(15, i+1)]
    dy_a = records[i]['character_only_translation_raw'][1]
    dy_b = records[min(15, i+1)]['character_only_translation_raw'][1]
    x = (a[0]+(b[0]-a[0])*u)/2+16
    y = (a[1]+(b[1]-a[1])*u+dy_a+(dy_b-dy_a)*u-320)/2
    prop = star.rotate(12*math.sin(math.tau*ms/cycle), Image.Resampling.BICUBIC, expand=True)
    prop = module.scaled_alpha(prop, min(1, ms/150, max(0, (cycle-ms)/450)))
    protected = Image.new('L', front.size)
    protected.paste(prop.getchannel('A').point(lambda a: 255 if a else 0),
                    (round(x-prop.width/2), round(y-prop.height/2)))
    mask = ImageChops.lighter(edge_mask(front.size), protected)
    out = front.copy()
    out.putalpha(ImageChops.multiply(front.getchannel('A'), mask))
    assert ImageChops.multiply(ImageChops.difference(front.getchannel('A'), out.getchannel('A')), protected).getbbox() is None
    return out


def night_atmosphere(ms, size, cycle):
    w, h = size
    t = ms/cycle
    layer = Image.new('RGBA', size)
    cloud = Image.new('RGBA', size)
    d = ImageDraw.Draw(cloud)
    cx, cy = w/2+12*math.sin(math.tau*t), h*.45+8*math.cos(math.tau*t)
    d.ellipse((cx-221, cy-195, cx+221, cy+195), fill=(51, 63, 133, 74))
    d.ellipse((cx-148, cy-182, cx+183, cy+104), fill=(109, 88, 170, 39))
    d.ellipse((cx-172, cy-112, cx+88, cy+183), fill=(92, 123, 172, 22))
    layer.alpha_composite(cloud.filter(ImageFilter.GaussianBlur(39)))
    dots = Image.new('RGBA', size)
    d = ImageDraw.Draw(dots)
    for j in range(23):
        q = (t+j/23) % 1
        x = 34+((j*.61803398875) % 1)*(w-68)+6*math.sin(math.tau*t+j)
        y = 38+((j*.371) % 1)*(h-100)+9*math.sin(math.tau*t+j*.7)
        a = round(115*math.sin(math.pi*q)**2)
        color = (206, 214, 250, a) if j % 3 else (255, 229, 166, a)
        d.ellipse((x-.8, y-.8, x+.8, y+.8), fill=color)
        if j % 7 == 0:
            d.line((x-3, y, x+3, y), fill=color)
            d.line((x, y-3, x, y+3), fill=color)
    layer.alpha_composite(dots)
    return layer


@lru_cache(maxsize=40)
def music_note(pixels):
    scale = 3
    im = Image.new('RGBA', (pixels*scale, pixels*scale))
    d = ImageDraw.Draw(im)
    s = pixels*scale
    gold = (255, 226, 153, 238)
    d.ellipse((s*.15, s*.62, s*.48, s*.85), fill=gold)
    d.line((s*.45, s*.72, s*.45, s*.16), fill=gold, width=max(2, round(s*.06)))
    d.line([(s*.45, s*.17), (s*.75, s*.29), (s*.8, s*.47)],
           fill=gold, width=max(2, round(s*.07)), joint='curve')
    return im.resize((pixels, pixels), Image.Resampling.LANCZOS)


@lru_cache(maxsize=8)
def crescent(pixels):
    scale = 3
    s = pixels*scale
    mask = Image.new('L', (s, s))
    d = ImageDraw.Draw(mask)
    d.ellipse((s*.07, s*.06, s*.91, s*.94), fill=255)
    d.ellipse((s*.35, -s*.07, s*1.12, s*.74), fill=0)
    im = Image.new('RGBA', (s, s), (255, 231, 168, 0))
    im.putalpha(mask)
    return im.resize((pixels, pixels), Image.Resampling.LANCZOS)


def stamp(layer, asset, centre, pixels, alpha=1, angle=0, halo=True):
    im = asset.copy()
    im.thumbnail((pixels, pixels), Image.Resampling.LANCZOS)
    if angle:
        im = im.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    im = opacity(im, alpha)
    x, y = round(centre[0]-im.width/2), round(centre[1]-im.height/2)
    if halo:
        glow = Image.new('RGBA', layer.size)
        g = Image.new('RGBA', im.size, (245, 207, 115, 0))
        g.putalpha(im.getchannel('A').point(lambda a: round(a*.36)))
        glow.alpha_composite(g, (x, y))
        layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(6)))
    layer.alpha_composite(im, (x, y))


def point_effect(state, ms, size, cycle, star):
    layer = Image.new('RGBA', size)
    d = ImageDraw.Draw(layer)
    w, h = size
    t = ms/cycle
    if state == 'running':
        centre = (w*.25, 120)
        stamp(layer, crescent(60), centre, 60, .88, angle=-9)
        pts = [(centre[0]+64*math.cos(math.tau*k/72),
                centre[1]+33*math.sin(math.tau*k/72)) for k in range(73)]
        d.line(pts, fill=(246, 218, 160, 57), width=1)
        a = math.tau*(t-.17)
        pulse = .7+.3*max(0, math.sin(math.tau*(t-.25)))
        stamp(layer, star, (centre[0]+64*math.cos(a), centre[1]+33*math.sin(a)), 30, pulse, angle=10*math.sin(a))
        for j in range(3):
            q = (t-j*.13) % 1
            a = math.tau*(q-.17)
            stamp(layer, music_note(25), (centre[0]+64*math.cos(a), centre[1]+33*math.sin(a)),
                  25, (.36+.28*math.sin(math.pi*q)**2), angle=8*math.sin(a), halo=False)
    elif state == 'waiting':
        for j, x in enumerate((86, w-86)):
            beat = max(math.exp(-((ms-b)/240)**2) for b in (1050, 2050))
            y = 137+8*math.sin(math.tau*t+j*.3)
            stamp(layer, star, (x, y), 42, .48+.5*beat, angle=8*math.sin(math.tau*t))
            stamp(layer, music_note(28), (x+(-1 if j==0 else 1)*31, y-25), 28, .35+.6*beat, halo=False)
            for birth in (1000, 2000):
                q = (ms-birth)/680
                if 0 <= q < 1:
                    radius = 23+25*q
                    d.ellipse((x-radius, y-radius, x+radius, y+radius),
                              outline=(255, 222, 151, round(105*math.sin(math.pi*q)**2)), width=1)
    elif state == 'failed':
        if 350 <= ms < cycle-100:
            age = ms-350
            join = smooth((age-250)/1050)
            envelope = smooth(age/200)*(1-smooth((ms-(cycle-650))/550))
            cx, cy = w/2, 91
            for j in range(8):
                a = math.tau*j/8+.3
                radius = (1-join)*(70+12*(j%2))
                x, y = cx+radius*math.cos(a), cy+radius*.5*math.sin(a)
                if j % 3 == 0:
                    stamp(layer, music_note(23), (x, y), 23, envelope*(1-join), angle=18*(1-join), halo=False)
                else:
                    d.ellipse((x-2, y-2, x+2, y+2), fill=(255, 225, 151, round(190*envelope*(1-join))))
            stamp(layer, star, (cx, cy), 49, envelope*join, angle=4*math.sin(math.tau*t))
            if join > .5:
                stamp(layer, music_note(25), (cx+37, cy-8), 25, envelope*join*.7, halo=False)
    elif state == 'waving':
        envelope = smooth((ms-400)/350)*(1-smooth((ms-1750)/500))
        centre = (w/2, 186)
        points = [(centre[0]+168*math.cos(math.radians(200+k*140/72)),
                   centre[1]+131*math.sin(math.radians(200+k*140/72))) for k in range(73)]
        d.line(points, fill=(255, 222, 152, round(90*envelope)), width=2)
        stamp(layer, crescent(38), (w/2, 111), 38, envelope*.85, angle=15)
        for j in range(5):
            a = math.radians(211+j*29)
            centre_j = (centre[0]+168*math.cos(a), centre[1]+131*math.sin(a))
            arrival = smooth((ms-(480+j*95))/240)
            alpha = envelope*arrival
            stamp(layer, star if j%2==0 else music_note(34), centre_j,
                  36 if j==2 else 29, alpha, angle=8*math.sin(math.tau*t+j))
    return layer


def border_max(alpha):
    w, h = alpha.size
    return max(alpha.crop((0, 0, w, 1)).getextrema()[1],
               alpha.crop((0, h-1, w, h)).getextrema()[1],
               alpha.crop((0, 0, 1, h)).getextrema()[1],
               alpha.crop((w-1, 0, w, h)).getextrema()[1])


def save_webp(frames, path, duration):
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=duration,
                   loop=0, lossless=True, quality=100, method=2, exact=True)


def load_original(state, folder, records, frames):
    source = MOTION/folder
    if state != 'idle':
        sys.modules['ambient'] = load_module(source/'ambient.py', f'night_ambient_{state}')
    module = load_module(source/'render.py', f'night_original_{state}')
    feather = Image.open(source/'effects/feather.png').convert('RGBA')
    star = Image.open(MOTION/'idle-v2-20261105/effects/star.png').convert('RGBA')
    attachments = None
    if state == 'running':
        attachments = {str(i):{str(s):list(module.wing_emitter(frames[i], s)) for s in (-1, 1)} for i in (6,7,8)}
    elif state == 'jumping':
        attachments = {'lift':{str(s):list(module.wing_emitter(frames[5], s)) for s in (-1,1)},
                       'landing':module.landing_support(frames[11])}
    def old(ms):
        if state == 'idle':
            return module.back_effects(ms, feather), module.star_effect(ms, star, records)
        if state in ('running', 'jumping'):
            return module.all_effects(ms, feather, attachments), Image.new('RGBA', frames[0].size)
        return module.all_effects(ms, feather), Image.new('RGBA', frames[0].size)
    return module, star, old


def display_alpha_cleanup(state, source, out, records, frames):
    """Restore missing white fur from the SAME original whole-frame RGB drawing.

    Original source files remain locked. No head/body masks, new pose, repaint,
    rescaling or drawing assembly: only the faulty background matte is replaced.
    Every formerly visible pixel must have exactly the same RGB as the raw pose.
    """
    if state != 'running':
        return frames, None
    cache = out/'alpha-cleanup.json'
    dest = out/'character-alpha'
    dest.mkdir(exist_ok=True)
    if cache.exists():
        info = json.loads(cache.read_text())
        assert info['matte_code_sha256'] == sha(ROOT/'matte.py')
        for item, record in zip(info['sources'], records):
            assert item['original_source_sha256'] == record['sha256']
            assert item['display_sha256'] == sha(out/item['display_path'])
        return [Image.open(out/i['display_path']).convert('RGBA') for i in info['sources']], info
    matte = load_module(ROOT/'matte.py', 'night_same_pose_matte')
    repaired, items = [], []
    for record, original in zip(records, frames):
        raw_path = source/'raw'/f"{record['id']}.png"
        assert sha(raw_path) == record['raw_sha256']
        raw = Image.open(raw_path).convert('RGB').resize((544,544), Image.Resampling.LANCZOS)
        scene = Image.new('RGB', (544,544), 'white')
        scene.paste(raw, tuple(record['registration_translation_scene_px']))
        padded = Image.new('RGB', original.size, 'white'); padded.paste(scene, (16,0))
        visible = original.getchannel('A').point(lambda a:255 if a else 0)
        difference = ImageChops.difference(original.convert('RGB'), padded)
        assert max(ImageChops.multiply(c,visible).getextrema()[1] for c in difference.split()) == 0
        fixed = matte.cutout(padded)
        path = dest/f"{record['id']}.png"; fixed.save(path)
        alpha_difference = ImageChops.difference(original.getchannel('A'), fixed.getchannel('A'))
        changed = sum(alpha_difference.histogram()[1:])
        items.append({'id':record['id'], 'original_source_sha256':record['sha256'],
                      'raw_sha256':record['raw_sha256'], 'display_path':str(path.relative_to(out)),
                      'display_sha256':sha(path), 'visible_source_RGB_difference':0,
                      'alpha_changed_pixels':changed})
        repaired.append(fixed)
    info = {'method':'same whole-frame original RGB and identical camera; alpha extraction only',
            'matte_code_sha256':sha(ROOT/'matte.py'), 'original_files_unchanged':True,
            'new_pose_or_head_body_assembly':False, 'sources':items}
    write(cache, info)
    return repaired, info


def render_state(state):
    folder, pose_ms, motif = SPECS[state]
    source, out = MOTION/folder, ROOT/state
    out.mkdir(parents=True, exist_ok=True)
    records = json.loads((source/'sources.json').read_text())
    before = {r['id']:sha(source/r['path']) for r in records}
    assert len(before) == 16 and all(before[r['id']]==r['sha256'] for r in records)
    lock_path = ROOT/'locks'/f'{state}.json'
    if lock_path.exists():
        assert json.loads(lock_path.read_text())['source_sha256']==before
    else:
        write(lock_path, {'source_sha256':before, 'method':'pre-effect-repair source lock; does not imply visual/native approval'})
    originals = {str(p):sha(p) for p in (source/'review'/f'{state}.gif', source/'review/character.gif')}
    frames = [Image.open(source/r['path']).convert('RGBA') for r in records]
    frames, alpha_cleanup = display_alpha_cleanup(state, source, out, records, frames)
    size, cycle = frames[0].size, pose_ms*16
    module, star, old = load_original(state, folder, records, frames)
    def effects(ms):
        back, front = old(ms)
        sky = night_atmosphere(ms, size, cycle)
        sky.alpha_composite(back)
        sky.alpha_composite(point_effect(state, ms, size, cycle, star))
        if state == 'idle':
            front = fade_idle_glow(front, module, star, records, ms, cycle)
        return fade_edges(sky), front
    playback, effects_hashes, edge_values = [], [], []
    sample_ms = min(cycle-50, 1400 if state in ('idle','waiting','failed') else 1000)
    for ms in range(0, cycle, 50):
        back, front = effects(ms)
        edge_values.append(border_max(back.getchannel('A')))
        frame = back.copy()
        frame.alpha_composite(frames[ms//pose_ms])
        frame.alpha_composite(front)
        playback.append(frame)
        effects_hashes.append(hashlib.sha256(back.tobytes()+front.tobytes()).hexdigest())
        if ms == sample_ms:
            frame.save(out/'preview.png')
            back.save(out/'effects-only.png')
    # Alpha remains continuous in the actual animated artifact, not just a GIF screenshot.
    save_webp(playback, out/'night.webp', 50)
    save_webp(frames, out/'character.webp', pose_ms)
    preview = []
    for frame in playback:
        bg = Image.new('RGBA', size, '#162039'); bg.alpha_composite(frame); preview.append(bg.convert('RGB'))
    save_gif = module.save_gif if hasattr(module, 'save_gif') else module.ambient.save_gif
    save_gif(preview, out/'preview.gif', 50)
    duration, decoded_edges = 0, []
    with Image.open(out/'night.webp') as im:
        assert im.n_frames == len(playback)
        board = Image.new('RGB', (size[0]*4, (size[1]+24)*4), '#162039')
        for i in range(im.n_frames):
            im.seek(i); im.load()
            duration += im.info['duration']
            decoded = im.convert('RGBA')
            decoded_edges.append(border_max(decoded.getchannel('A')))
            # Lossless export must preserve visible pixels on both dark and light windows.
            for color in ('#162039', '#f3f0e9'):
                a = Image.new('RGBA', size, color); a.alpha_composite(decoded)
                b = Image.new('RGBA', size, color); b.alpha_composite(playback[i])
                assert max(ImageChops.difference(a, b).getextrema()[j][1] for j in range(3)) <= 1
            if i % (pose_ms//50) == 0:
                j = i//(pose_ms//50); x, y = j%4*size[0], j//4*(size[1]+24)
                bg = Image.new('RGBA', size, '#162039'); bg.alpha_composite(decoded)
                board.paste(bg.convert('RGB'), (x,y+24))
                ImageDraw.Draw(board).text((x+6,y+4), f'{j:02}', fill='white')
        board.thumbnail((1152, 1180), Image.Resampling.LANCZOS); board.save(out/'decoded-board.png')
    assert duration == cycle and max(decoded_edges)==0 and max(edge_values)==0
    after = {r['id']:sha(source/r['path']) for r in records}
    assert before == after and all(sha(Path(p))==h for p,h in originals.items())
    back0, front0 = effects(0); back1, front1 = effects(50)
    assert (back0.tobytes()+front0.tobytes()) != (back1.tobytes()+front1.tobytes())
    # Comparison on windows with different colours/text under the same transparent image.
    selected = playback[sample_ms//50]
    comparison = Image.new('RGB', (size[0]*3, size[1]+35), '#162039')
    for j, (color, title) in enumerate((('#162039','Dark window'),('#f3f0e9','Light window'),('#6c607f','Different window colours'))):
        bg = Image.new('RGBA', size, color); d = ImageDraw.Draw(bg)
        for k in range(11):
            y = 45+k*43
            d.line((18,y,size[0]-18,y), fill=(125,139,164,55), width=2)
        d.rounded_rectangle((24,56,size[0]*.63,size[1]-48),radius=12,fill=(89,115,155,29),outline=(141,155,179,75))
        d.rounded_rectangle((size[0]*.38,128,size[0]-21,size[1]-18),radius=12,fill=(148,119,164,24),outline=(157,141,175,67))
        bg.alpha_composite(selected); comparison.paste(bg.convert('RGB'), (j*size[0],35))
        ImageDraw.Draw(comparison).text((j*size[0]+12,10),title,fill='white')
    comparison.save(out/'window-comparison.png')
    report = {'state':state, 'mode':'effect-repair', 'source_folder':folder,
              'source_count':16, 'pose_ms':pose_ms, 'cycle_ms':cycle, 'effect_sample_ms':50,
              'animated_webp_frames':len(playback), 'decoded_webp_ms':duration,
              'continuous_alpha_preserved':True, 'visible_lossless_pixels_on_dark_and_light':True,
              'effect_outer_border_alpha_max':max(edge_values), 'decoded_full_outer_border_alpha_max':max(decoded_edges),
              'edge_fade_mask_centre_line':{str(x):edge_mask(size).getpixel((x,size[1]//2)) for x in (0,8,16,32,64,96)},
              'original_character_hashes_unchanged':before==after, 'original_gifs_unchanged':True,
              'unique_effect_samples':len(set(effects_hashes)), 'effects_advance_with_frozen_character':True,
              'point_motif':motif, 'character_regenerated':False,
              'same_pose_alpha_cleanup':alpha_cleanup is not None,
              'visible_original_RGB_preserved':True,
              'idle_star_prop_pixels_preserved':state=='idle',
              'idle_prop_halo_edge_faded':state=='idle', 'original_registration':'unverified',
              'native_installed':False, 'click_motion_status':'unfinished original draft; three-flying revision not generated' if state=='jumping' else None}
    write(out/'validation.json',report)
    print(json.dumps({'state':state,'frames':len(playback),'ms':duration,'border_alpha':max(decoded_edges),'source_unchanged':True,'webp_bytes':(out/'night.webp').stat().st_size}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--states', nargs='+', choices=list(SPECS), default=list(SPECS))
    args = parser.parse_args()
    for state in args.states:
        render_state(state)
