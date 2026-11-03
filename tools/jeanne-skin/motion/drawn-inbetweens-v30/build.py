from pathlib import Path
from PIL import Image
import json, hashlib

p=Path(__file__).parent
root=p.parent
for state,ms in [('waving',150),('waiting',200)]:
    d=p/state
    for i in range(16):
        source=d/f'{i:02}-source.png'
        assert source.exists(),source
        im=Image.open(source).convert('RGBA')
        im.resize((448,640),Image.Resampling.LANCZOS).save(d/f'{i:02}.png')
    sources=[hashlib.sha256((d/f'{i:02}-source.png').read_bytes()).hexdigest() for i in range(16)]
    assert len(set(sources))==16
    for theme,color in [('dark','#181827'),('white','#fffdf8')]:
        frames=[]
        board=Image.new('RGB',(896,1280),color)
        for i in range(16):
            im=Image.open(d/f'{i:02}.png').convert('RGBA').resize((224,320),Image.Resampling.LANCZOS)
            bg=Image.new('RGBA',(224,320),color);bg.alpha_composite(im)
            frames.append(bg.convert('RGB'));board.paste(frames[-1],((i%4)*224,(i//4)*320))
        board.save(d/f'review-{theme}.png')
        for ext in ['webp','gif']:
            kwargs={'lossless':True} if ext=='webp' else {'disposal':2}
            file=d/f'animation-{theme}.{ext}'
            frames[0].save(file,save_all=True,append_images=frames[1:],duration=ms,loop=0,**kwargs)
            decoded=Image.open(file);assert decoded.n_frames==16,(file,decoded.n_frames)
            durations=[]
            for i in range(16):
                decoded.seek(i);decoded.load();durations.append(decoded.info['duration'])
            assert durations==[ms]*16,(file,durations)
        loop=Image.new('RGB',(1120,320),color)
        for k,i in enumerate([13,14,15,0,1]):loop.paste(frames[i],(k*224,0))
        loop.save(d/f'loop-{theme}.png')
    (d/'manifest.json').write_text(json.dumps({'independentSources':16,'durationMs':ms*16,'integrated':True,'sourceHashes':sources},indent=2))
import zipfile
preserved=json.loads((p/'preserved-keys.json').read_text())
keymap={(r['state'],r['frame']):r for r in preserved}
origins=[]
for state in ['waving','waiting']:
    for i in range(16):
        source=p/state/f'{i:02}-source.png'
        old=keymap.get((state,i))
        if old:
            assert hashlib.sha256(source.read_bytes()).hexdigest()==old['sha256']
            assert Image.open(p/state/f'{i:02}.png').convert('RGBA').tobytes()==Image.open(root/old['file']).convert('RGBA').tobytes()
        origins.append({'state':state,'frame':i,'kind':'preserved drawing' if old else 'new anatomical drawing','source':str(source.relative_to(root)),'hash':hashlib.sha256(source.read_bytes()).hexdigest(),'opticalFlow':False})
with zipfile.ZipFile(p/'jeanne-png-frames.zip','w',zipfile.ZIP_DEFLATED) as z:
    for state in ['waving','waiting']:
        for i in range(16):z.write(p/state/f'{i:02}.png',f'{state}/{i:02}.png')
(p/'source-origins.json').write_text(json.dumps(origins,indent=2))
print('32 complete cells:15 newly drawn in-betweens and17 preserved drawings;GIF/WebP counts,timings and preserved pixels verified')
