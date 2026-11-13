"""Gentle continuous clear tears and airborne companion comfort effects."""
from pathlib import Path
import importlib.util,json,hashlib,math
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('angel_helpers',ROOT.parent/'idle-v3-airborne-20261106/render.py')
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
night=helper.night;SIZE=(544,544);POSE=200;STEP=50;CYCLE=3200
BLUE=(102,202,255);RED=(255,109,143)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def at(records,ms,key):return records[int((ms%CYCLE)//POSE)]['attachment_proxies'][key]
def blocked(stream,birth):
    i=int((birth%CYCLE)//POSE)
    return (stream=='main_left' and i in [3,4,5]) or (stream=='main_right' and i in [10,11,12])
def effects(ms,records):
    ms%=CYCLE;t=ms/CYCLE;phase=math.tau*t
    back=night.opacity(night.night_atmosphere(ms,SIZE,CYCLE),.65);front=Image.new('RGBA',SIZE)
    night.stamp(back,night.crescent(46),(382,107+2*math.sin(phase)),46,.42,-18+3*math.sin(phase))
    for key,color,side in [('tato_magic_emitter',BLUE,-1),('melody_magic_emitter',RED,1)]:
        for age in [0,150,300,450]:
            q=age/600;x,y=at(records,ms-age,key)
            helper.stamp(back,'star' if side<0 else 'heart',(x+side*(5+17*q),y+24*q),15 if side<0 else 12,color,.55*(1-q)**1.4,side*12*q)
        x,y=at(records,ms,key);q=(t*2)%1
        helper.stamp(front,'star' if side<0 else 'heart',(x+side*10,y+8+20*q),13 if side<0 else 10,color,.38+.22*math.sin(math.pi*q)**2)
    for j in range(4):
        q=(t+j/4)%1;night.stamp(back,helper.FEATHER,(42+j*145+7*math.sin(math.tau*q+j),100+325*q),18,.23*math.sin(math.pi*q)**2,16*math.sin(phase+j),halo=False)
    return helper.edge(back),helper.edge(front)
def droplet(size,alpha):
    w=size*3;h=round(size*1.6)*3;im=Image.new('RGBA',(w,h));d=ImageDraw.Draw(im)
    d.polygon([(w*.5,0),(w*.15,h*.5),(w*.85,h*.5)],fill=(169,220,246,round(145*alpha)))
    d.ellipse((w*.12,h*.3,w*.88,h*.96),fill=(169,220,246,round(145*alpha)),outline=(225,248,255,round(200*alpha)),width=2)
    d.ellipse((w*.23,h*.46,w*.41,h*.68),fill=(255,255,255,round(230*alpha)))
    return im.resize((size,round(size*1.6)),Image.Resampling.LANCZOS)
def tears(ms,records,only=None):
    layers=Image.new('RGBA',SIZE);counts={};names=['main_left','main_right','tato','melody'];offsets=[0,400,200,600]
    current=records[int((ms%CYCLE)//POSE)]['attachment_proxies']
    for stream,offset in zip(names,offsets):
        if only is not None and stream!=only:continue
        age=(ms-offset)%800;birth=ms-age
        if blocked(stream,birth):counts[stream]=0;continue
        q=age/800;root=at(records,birth,'tear_roots')[stream]['xy'];side=-1 if stream in ['main_left','tato'] else 1
        x=root[0]+side*(2+5*q);y=root[1]+5+64*q
        a=math.sin(math.pi*q)**.85*.85;drop=droplet(6 if stream.startswith('main') else 5,a)
        layer=Image.new('RGBA',SIZE);layer.alpha_composite(drop,(round(x-drop.width/2),round(y)))
        # Art already contains the wet lower-eye streaks. Moving beads only
        # appear below the current nose/collar level, protecting iris/dot glyphs
        # even if a flying head moves beneath an older detached tear.
        floor=current['main_nose'][1]+7 if stream.startswith('main') else (current['tato_bell'][1]-20 if stream=='tato' else current['melody_bow_ribbon_proxy'][1]-10)
        safe=Image.new('L',SIZE);ImageDraw.Draw(safe).rectangle((0,math.ceil(floor),543,543),fill=255)
        layer.putalpha(ImageChops.multiply(layer.getchannel('A'),safe));layers.alpha_composite(layer)
        counts[stream]=int(np.count_nonzero(np.asarray(layer.getchannel('A'))))
    return helper.edge(layers),counts
def compose(ms,char,records):
    back,front=effects(ms,records);out=helper.compose(back,char,front);water,counts=tears(ms,records)
    before=np.asarray(out);out.alpha_composite(water);after=np.asarray(out)
    protected=np.asarray(water.getchannel('A'))==0
    assert np.array_equal(before[protected],after[protected]),'changed outside clear-tear particles'
    return out,counts
def main():
    records=json.loads((ROOT/'sources.json').read_text());chars=[Image.open(ROOT/r['path']).convert('RGBA') for r in records]
    assert len(chars)==16 and all(sha(ROOT/r['path'])==r['sha256'] for r in records)
    frames=[];dark=[];hashes=[];stream_pixels={k:0 for k in ['main_left','main_right','tato','melody']}
    for ms in range(0,CYCLE,STEP):
        f,c=compose(ms,chars[ms//POSE],records);assert night.border_max(f.getchannel('A'))==0
        frames.append(f);hashes.append(hashlib.sha256(f.tobytes()).hexdigest())
        for k,v in c.items():stream_pixels[k]+=v
        b=Image.new('RGBA',SIZE,'#10182a');b.alpha_composite(f);dark.append(b.convert('RGB'))
    assert len(set(hashes))==64 and all(v>0 for v in stream_pixels.values())
    a,_=compose(0,chars[0],records);b,_=compose(CYCLE,chars[0],records);assert a.tobytes()==b.tobytes()
    a,_=compose(700,chars[3],records);b,_=compose(750,chars[3],records);assert a.tobytes()!=b.tobytes()
    _,left=tears(900,records,only='main_left');_,right=tears(2100,records,only='main_right')
    assert left['main_left']==right['main_right']==0,'fresh tears continued during wiping'
    night.save_webp(frames,ROOT/'review/night.webp',STEP)
    dark[0].save(ROOT/'review/failed.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2);frames[12].save(ROOT/'review/preview.png')
    for bg,label in [('#10182a','dark'),('#edf0f5','light')]:
        board=Image.new('RGB',(896,992),bg);d=ImageDraw.Draw(board)
        for i in range(16):
            t=Image.new('RGBA',SIZE,bg);t.alpha_composite(frames[i*4]);x=i%4*224;y=i//4*248;board.paste(t.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));d.text((x+6,y+228),str(i),fill='#b9a37f')
        board.save(ROOT/'review'/f'effect-runtime-{label}.png')
    report={'independent_character_drawings':16,'pose_ms':POSE,'effect_ms':STEP,'cycle_ms':CYCLE,'distinct_effect_samples':64,'periodic_loop':True,'frozen_pose_effect_progression':True,'fresh_tears_paused_on_wiped_side':True,'all4_tear_streams_visible_pixel_sum':stream_pixels,'character_sources_unchanged':True,'edge_alpha_max':0,'native_installed':False,'media':{}}
    for name in ['character.webp','character.gif','night.webp','failed.gif']:
        total=0;unique=set()
        with Image.open(ROOT/'review'/name) as im:
            for i in range(im.n_frames):
                im.seek(i);im.load();total+=im.info['duration'];unique.add(hashlib.sha256(im.convert('RGBA').tobytes()).hexdigest())
            assert total==CYCLE
            if name=='character.webp':assert len(unique)==16
            report['media'][name]={'frames':im.n_frames,'cycle_ms':total,'sha256':sha(ROOT/'review'/name)}
    (ROOT/'review/media-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
if __name__=='__main__':main()
