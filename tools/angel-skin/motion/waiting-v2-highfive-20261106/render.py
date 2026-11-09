"""Two contact-triggered high-five bursts plus continuous airborne companion wakes."""
from pathlib import Path
import importlib.util,json,hashlib,math
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('idle_helpers',ROOT.parent/'idle-v3-airborne-20261106/render.py')
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
night=helper.night;SIZE=(544,544);POSE=200;STEP=50;CYCLE=3200
BLUE=(102,202,255);RED=(255,109,143)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def at(records,ms,key):return records[int((ms%CYCLE)//POSE)]['attachment_proxies'][key]
def effects(ms,records,contacts):
    ms%=CYCLE;t=ms/CYCLE;phase=math.tau*t
    back=night.opacity(night.night_atmosphere(ms,SIZE,CYCLE),.75);front=Image.new('RGBA',SIZE)
    night.stamp(back,night.crescent(50),(382,113+3*math.sin(phase)),50,.48,-18+4*math.sin(phase))
    for actor,key,color,side in [('Tato','tato_magic_emitter',BLUE,-1),('Melody','melody_magic_emitter',RED,1)]:
        for age in [0,100,200,300,400]:
            q=age/500;px,py=at(records,ms-age,key);kind='star' if side<0 else ('heart' if age%200==0 else 'feather')
            helper.stamp(back,kind,(px+side*(4+18*q),py+22*q),18 if kind!='feather' else 22,color,(1-q)**1.5*.85,side*(10+30*q))
        ex,ey=at(records,ms,key);q=(t*2)%1
        helper.stamp(front,'star' if side<0 else 'heart',(ex+side*12,ey-18-22*q),18 if side<0 else 14,color,.6+.3*math.sin(math.pi*q)**2)
    # No contact flash before the actual palms meet. Bursts follow the measured
    # joined paws during contact, then keep their last birthplace on release.
    for event in contacts['events']:
        age=ms-event['start_ms']
        if age<0 or age>=650:continue
        q=age/650;points=event['points'];current=points[min(int(age//POSE),len(points)-1)]
        x,y=current;color=BLUE if event['actor']=='Tato' else RED
        strength=(1-q)**.8;radius=10+32*q
        glow=Image.new('RGBA',SIZE);d=ImageDraw.Draw(glow)
        d.ellipse((x-radius,y-radius,x+radius,y+radius),fill=(*color,round(75*strength)))
        back.alpha_composite(glow.filter(ImageFilter.GaussianBlur(10)))
        ring=Image.new('RGBA',SIZE);d=ImageDraw.Draw(ring)
        d.ellipse((x-radius,y-radius,x+radius,y+radius),outline=(*color,round(185*strength)),width=2)
        back.alpha_composite(ring.filter(ImageFilter.GaussianBlur(2)));back.alpha_composite(ring)
        for j in range(6):
            angle=j*math.tau/6+q*.55;r=18+31*q
            helper.stamp(front,'star' if event['actor']=='Tato' else ('heart' if j%2==0 else 'star'),(x+r*math.cos(angle),y+r*math.sin(angle)),round(10+5*strength),color,.95*strength,j*12)
    for j in range(4):
        q=(t+j/4)%1;night.stamp(back,helper.FEATHER,(42+j*145+9*math.sin(math.tau*q+j),110+320*q),18,.27*math.sin(math.pi*q)**2,20*math.sin(phase+j),halo=False)
    return helper.edge(back),helper.edge(front)
def compose(back,char,front,ms,contacts):
    out=helper.compose(back,char,front);allowed=Image.new('L',SIZE);mask=ImageDraw.Draw(allowed)
    # A restrained local glint may illuminate the touching pads. The reviewed
    # small disks avoid the main face and both companions' eye glyphs.
    for event in contacts['events']:
        age=ms%CYCLE-event['start_ms']
        if age<0 or age>=650:continue
        q=age/650;x,y=event['points'][min(int(age//POSE),len(event['points'])-1)]
        color=BLUE if event['actor']=='Tato' else RED;strength=(1-q)**1.2
        local=Image.new('RGBA',SIZE);draw=ImageDraw.Draw(local)
        draw.ellipse((x-19,y-19,x+19,y+19),fill=(*color,round(54*strength)))
        local=local.filter(ImageFilter.GaussianBlur(4))
        helper.stamp(local,'star',(x,y),18,color,.95*strength)
        limit=Image.new('L',SIZE);ImageDraw.Draw(limit).ellipse((x-24,y-24,x+24,y+24),fill=255)
        local.putalpha(ImageChops.multiply(local.getchannel('A'),limit));out.alpha_composite(local)
        mask.ellipse((x-24,y-24,x+24,y+24),fill=255)
    a=np.asarray(char);b=np.asarray(out);protected=(a[:,:,3]==255)&(np.asarray(allowed)==0)
    assert np.array_equal(a[protected],b[protected]),'character changed outside allowed pad-contact light'
    return out
def main():
    records=json.loads((ROOT/'sources.json').read_text());contacts=json.loads((ROOT/'contacts.json').read_text())
    chars=[Image.open(ROOT/r['path']).convert('RGBA') for r in records]
    assert len(chars)==16 and all(sha(ROOT/r['path'])==r['sha256'] for r in records)
    full=[];dark=[];fxhash=[]
    for ms in range(0,CYCLE,STEP):
        back,front=effects(ms,records,contacts);frame=compose(back,chars[ms//POSE],front,ms,contacts)
        assert night.border_max(frame.getchannel('A'))==0
        full.append(frame);fxhash.append(hashlib.sha256(back.tobytes()+front.tobytes()).hexdigest())
        bg=Image.new('RGBA',SIZE,'#10182a');bg.alpha_composite(frame);dark.append(bg.convert('RGB'))
    assert len(set(fxhash))==64
    a,b=effects(0,records,contacts);c,d=effects(CYCLE,records,contacts);assert a.tobytes()==c.tobytes() and b.tobytes()==d.tobytes()
    night.save_webp(full,ROOT/'review/night.webp',STEP)
    dark[0].save(ROOT/'review/waiting.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2)
    full[12].save(ROOT/'review/preview.png')
    for color,label in [('#10182a','dark'),('#edf0f5','light')]:
        board=Image.new('RGB',(896,992),color);draw=ImageDraw.Draw(board)
        for i in range(16):
            tile=Image.new('RGBA',SIZE,color);tile.alpha_composite(full[i*4]);x=i%4*224;y=i//4*248
            board.paste(tile.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));draw.text((x+6,y+228),str(i),fill='#b9a37f')
        board.save(ROOT/'review'/f'effect-runtime-{label}.png')
    frozen=[]
    for ms in [700,750]:
        back,front=effects(ms,records,contacts);frozen.append(hashlib.sha256(compose(back,chars[3],front,ms,contacts).tobytes()).hexdigest())
    assert len(set(frozen))==2
    contact_checks=[]
    for event in contacts['events']:
        results=[]
        for offset in [-50,100]:
            ms=event['start_ms']+offset
            a,b=effects(ms,records,contacts);visible=compose(a,chars[ms//POSE],b,ms,contacts)
            a,b=effects(ms,records,{'events':[]});without=compose(a,chars[ms//POSE],b,ms,{'events':[]})
            count=int(np.any(np.asarray(visible)!=np.asarray(without),axis=2).sum());results.append(count)
        assert results[0]==0 and results[1]>20,(event['actor'],results)
        contact_checks.append({'actor':event['actor'],'visible_burst_pixels_before_touch':results[0],'visible_burst_pixels_after_touch':results[1]})
    report={'distinct_character_drawings':16,'pose_ms':POSE,'cycle_ms':CYCLE,'effect_ms':STEP,'distinct_effect_samples':64,'periodic_effects':True,'effects_advance_on_frozen_pose':True,'edge_alpha_max':0,'opaque_character_RGBA_preserved_outside_contact_light':True,'allowed_contact_light_radius_px':24,'contact_burst_starts_ms':[e['start_ms'] for e in contacts['events']],'contact_visibility_checks':contact_checks,'native_installed':False,'media':{}}
    for name in ['character.webp','character.gif','night.webp','waiting.gif']:
        total=0;unique=set()
        with Image.open(ROOT/'review'/name) as im:
            for j in range(im.n_frames):
                im.seek(j);im.load();total+=im.info['duration'];unique.add(hashlib.sha256(im.convert('RGBA').tobytes()).hexdigest())
                if name.endswith('webp'):assert night.border_max(im.convert('RGBA').getchannel('A'))==0
            assert total==CYCLE
            if name=='character.webp':assert len(unique)==16
            report['media'][name]={'frames':im.n_frames,'cycle_ms':total,'sha256':sha(ROOT/'review'/name)}
    (ROOT/'review/media-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
if __name__=='__main__':main()
