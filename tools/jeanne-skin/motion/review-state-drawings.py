from PIL import Image, ImageDraw
from pathlib import Path
import json, hashlib, math
root=Path(__file__).resolve().parent
plan=json.loads((root/'state-direct-v1/generation-plan.json').read_text())
records=[]
for state in plan['targets']:
    files=sorted((root/'state-direct-v1'/state).glob('[0-9][0-9].png'))
    if not files: continue
    unique={hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
    pixels={hashlib.sha256(Image.open(f).convert('RGBA').tobytes()).hexdigest() for f in files}
    if len(unique)!=len(files) or len(pixels)!=len(files): raise ValueError('duplicate '+state)
    for theme,bg in [('dark','#181827'),('white','#fffdf8')]:
        board=Image.new('RGB',(896,340*math.ceil(len(files)/4)),bg)
        for i,file in enumerate(files):
            im=Image.open(file).convert('RGBA');im.thumbnail((224,320))
            x,y=i%4*224,i//4*340
            board.paste(im,(x+(224-im.width)//2,y+(320-im.height)//2),im)
            ImageDraw.Draw(board).text((x+5,y+320),state+' '+file.stem,fill='white' if theme=='dark' else 'black')
        board.save(root/'review'/f'state-{state}-{len(files)}-{theme}.jpg',quality=95)
    records.append({'state':state,'drawings':len(files),'sourceUnique':len(unique),'decodedUnique':len(pixels),'files':[str(f.relative_to(root)) for f in files],'anatomyReview':'pending','originalRegistration':'not certified','loopReview':'pending'})
(root/'state-direct-v1/source-validation.json').write_text(json.dumps(records,indent=2)+'\n')
print([(r['state'],r['drawings']) for r in records])
