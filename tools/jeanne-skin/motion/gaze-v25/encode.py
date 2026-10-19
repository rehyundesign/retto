from pathlib import Path
from PIL import Image
import json, hashlib

p = Path(__file__).parent
manifest = json.loads((p/'manifest.json').read_text())
checks = []
for theme, background in [('dark','#181827'),('white','#fffdf8')]:
    frames = []
    for cell in manifest['records']:
        picture = Image.open(p.parent/cell['file']).convert('RGBA').resize((224,320),Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA',(224,320),background)
        canvas.alpha_composite(picture)
        frames.append(canvas.convert('RGB'))
    file = p/('directions-' + theme + '.webp')
    frames[0].save(file,save_all=True,append_images=frames[1:],duration=200,loop=0,lossless=True)
    decoded = Image.open(file)
    assert decoded.n_frames == 16
    durations, hashes = [], []
    for n in range(16):
        decoded.seek(n)
        decoded.load()
        durations.append(decoded.info['duration'])
        hashes.append(hashlib.sha256(decoded.convert('RGB').tobytes()).hexdigest())
    assert durations == [200]*16
    assert len(set(hashes)) == 16
    checks.append({'theme':theme,'distinctDecodedFrames':16,'intervalMs':200,'scanCycleMs':3200,'nativePlayback':'not tested'})
for cell in manifest['records']:
    image = Image.open(p.parent/cell['file'])
    assert image.size == (448,640)
    assert image.mode == 'RGBA'
    assert hashlib.sha256((p.parent/cell['source']).read_bytes()).hexdigest() == cell['sourceSha256']
for cell in json.loads((p/'existing-source-lock.json').read_text()):
    assert hashlib.sha256((p.parent/cell['file']).read_bytes()).hexdigest() == cell['sha256']
(p/'encoded-checks.json').write_text(json.dumps(checks,indent=2))
print(json.dumps(checks))
print('16 source drawings, alpha/dimensions, direction-scan durations and all144 unchanged state files verified.')
