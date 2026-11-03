from PIL import Image
from pathlib import Path
p=Path(__file__).parent
for theme,color in [('dark',(24,24,39,255)),('white',(255,253,248,255))]:
    frames=[]
    for i in range(16):
        image=Image.open(p/f'{i:02}.png').convert('RGBA').resize((224,320),Image.Resampling.LANCZOS)
        bg=Image.new('RGBA',image.size,color)
        bg.alpha_composite(image)
        frames.append(bg.convert('RGB'))
    frames[0].save(p/f'animation-{theme}.webp',save_all=True,append_images=frames[1:],duration=150,loop=0,lossless=True)
    check=Image.open(p/f'animation-{theme}.webp')
    assert check.n_frames==16
    print(theme,check.n_frames,'frames; 2.4 sec')
