"""Read-only style comparison at 224x320; never an atlas or registration source."""
from pathlib import Path
import argparse,hashlib,json
from PIL import Image,ImageDraw,ImageFont
r=Path(__file__).resolve().parent
font='/System/Library/Fonts/AppleSDGothicNeo.ttc'
W,H=224,320
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',default='anchors/idle-heart-hana-material-v8-source.png')
parser.add_argument('--version',default='v8')
parser.add_argument('--anatomy',default='two actual forelegs visible; seated rear legs occluded by torso and skirt')
args=parser.parse_args()
source_paths=[r/'reference/hana-material-reference.png',r/args.source]
images=[]
for p in source_paths:
 im=Image.open(p).convert('RGBA')
 im.thumbnail((W,H),Image.Resampling.LANCZOS)
 cell=Image.new('RGBA',(W,H)); cell.alpha_composite(im,((W-im.width)//2,(H-im.height)//2)); images.append(cell)
ran=Image.open(r/'reference/ran-neutral-source.png').convert('RGBA')
ran=ran.crop(ran.getchannel('A').point(lambda a:255 if a>8 else 0).getbbox())
ran.thumbnail((44,44),Image.Resampling.LANCZOS)
images[1].alpha_composite(ran,(174,113))
board=Image.new('RGB',(976,406),'#f9f7f3'); d=ImageDraw.Draw(board)
f=ImageFont.truetype(font,16); small=ImageFont.truetype(font,13)
for col,(label,im) in enumerate([('하나 기준 · 밝은 배경',images[0]),('아무 수정 · 밝은 배경',images[1]),('하나 기준 · 어두운 배경',images[0]),('아무 수정 · 어두운 배경',images[1])]):
 x=16+col*240; d.text((x,13),label,fill='#403a3d',font=f)
 bg=Image.new('RGBA',(W,H),'#fffdfa' if col<2 else '#23232d'); bg.alpha_composite(im)
 board.paste(bg.convert('RGB'),(x,45))
d.text((16,378),'224×320 표시 비교 · 의상/재질 후보 검토용 · 원본 등록 및 동작 검증 전',fill='#76636e',font=small)
output=r/f'material-review-{args.version}-1x.png'
board.save(output)
(r/f'material-review-{args.version}.json').write_text(json.dumps({'kind':'material-comparison-only','display_cell':[W,H],'production_ready':False,'registration_certified':False,'reference_and_candidate':[{'path':str(p.relative_to(r)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in source_paths],'ran_source_preserved':True,'visual_review':{'fur':'candidate follows Hana short soft flocked-fur material reference','fabric':'matte felt reference applies to all current outfit pieces','shine':'satin/plastic ribbon highlights removed; natural eye highlights retained','anatomy':args.anatomy,'pending':['original and Hana profile measurements','source alpha-edge fragments and cell margin','all-pose four-limb review','actual motion and native rendering']}},ensure_ascii=False,indent=2)+'\n')
print(output)
