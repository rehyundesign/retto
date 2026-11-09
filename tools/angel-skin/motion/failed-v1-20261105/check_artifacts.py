"""Check encoded motion artifacts, not anatomical or native-app approval."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    records = json.loads((ROOT/'sources.json').read_text())
    assert len(records) == 16
    unique, bounds, hashes = set(), {}, {}
    for r in records:
        p = ROOT/r['path']
        assert digest(p) == r['sha256']
        hashes[r['id']] = digest(p)
        im = Image.open(p)
        assert im.mode == 'RGBA' and im.size == (576, 544)
        alpha = im.getchannel('A')
        box = alpha.getbbox()
        assert box is not None
        margins = [box[0], box[1], im.width-box[2], im.height-box[3]]
        assert min(margins) >= 12, (r['id'], margins)
        bounds[r['id']] = {'alpha_box': box, 'margins': margins}
        # Compare visible decoded pixels, ignoring RGB hidden under alpha zero.
        visible = Image.new('RGBA', im.size)
        visible.alpha_composite(im)
        unique.add(hashlib.sha256(visible.tobytes()).hexdigest())
    assert len(unique) == 16
    with Image.open(ROOT/'review/failed.gif') as gif:
        assert gif.n_frames == 64
        duration = 0
        board = Image.new('RGB', (1152, 1168), '#fffaf2')
        for i in range(gif.n_frames):
            gif.seek(i)
            duration += gif.info['duration']
            if i % 4 == 0:
                j = i//4
                thumb = gif.convert('RGB').resize((288, 272), Image.Resampling.LANCZOS)
                x, y = j % 4*288, j//4*292
                board.paste(thumb, (x, y+20))
                ImageDraw.Draw(board).text((x+5, y+3), f'{j:02}', fill='#302b21')
        assert duration == 3200
        board.save(ROOT/'review/final-decoded-board.png')
    # Re-render using only final cells and packaged dependencies; generation
    # caches, previous states and absolute source paths must not be required.
    with tempfile.TemporaryDirectory(prefix='retto-angel-failed-reproduce-') as temp:
        dest = Path(temp)
        for name in ('character', 'effects', 'review'):
            (dest/name).mkdir()
        for name in ('render.py', 'ambient.py', 'sources.json'):
            shutil.copyfile(ROOT/name, dest/name)
        for r in records:
            shutil.copyfile(ROOT/r['path'], dest/r['path'])
        shutil.copyfile(ROOT/'effects/feather.png', dest/'effects/feather.png')
        subprocess.run([sys.executable, str(dest/'render.py')],
                       check=True, capture_output=True, text=True)
        for name in ('character.gif', 'failed.gif'):
            assert digest(dest/'review'/name) == digest(ROOT/'review'/name)
    assert hashes == {r['id']: digest(ROOT/r['path']) for r in records}
    (ROOT/'character-source-lock.json').write_text(json.dumps({'source_sha256': hashes}, indent=2)+'\n')
    (ROOT/'review/alpha-bounds.json').write_text(json.dumps(bounds, indent=2)+'\n')
    report = {'independent_sources': 16, 'unique_visible_decoded_cells': len(unique),
              'gif_frames': 64, 'gif_ms': duration,
              'all_character_margins_at_least_12px': True,
              'clean_render_reproduction_identical': True,
              'character_hashes_unchanged': True,
              'original_anatomical_registration': 'unverified',
              'native_registered': False, 'installed': False}
    (ROOT/'review/artifact-checks.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
