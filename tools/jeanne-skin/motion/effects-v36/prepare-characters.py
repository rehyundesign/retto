"""Normalize full canvases only; no limb, garment, or identity-region compositing."""
from pathlib import Path
from PIL import Image, ImageDraw
import json, hashlib
ROOT=Path(__file__).parent
lock=json.loads((ROOT/'approved-motion-lock.json').read_text())
pilots={('idle',0):'idle-00-source.png',('running',5):'running-05-source.png',('sleeping',8):'sleeping-08-source.png',('waving',6):'waving-06-clean-source.png'}
records=[]
for s in lock['states']:
    d=ROOT/'characters'/s['id'];d.mkdir(parents=True,exist_ok=True)
    frames=[];missing=[]
    for i in range(len(s['files'])):
        src=ROOT/'clean-sources'/f"{s['id']}-{i:02}.png"
        if (s['id'],i) in pilots:src=ROOT/'clean-pilot'/pilots[s['id'],i]
        repaired=ROOT/'clean-sources'/f"{s['id']}-{i:02}-repaired.png"
        if repaired.exists():src=repaired
        edge=ROOT/'clean-sources'/f"{s['id']}-{i:02}-edge-clean.png"
        if edge.exists():src=edge
        if not src.exists():missing.append(i);continue
        dst=d/f'{i:02}.png'
        im=Image.open(src).convert('RGBA').resize((448,640),Image.Resampling.LANCZOS)
        im.save(dst);frames.append((i,im))
        records.append({'state':s['id'],'frame':i,'source':str(src.relative_to(ROOT)),'sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'output':str(dst.relative_to(ROOT)),'operation':'whole-canvas resize 448x640; no per-character registration transform','visualReview':'pending'})
    for theme,color in [('dark','#181827'),('white','#fffdf8')]:
        # Each pair is original then clean at the exact native 1x size.
        board=Image.new('RGB',(896,352*((len(s['files'])+1)//2)),color);draw=ImageDraw.Draw(board)
        for i,im in frames:
            for k,cell in enumerate([Image.open(ROOT/'locked'/s['id']/f'{i:02}.png').convert('RGBA'),im]):
                x=(i%2*2+k)*224;y=i//2*352
                bg=Image.new('RGBA',(224,320),color);bg.alpha_composite(cell.resize((224,320),Image.Resampling.LANCZOS));board.paste(bg.convert('RGB'),(x,y));draw.text((x+8,y+324),f'{i:02} '+('original' if k==0 else 'clean'),fill='#888888')
        board.save(ROOT/f"{s['id']}-comparison-{theme}.png")
    print(s['id'],len(frames),'/',len(s['files']),'missing',missing)
(ROOT/'character-source-records.json').write_text(json.dumps(records,indent=2))
print('All character-only cells require visual review before delivery; equal canvas size is not registration proof.')
