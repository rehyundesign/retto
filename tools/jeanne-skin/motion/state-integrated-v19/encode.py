from PIL import Image
from pathlib import Path
import json
p=Path(__file__).parent
for m in p.glob('**/manifest.json'):
    data=json.loads(m.read_text()); d=m.parent
    durations=[round(t*1000) for t in data['times']] if data.get('times') else [round(data['cycleSeconds']*1000/16)]*16
    for theme,color in [('dark',(24,24,39,255)),('white',(255,253,248,255))]:
        frames=[]
        for i in range(16):
            image=Image.open(d/f'{i:02}.png').convert('RGBA').resize((224,320),Image.Resampling.LANCZOS)
            bg=Image.new('RGBA',image.size,color); bg.alpha_composite(image); frames.append(bg.convert('RGB'))
        frames[0].save(d/f'animation-{theme}.webp',save_all=True,append_images=frames[1:],duration=durations,loop=0,lossless=True)
        check=Image.open(d/f'animation-{theme}.webp'); assert check.n_frames==16
    print(data['id'], '16 frames',sum(durations)/1000,'seconds')
