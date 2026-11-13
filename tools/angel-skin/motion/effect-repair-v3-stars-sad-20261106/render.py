"""Repair two existing effects; every approved character drawing remains exact."""
from pathlib import Path
import importlib.util,json,hashlib,math
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops,ImageFont
ROOT=Path(__file__).resolve().parent;SIZE=(544,544);CYCLE=3200;STEP=50
NAMES={'waiting':'waiting-v2-highfive-20261106','failed':'failed-v2-tears-20261106'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def module(state):
    p=ROOT.parent/NAMES[state]/'render.py';s=importlib.util.spec_from_file_location('original_'+state,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
WAIT=module('waiting');SAD=module('failed');H=WAIT.helper;N=WAIT.night
GOLD=(255,216,77);PALE=(255,245,189)
def five_star(size,alpha,angle=0):
    s=size*3;im=Image.new('RGBA',(s,s));d=ImageDraw.Draw(im);points=[]
    for j in range(10):
        a=-math.pi/2+j*math.pi/5;r=s*(.44 if j%2==0 else .2);points.append((s/2+r*math.cos(a),s/2+r*math.sin(a)))
    d.polygon(points,fill=(*GOLD,round(255*alpha)),outline=(*PALE,round(245*alpha)),width=2)
    d.line((s*.4,s*.34,s*.48,s*.26),fill=(255,255,235,round(220*alpha)),width=2)
    im=im.resize((size,size),Image.Resampling.LANCZOS)
    return im.rotate(angle,Image.Resampling.BICUBIC,expand=True) if angle else im
def gold_stamp(layer,xy,size,alpha,angle=0):
    im=five_star(size,alpha,angle);x=round(xy[0]-im.width/2);y=round(xy[1]-im.height/2)
    glow=Image.new('RGBA',SIZE);g=Image.new('RGBA',im.size,(*GOLD,0));g.putalpha(im.getchannel('A').point(lambda a:round(a*.4)));glow.alpha_composite(g,(x,y));layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(4)));layer.alpha_composite(im,(x,y))
def face_mask(char,rec):
    a=np.asarray(char).astype(int);r,g,b,al=[a[:,:,i] for i in range(4)];yy,xx=np.indices(al.shape)
    pink=(r>180)&(r-g>35)&(b-g>0)&(al>200)&(xx>185)&(xx<335)&(yy>180)&(yy<270)
    ys,xs=np.nonzero(pink);nx=float(xs.mean()) if len(xs) else 255;ny=float(ys.mean()) if len(ys) else 225
    mask=Image.new('L',SIZE);d=ImageDraw.Draw(mask)
    d.ellipse((nx-91,ny-82,nx+91,ny+44),fill=255)
    bell=rec['attachment_proxies']['tato_bell'];bow=rec['attachment_proxies']['melody_bow']
    d.ellipse((bell[0]-47,bell[1]-96,bell[0]+47,bell[1]-12),fill=255)
    d.ellipse((bow[0]-81,bow[1]-102,bow[0]+49,bow[1]-10),fill=255)
    return mask
def gold_burst(ms,contacts,char,rec):
    layer=Image.new('RGBA',SIZE);faces=face_mask(char,rec);allowed=Image.new('L',SIZE)
    for event in contacts['events']:
        age=ms%CYCLE-event['start_ms']
        if not 0<=age<650:continue
        q=age/650;x,y=event['points'][min(int(age//200),len(event['points'])-1)];strength=(1-q)**.7
        gold_stamp(layer,(x,y),round(32-9*q),strength,12*math.sin(q*math.pi))
        ImageDraw.Draw(allowed).ellipse((x-16,y-16,x+16,y+16),fill=255)
        # A readable downward fan leaves the faces clear and follows the slap.
        for j in range(5):
            a=math.radians(28+j*31);distance=20+52*q
            gold_stamp(layer,(x+distance*math.cos(a),y+14+distance*math.sin(a)),round((19 if j%2 else 24)*(1-.35*q)),strength*.93,(j-2)*14+55*q)
        rays=Image.new('RGBA',SIZE);d=ImageDraw.Draw(rays)
        for j in [-1,0,1]:
            dx=j*22;d.line((x+dx*.65,y-12,x+dx,y-24-8*q),fill=(*PALE,round(210*strength)),width=2)
        layer.alpha_composite(rays)
    protect=ImageChops.subtract(faces,allowed);layer.putalpha(ImageChops.multiply(layer.getchannel('A'),ImageChops.invert(protect)))
    return H.edge(layer),protect
def waiting(ms,char,records,contacts):
    ms%=CYCLE
    back,front=WAIT.effects(ms,records,{'events':[]});base=WAIT.helper.compose(back,char,front)
    burst,protected=gold_burst(ms,contacts,char,records[ms//200]);before=base.copy();base.alpha_composite(burst)
    assert all(ImageChops.multiply(c,protected).getbbox() is None for c in ImageChops.difference(before,base).split()),'gold covered protected face'
    return base,burst
def stronger_tears(ms,records):
    # Reuse exact birth clocks, per-frame roots and current eye-level masks.
    layer=Image.new('RGBA',SIZE);current=records[(ms%CYCLE)//200]['attachment_proxies'];counts={}
    for stream,offset in zip(['main_left','main_right','tato','melody'],[0,400,200,600]):
        age=(ms-offset)%800;birth=ms-age
        if SAD.blocked(stream,birth):counts[stream]=0;continue
        q=age/800;root=SAD.at(records,birth,'tear_roots')[stream]['xy'];side=-1 if stream in ['main_left','tato'] else 1
        x=root[0]+side*(2+7*q);y=root[1]+5+83*q
        im=SAD.droplet(10 if stream.startswith('main') else 8,math.sin(math.pi*q)**.75*.98)
        drop=Image.new('RGBA',SIZE);drop.alpha_composite(im,(round(x-im.width/2),round(y)))
        floor=current['main_nose'][1]+7 if stream.startswith('main') else(current['tato_bell'][1]-20 if stream=='tato' else current['melody_bow_ribbon_proxy'][1]-10)
        mask=Image.new('L',SIZE);ImageDraw.Draw(mask).rectangle((0,math.ceil(floor),543,543),fill=255);drop.putalpha(ImageChops.multiply(drop.getchannel('A'),mask))
        layer.alpha_composite(drop);counts[stream]=int(np.count_nonzero(np.asarray(drop.getchannel('A'))))
    return H.edge(layer),counts
def failed(ms,char,records):
    ms%=CYCLE
    back,front=SAD.effects(ms,records);t=ms%CYCLE/CYCLE
    # A soft blue veil, slow drizzle and falling feathers signal a quiet sob.
    veil=Image.new('RGBA',SIZE);d=ImageDraw.Draw(veil)
    d.ellipse((65,95,480,445),fill=(104,151,218,18));back.alpha_composite(H.edge(veil.filter(ImageFilter.GaussianBlur(48))))
    for j,x in enumerate([27,79,139,407,465,517]):
        q=(t*2+j/6)%1;im=SAD.droplet(9+(j%2)*2,.62*math.sin(math.pi*q)**2)
        front.alpha_composite(im,(round(x+4*math.sin(q*math.tau+j)),round(120+340*q)))
    for j,x in enumerate([29,151,397,516]):
        q=(t+j/4)%1;H.stamp(front,'feather',(x+5*math.sin(q*math.tau+j),95+370*q),29+(j%2)*3,(190,216,247),.58*math.sin(math.pi*q)**2,17*math.sin(q*math.tau+j))
    front=H.edge(front);base=H.compose(back,char,front);water,counts=stronger_tears(ms,records);base.alpha_composite(water)
    return base,water,counts
def save_board(frames,path,color):
    board=Image.new('RGB',(896,992),color);d=ImageDraw.Draw(board)
    for i in range(16):
        b=Image.new('RGBA',SIZE,color);b.alpha_composite(frames[i*4]);x=i%4*224;y=i//4*248;board.paste(b.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));d.text((x+6,y+228),str(i),fill='#b9a37f')
    board.save(path)
def main():
    results={};movies={}
    for state,name in NAMES.items():
        old=ROOT.parent/name;dest=ROOT/state;lock=json.loads((dest/'pre-edit-lock.json').read_text())
        assert sha(old/'render.py')==lock['renderer_sha256'] and sha(old/'sources.json')==lock['sources_sha256']
        records=json.loads((old/'sources.json').read_text());chars=[Image.open(old/r['path']).convert('RGBA') for r in records]
        assert all(sha(old/r['path'])==lock['source_sha256'][r['id']] for r in records)
        contacts=json.loads((old/'contacts.json').read_text()) if state=='waiting' else None
        frames=[];dark=[];checks=[];counts={k:0 for k in ['main_left','main_right','tato','melody']}
        for ms in range(0,CYCLE,STEP):
            if state=='waiting':f,delta=waiting(ms,chars[ms//200],records,contacts)
            else:
                f,delta,c=failed(ms,chars[ms//200],records)
                for k,v in c.items():counts[k]+=v
            assert N.border_max(f.getchannel('A'))==0;frames.append(f);checks.append(hashlib.sha256(delta.tobytes()).hexdigest())
            bg=Image.new('RGBA',SIZE,'#10182a');bg.alpha_composite(f);dark.append(bg.convert('RGB'))
        N.save_webp(frames,dest/'night.webp',STEP);dark[0].save(dest/f'{state}.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2)
        save_board(frames,dest/'runtime-dark.png','#10182a');save_board(frames,dest/'runtime-light.png','#edf0f5')
        assert sha(Path(lock['character_animation']['path']))==lock['character_animation']['sha256']
        assert sha(Path(lock['effect_animation']['path']))==lock['effect_animation']['sha256']
        with Image.open(dest/'night.webp') as im:
            total=0
            for i in range(im.n_frames):im.seek(i);im.load();total+=im.info['duration']
            assert im.n_frames==64 and total==CYCLE
        if state=='waiting':
            for e in contacts['events']:
                pre,_=gold_burst(e['start_ms']-50,contacts,chars[(e['start_ms']-50)//200],records[(e['start_ms']-50)//200]);assert pre.getbbox() is None
                post,_=gold_burst(e['start_ms']+100,contacts,chars[(e['start_ms']+100)//200],records[(e['start_ms']+100)//200]);assert np.count_nonzero(np.asarray(post.getchannel('A')))>2500
        else:
            assert all(v>0 for v in counts.values())
            _,c=stronger_tears(900,records);assert c['main_left']==0
            _,c=stronger_tears(2100,records);assert c['main_right']==0
        results[state]={'retained_character_drawings':16,'all_character_PNGs_and_animation_byte_identical':True,'prior_effect_animation_unchanged':True,'cycle_ms':CYCLE,'effect_ms':STEP,'edge_alpha_max':0,'source_sha256':lock['source_sha256'],'night_sha256':sha(dest/'night.webp'),'gif_sha256':sha(dest/f'{state}.gif'),'visible_tear_pixel_sum':counts if state=='failed' else None,'native_installed':False}
        (dest/'validation.json').write_text(json.dumps(results[state],indent=2)+'\n');movies[state]=dark
    # One finished review GIF shows both requested effect repairs together.
    frames=[];font=ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc',18)
    for i in range(64):
        b=Image.new('RGB',(672,378),'#10182a');d=ImageDraw.Draw(b)
        for j,(state,label) in enumerate([('waiting','입력 대기 · 노란 별 하이파이브'),('failed','실패 · 눈물과 쓸쓸한 달빛')]):
            d.text((j*336+14,12),label,font=font,fill='#e8e3d8');b.paste(movies[state][i].resize((336,336),Image.Resampling.LANCZOS),(j*336,42))
        frames.append(b)
    frames[0].save(ROOT/'review/effects.gif',save_all=True,append_images=frames[1:],duration=STEP,loop=0,disposal=2)
    (ROOT/'review/validation.json').write_text(json.dumps(results,indent=2)+'\n');print({s:{k:v for k,v in r.items() if k!='source_sha256'} for s,r in results.items()})
if __name__=='__main__':main()
