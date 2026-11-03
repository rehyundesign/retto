"""Assemble locked Retto and Ran sources; never redraw approved character art."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import argparse,hashlib,json
r=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--character-source',default='anchors/idle-heart-cape-pose-v9-source.png')
parser.add_argument('--ran-source',default='reference/ran-neutral-source.png')
parser.add_argument('--version',default='v9')
parser.add_argument('--ran-y',type=int,default=282)
args=parser.parse_args()
character_path=r/args.character_source
ran_path=r/args.ran_source
character_hash=hashlib.sha256(character_path.read_bytes()).hexdigest()
ran_hash=hashlib.sha256(ran_path.read_bytes()).hexdigest()
size=(448,640)
character=Image.open(character_path).convert('RGBA')
character.thumbnail(size,Image.Resampling.LANCZOS)
character_layer=Image.new('RGBA',size)
character_layer.alpha_composite(character,((size[0]-character.width)//2,(size[1]-character.height)//2))
ran=Image.open(ran_path).convert('RGBA')
ran_bounds=ran.getchannel('A').point(lambda a:255 if a>8 else 0).getbbox()
if ran_bounds is None:
 raise ValueError('Ran source is empty')
ran=ran.crop(ran_bounds)
ran.thumbnail((90,90),Image.Resampling.LANCZOS)
companion_layer=Image.new('RGBA',size)
position=(360,args.ran_y)
companion_layer.alpha_composite(ran,position)
scene=Image.alpha_composite(character_layer,companion_layer)
output=r/f'amu-ran-pet-{args.version}.png'
scene.save(output)
# Runtime-size light/dark review, isolated from final sprite sources.
board=Image.new('RGB',(496,380),'#faf7f9'); draw=ImageDraw.Draw(board)
font=ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc',14)
for i,(name,bg) in enumerate([('밝은 배경','#fffdfa'),('어두운 배경','#23232d')]):
 x=16+240*i
 draw.text((x,10),'아무 · 란 / '+name,font=font,fill='#5d4c56')
 cell=Image.new('RGBA',(224,320),bg)
 cell.alpha_composite(scene.resize((224,320),Image.Resampling.LANCZOS))
 board.paste(cell.convert('RGB'),(x,38))
review=r/f'pet-review-{args.version}-1x.png'
board.save(review)
assert hashlib.sha256(character_path.read_bytes()).hexdigest()==character_hash
assert hashlib.sha256(ran_path.read_bytes()).hexdigest()==ran_hash
report={
 'kind':'static-pet-composition','source_cell':[448,640],'runtime_display':[224,320],
 'character':{'path':str(character_path.relative_to(r)),'sha256':character_hash,'redrawn':False},
 'companion':{'path':str(ran_path.relative_to(r)),'sha256':ran_hash,'redrawn':False,'position_2x':list(position),'size_2x':list(ran.size)},
 'layers':['character','ran'],'source_hash_preservation':True,
 'candidate':output.name,'runtime_review':review.name,
 'animated':False,'production_ready':False,'installed':False,
 'visual_review':{'pose':'two central forelegs and two smaller outer rear paws visible; four limbs total','cape':'one broad shoulder/upper-chest mantle with pink lining and red edge','pendant':'single visibly suspended Guardian Egg','floor_pompons':'removed, including wrist loops','companion':'Ran floats beside shoulder, separate from visor/face/cape'},
 'remaining':['all static anchors','independent motion','gaze','effects','strict cell registration and native review']}
(r/f'pet-composition-{args.version}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('Composed Retto + selected Ran, source hashes unchanged: '+str(output))
