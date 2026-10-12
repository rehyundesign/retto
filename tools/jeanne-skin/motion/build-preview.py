"""Build the current motion preview and source-count report without changing approved art."""
from pathlib import Path
from PIL import Image
import hashlib
import json

ROOT = Path(__file__).resolve().parent
spec = json.loads((ROOT / 'delivery-map.json').read_text())
states = spec['states']
report = []
for state in states:
    frames = []
    source_hashes = []
    pixel_hashes = []
    for frame in range(16):
        source = ROOT / 'production-raw' / f"{state['id']}-{frame:02}.png"
        if not source.exists():
            raise FileNotFoundError(source)
        image = Image.open(source).convert('RGBA')
        # Export an independent character cell. Effects are rendered separately.
        image = image.resize((448, 640), Image.Resampling.LANCZOS)
        rgba = bytearray(image.tobytes())
        for offset in range(0, len(rgba), 4):
            if rgba[offset + 3] == 0:
                rgba[offset:offset + 3] = b'\0\0\0'
        image = Image.frombytes('RGBA', image.size, bytes(rgba))
        destination = ROOT / 'characters' / f"{state['id']}-{frame:02}.png"
        image.save(destination)
        source_hashes.append(hashlib.sha256(source.read_bytes()).hexdigest())
        pixel_hashes.append(hashlib.sha256(image.tobytes()).hexdigest())
        frames.append('characters/' + destination.name)
    state['files'] = frames
    report.append({'state': state['id'], 'sourceCount': len(frames),
                   'uniqueSources': len(set(source_hashes)),
                   'uniqueDecodedPixels': len(set(pixel_hashes)),
                   'cycleSeconds': state['cycle'], 'intervalSeconds': state['cycle'] / 16,
                   'originalRettoRegistration': 'unverified',
                   'meaningfulPoseContinuity': 'requires visual review'})
manifest = {'states': states, 'effectPeriod': 8, 'effectSamplingHz': 10,
            'redrawHz': 60, 'registration': 'approved concept proportions; original registration unverified'}
(ROOT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
(ROOT / 'source-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
assert all(r['uniqueSources'] == 16 and r['uniqueDecodedPixels'] == 16 for r in report)
print('160 independent sources and decoded character cells; 16 per sequence.')
