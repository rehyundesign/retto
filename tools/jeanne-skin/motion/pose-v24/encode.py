from PIL import Image
from pathlib import Path
import json, hashlib

p = Path(__file__).parent
root = p.parent
checks = []
for row in json.loads((p/'rows.json').read_text()):
    if not row['files'][0].startswith('pose-v24/'):
        continue
    count = len(row['files'])
    durations = [round(row['cycle']*1000/count)]*count
    for theme, color in [('dark','#181827'),('white','#fffdf8')]:
        frames = []
        for f in row['files']:
            im = Image.open(root/f).convert('RGBA').resize((224,320),Image.Resampling.LANCZOS)
            bg = Image.new('RGBA',im.size,color)
            bg.alpha_composite(im)
            frames.append(bg.convert('RGB'))
        out = root/next(a['file'] for a in row['animations'] if a['theme']==theme)
        frames[0].save(out,save_all=True,append_images=frames[1:],duration=durations,loop=0,lossless=True)
        decoded = Image.open(out)
        assert decoded.n_frames == count, (row['id'],decoded.n_frames,count)
        actual, hashes = [], []
        for i in range(count):
            decoded.seek(i)
            decoded.load()
            actual.append(decoded.info['duration'])
            hashes.append(hashlib.sha256(decoded.convert('RGB').tobytes()).hexdigest())
        assert actual == durations
        assert len(set(hashes)) == count
        checks.append({'state':row['id'],'theme':theme,'frames':count,'durationsMs':actual,'cycleMs':sum(actual),'distinctDecodedFrames':len(set(hashes))})
for row in json.loads((p/'rows.json').read_text()):
    for f in row['files'] + [a['file'] for a in row['animations']]:
        assert (root/f).is_file(), f
for locked in json.loads((p/'unaffected-lock.json').read_text()):
    assert hashlib.sha256((root/locked['file']).read_bytes()).hexdigest() == locked['sha256']
for locked in json.loads((p/'approved-jump-lock.json').read_text()):
    assert hashlib.sha256((root/locked['file']).read_bytes()).hexdigest() == locked['hash']
(p/'encoded-checks.json').write_text(json.dumps(checks,indent=2))
print(json.dumps(checks))
print('Preview paths, unchanged-state sources, and approved jump input files verified.')
