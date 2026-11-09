"""Keep current GIFs together, preserving each state's physical clock."""
from pathlib import Path
import json,hashlib,re,subprocess,sys,math
from PIL import Image,ImageDraw,ImageFont,ImageOps
ROOT=Path(__file__).resolve().parent
NAMES={'idle':'기본 대기','running':'오르골 감상','waiting':'입력 대기','failed':'위로','waving':'작업 완료','jumping':'점프 · 윙크','sleeping':'수면'}
FONT='/System/Library/Fonts/AppleSDGothicNeo.ttc'
font=ImageFont.truetype(FONT,16);title=ImageFont.truetype(FONT,23)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    lock=json.loads((ROOT/'pre-edit-lock.json').read_text());states=list(lock);movies={};steps={};runtime={}
    for state in states:
        v=json.loads((ROOT/state/'validation.json').read_text());assert v['render_code_sha256']==sha(ROOT/'render.py')
        assert sha(Path(lock[state]['character']))==lock[state]['character_sha256']
        ims=[]
        with Image.open(ROOT/state/'night.webp') as im:
            for i in range(im.n_frames):
                im.seek(i);im.load();tile=Image.new('RGBA',(224,224));f=ImageOps.contain(im.convert('RGBA'),(224,224),Image.Resampling.LANCZOS);tile.alpha_composite(f,((224-f.width)//2,(224-f.height)//2));ims.append(tile)
            steps[state]=im.info['duration']
        movies[state]=ims
        for bg,label in [('#10182a','dark'),('#edf0f5','light')]:
            board=Image.new('RGBA',(896,992),bg);d=ImageDraw.Draw(board)
            for i in range(16):
                idx=round(i*lock[state]['cycle_ms']/16/steps[state]);x=i%4*224;y=i//4*248;board.alpha_composite(ims[idx],(x,y));d.text((x+6,y+225),str(i),font=font,fill='#a08b6c')
            board.convert('RGB').save(ROOT/state/f'runtime-{label}.png')
    frames=[]
    for ms in range(0,19200,100):
        board=Image.new('RGBA',(960,570),'#10182a');d=ImageDraw.Draw(board);d.text((16,10),'천사 레토 · 타토의 청빛 & 멜로디의 장밋빛',font=title,fill='#f4e5c5')
        for i,state in enumerate(states):
            x=i%4*240+8;y=i//4*260+50;d.text((x+6,y),NAMES[state],font=font,fill='#d5c6af');board.alpha_composite(movies[state][(ms//steps[state])%len(movies[state])],(x,y+24))
        d.text((740,360),'타토 · 푸른 방울과 별빛',font=font,fill='#66caff');d.text((740,390),'멜로디 · 붉은 하트와 깃털',font=font,fill='#ff6d8f')
        frames.append(board.convert('RGB'))
    frames[0].save(ROOT/'overview.gif',save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=1,optimize=True)
    frames[8].save(ROOT/'overview.png')
    total=0
    with Image.open(ROOT/'overview.gif') as im:
        for i in range(im.n_frames):im.seek(i);total+=im.info['duration']
        assert total==19200
    print({'overview_frames':len(frames),'cycle_ms':total})
if __name__=='__main__':main()
