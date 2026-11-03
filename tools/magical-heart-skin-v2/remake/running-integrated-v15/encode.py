from pathlib import Path
from PIL import Image
import json
p=Path(__file__).resolve().parent
for theme in ['dark','white']:
    frames=[Image.open(p/theme/f'{i:02}.png').convert('RGB') for i in range(16)]
    palette=Image.open(p/f'{theme}-board.png').convert('RGB').quantize(colors=256)
    indexed=[im.quantize(palette=palette,dither=Image.Dither.FLOYDSTEINBERG) for im in frames]
    out=p/f'running-{theme}-v15.gif'
    indexed[0].save(out,save_all=True,append_images=indexed[1:],duration=150,loop=0,disposal=2,optimize=False)
    check=Image.open(out)
    assert check.n_frames==16
    duration=0
    for i in range(16):
        check.seek(i)
        duration+=check.info['duration']
    assert duration==2400
    print(f'PASS: {theme} GIF has 16 frames and {duration}ms duration.')
(p/'progress.json').write_text(json.dumps({'state':'running','status':'16_integrated_frame_motion_preview','drawings':16,'duration_seconds':2.4,'native_app_applied':False},indent=2))
