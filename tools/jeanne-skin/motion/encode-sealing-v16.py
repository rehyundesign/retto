from pathlib import Path
from PIL import Image
import json
root=Path(__file__).resolve().parent
records=json.loads((root/'state-direct-v1/sealing-v16-validation.json').read_text())
for r in records:
    for theme in ['dark','white']:
        source=root/'state-direct-v1/exports'/r['state']/theme
        frames=[Image.open(f).convert('RGBA') for f in sorted(source.glob('*.png'))]
        expected=int(r['exportSeconds']*r['exportHz'])
        if len(frames)!=expected: raise ValueError(f"sample count {r['state']}: {len(frames)} != {expected}")
        target=root/'state-direct-v1'/f"{r['state']}-{theme}.webp"
        frames[0].save(target,save_all=True,append_images=frames[1:],duration=50,loop=0,lossless=True)
        check=Image.open(target);duration=0
        for i in range(check.n_frames):
            check.seek(i);check.load();duration+=check.info['duration']
        if duration!=r['exportSeconds']*1000: raise ValueError('timing mismatch')
    print(r['state'],r['drawings'],'drawings',r['exportSeconds'],'seconds')
