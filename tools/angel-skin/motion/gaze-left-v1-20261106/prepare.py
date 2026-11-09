from pathlib import Path
import importlib.util,hashlib,json
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('idle_prepare',ROOT.parent/'idle-v5-canonical-20261106/prepare.py');M=importlib.util.module_from_spec(s);s.loader.exec_module(M)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def one(i):
 p=ROOT/'raw'/f'{i:02}-repair.png'
 if not p.exists():p=ROOT/'raw'/f'{i:02}.png'
 raw=Image.open(p).convert('RGBA');assert raw.width==raw.height
 im,n=M.clean(raw);ground=M.support(im);dy=484-ground;assert abs(dy)<40,(i,dy)
 out=Image.new('RGBA',(544,544));out.alpha_composite(im,(0,dy));assert M.support(out)==484
 dest=ROOT/'character'/f'{i:02}.png';out.save(dest)
 return out,{'id':f'{i:02}','path':f'character/{i:02}.png','sha256':sha(dest),'raw_sha256':sha(p),'prompt_sha256':sha(ROOT/'prompts'/(f'{i:02}-repair.txt' if (ROOT/'prompts'/f'{i:02}-repair.txt').exists() else f'{i:02}.txt')),'independent_complete_drawing':True,'no_head_body_assembly':True,'whole_character_translation':[0,dy],'support_proxy_y':484,'attachment_proxies':M.landmarks(out,i),'anatomical_landmarks':'unverified; support proxy is not original-body certification','removed_detached_dust_pixels':n}
def board(frames,path,color):
 b=Image.new('RGB',(896,992),color);d=ImageDraw.Draw(b)
 for i,f in enumerate(frames):
  c=Image.new('RGBA',f.size,color);c.alpha_composite(f);x=i%4*224;y=i//4*248;b.paste(c.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));d.text((x+5,y+225),str(i),fill='#a99572')
 b.save(path)
def main():
 fs=[];rs=[]
 for i in range(16):f,r=one(i);fs.append(f);rs.append(r)
 fs[0].save(ROOT/'review/character.webp',save_all=True,append_images=fs[1:],duration=200,loop=0,lossless=True,exact=True,method=4)
 (ROOT/'sources.json').write_text(json.dumps(rs,indent=2)+'\n')
 for label,color in [('dark','#10182a'),('light','#edf0f5')]:board(fs,ROOT/'review'/f'character-{label}.png',color)
if __name__=='__main__':main()
