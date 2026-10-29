from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,sys
ROOT=Path(__file__).resolve().parent.parent
source=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'native/native-white-1x.png'
board=Image.open(source).convert('RGB');poster=Image.new('RGB',(1200,900),'white');draw=ImageDraw.Draw(poster);fontpath='/System/Library/Fonts/AppleSDGothicNeo.ttc';font=ImageFont.truetype(fontpath,13);title=ImageFont.truetype(fontpath,21);badge=ImageFont.truetype(fontpath,14);note=ImageFont.truetype(fontpath,11)
draw.text((20,15),'아무 · 란 — 상태별 동작과 이펙트',font=title,fill='#51444d')
config=json.loads((ROOT/'review-config.json').read_text());indices=[0,8,9,5,6,4,3,1,2,7]
for i,(state,index) in enumerate(zip(config,indices)):
 x=i%5*240;y=54+i//5*410;label=state['stateTitle'];width=draw.textbbox((0,0),label,font=badge)[2]+20;draw.rounded_rectangle((x+8,y+3,x+8+width,y+29),radius=13,fill='#ffe5ef');draw.text((x+18,y+7),label,font=badge,fill='#a82e60');draw.text((x+8,y+37),state['label'],font=font,fill='#51444d');draw.text((x+8,y+59),state['stateNote'],font=note,fill='#80737b')
 cell=board.crop((index%4*224,index//4*320,(index%4+1)*224,(index//4+1)*320));poster.paste(cell,(x+8,y+83))
poster.save(ROOT/'preview-poster.png')
print('Current native1x result with10 explicit state labels saved')
