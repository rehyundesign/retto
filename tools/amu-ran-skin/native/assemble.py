"""Package only reviewed independent cells; atlas is assembled, never sliced from a sheet."""
from pathlib import Path
from PIL import Image
import json,hashlib,shutil
import numpy as np
root=Path(__file__).resolve().parent.parent;repo=root.parents[1]
config=json.loads((root/'review-config.json').read_text());dest=repo/'assets/amu-ran-frames';dest.mkdir(exist_ok=True)
atlas=Image.new('RGBA',(7168,7680));records=[]
def copy(source,name,expected):
    im=Image.open(source).convert('RGBA');assert im.size==expected,(source,im.size)
    target=dest/(name+'.png');shutil.copy2(source,target)
    records.append({'source':str(source.relative_to(repo)),'destination':str(target.relative_to(repo)),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
for item in config:
    r=root/item['path'];hashes=[]
    for i in range(16):
        p=r/'character'/f'F{i:02}.png';im=Image.open(p).convert('RGBA');hashes.append(hashlib.sha256(im.tobytes()).hexdigest())
        copy(p,f"character-{item['row']}-{i}",(448,640));atlas.alpha_composite(im,(i*448,item['row']*640))
    assert len(set(hashes))==16,item['id']
    for layer in ['back','front']:
        for i in range(80):copy(r/('effect_'+layer)/f'{i:03}.png',f"{layer}-{item['row']}-{i}",(448,640))
for costume,row in [('school',9),('heart',10)]:
    for i in range(16):
        p=root/'motion'/f'gaze-{costume}-v2/character/G{i:02}.png';copy(p,f'gaze-{costume}-{i}',(448,640));atlas.alpha_composite(Image.open(p).convert('RGBA'),(i*448,row*640))
for pose,directory in [('cheer','idle-v2'),('sleep','sleeping-v1')]:
    for i in range(8):copy(root/'motion'/directory/'companion'/f'R{i:02}.png',f'companion-{pose}-{i}',(90,90))
for side in ['left','right']:
    for i in range(8):copy(root/'motion'/f'ran-interaction-{side}-v1/character/R{i:02}.png',f'companion-{side}-{i}',(90,90))
atlas.save(repo/'assets/spritesheet-amu-ran.webp',lossless=True,method=6)
assert len(records)==1824
source=root/'interaction/plan.json';target=dest/'interaction.json';shutil.copy2(source,target)
records.append({'source':str(source.relative_to(repo)),'destination':str(target.relative_to(repo)),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
(root/'native/resources.json').write_text(json.dumps({'cell_dimensions':[448,640],'atlas_dimensions':[7168,7680],'character_cells':160,'gaze_cells':32,'effect_cells':1600,'companion_cells':32,'data_files':1,'installed':False,'files':records},indent=2)+'\n')
print('Assembled192 character/gaze +1600 effects +32 companions +1 interaction plan; no installation')
