"""Add gentle moving light only inside the existing registered music-box dome."""
from pathlib import Path
import hashlib,json,math,importlib.util
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops
ROOT=Path(__file__).resolve().parent;OLD=ROOT.parent/'running-v3-proportion-20261105'
spec=importlib.util.spec_from_file_location('night',ROOT.parent/'night-effects-v1-20261105/render_night.py');night=importlib.util.module_from_spec(spec);spec.loader.exec_module(night)
SIZE=(544,544);CYCLE=3200;STEP=50
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dome_at(i):
    boxes=json.loads((OLD/'dome-landmarks.json').read_text());regs=json.loads((OLD/'review/media-validation.json').read_text())['whole_character_registration'];x,y,w,h=boxes[i];s=512/1254
    return (16+x*s,16+regs[i]['whole_character_y_px']+y*s,w*s,h*s)
def light(ms,dome):
    x,y,w,h=dome;t=ms%CYCLE/CYCLE;p=math.tau*t
    # Reviewed inner glass silhouette, excluding face, hands, base outline.
    mask=Image.new('L',SIZE);d=ImageDraw.Draw(mask);inset=5
    d.ellipse((x+inset,y+inset,x+w-inset,y+w-inset),fill=255)
    d.rectangle((x+inset,y+w/2,x+w-inset,y+h-4),fill=255)
    clip=Image.new('L',SIZE);ImageDraw.Draw(clip).rectangle((x+inset,y+inset,x+w-inset,y+h-4),fill=255)
    mask=ImageChops.multiply(mask,clip).filter(ImageFilter.GaussianBlur(.7))
    glow=Image.new('RGBA',SIZE);gd=ImageDraw.Draw(glow)
    colors=[(255,240,199),(198,233,255),(225,207,255)]
    for j,(cx,cy) in enumerate([(.36,.77),(.67,.7),(.52,.42)]):
        r=14+3*math.sin(p+j);a=round(22+12*math.sin(p+j)**2)
        px=x+cx*w;py=y+cy*h;gd.ellipse((px-r,py-r,px+r,py+r),fill=(*colors[j],a))
    glow=glow.filter(ImageFilter.GaussianBlur(7));stars=Image.new('RGBA',SIZE);sd=ImageDraw.Draw(stars)
    for j,(cx,cy) in enumerate([(.25,.33),(.72,.27),(.48,.53),(.28,.7),(.73,.65),(.52,.2)]):
        q=(t+j*.163)%1;s=math.sin(math.pi*q)**4;r=1.5+3.8*s
        px=x+w*(cx+.025*math.sin(p+j));py=y+h*(cy+.045*math.sin(p+j*.7));color=(*colors[j%3],round(200*s))
        sd.line((px-r,py,px+r,py),fill=color,width=1);sd.line((px,py-r,px,py+r),fill=color,width=1)
        sd.ellipse((px-1.3,py-1.3,px+1.3,py+1.3),fill=(255,252,238,round(200*s)))
    glow.alpha_composite(stars.filter(ImageFilter.GaussianBlur(2)));glow.alpha_composite(stars)
    # Tiny glints progress around the already rotating mirrored plate.
    sd=ImageDraw.Draw(glow)
    for j in range(3):
        a=p+j*math.tau/3;px=x+w/2+math.cos(a)*w*.33;py=y+h*.91+math.sin(a)*h*.035
        sd.ellipse((px-1.3,py-1.3,px+1.3,py+1.3),fill=(255,241,197,round(100*(.5+.5*math.sin(a)**2))))
    glow.putalpha(ImageChops.multiply(glow.getchannel('A'),mask));return glow,mask
def main():
    lock=json.loads((ROOT/'pre-edit-lock.json').read_text())
    assert sha(OLD/'dome-landmarks.json')==lock['dome_landmarks_sha256'];assert sha(OLD/'review/media-validation.json')==lock['registration_sha256']
    for ident,digest in lock['source_sha256'].items():assert sha(OLD/'character'/f'{ident}.png')==digest
    for key in ['character_animation','effect_animation']:assert sha(Path(lock[key]['path']))==lock[key]['sha256']
    movie=Image.open(lock['effect_animation']['path']);frames=[];dark=[];changes=[];hashes=[]
    for j,ms in enumerate(range(0,CYCLE,STEP)):
        movie.seek(j);movie.load();original=movie.convert('RGBA');layer,mask=light(ms,dome_at(ms//200))
        out=original.copy();out.alpha_composite(layer);out.putalpha(original.getchannel('A'))
        a=np.asarray(original);b=np.asarray(out);outside=np.asarray(mask)==0
        assert np.array_equal(a[outside],b[outside]);assert np.array_equal(a[:,:,3],b[:,:,3])
        changes.append(int(np.any(a!=b,axis=2).sum()));hashes.append(hashlib.sha256(layer.tobytes()).hexdigest());frames.append(out)
        bg=Image.new('RGBA',SIZE,'#10182a');bg.alpha_composite(out);dark.append(bg.convert('RGB'))
    assert len(set(hashes))==64 and min(changes)>0
    night.save_webp(frames,ROOT/'review/night.webp',STEP)
    dark[0].save(ROOT/'review/running.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2);frames[12].save(ROOT/'review/preview.png')
    for color,label in [('#10182a','dark'),('#edf0f5','light')]:
        board=Image.new('RGB',(896,992),color);d=ImageDraw.Draw(board)
        for i in range(16):
            b=Image.new('RGBA',SIZE,color);b.alpha_composite(frames[i*4]);x=i%4*224;y=i//4*248;board.paste(b.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));d.text((x+6,y+228),str(i),fill='#b9a37f')
        board.save(ROOT/'review'/f'runtime-{label}.png')
    frozen=[]
    for ms in [700,750]:layer,_=light(ms,dome_at(3));frozen.append(hashlib.sha256(layer.tobytes()).hexdigest())
    assert len(set(frozen))==2
    for key in ['character_animation','effect_animation']:assert sha(Path(lock[key]['path']))==lock[key]['sha256']
    with Image.open(ROOT/'review/night.webp') as im:
        total=0
        for j in range(im.n_frames):
            im.seek(j);im.load();total+=im.info['duration'];assert night.border_max(im.convert('RGBA').getchannel('A'))==0
        assert im.n_frames==64 and total==CYCLE
    report={'mode':'effect-repair','retained_drawings':16,'cycle_ms':CYCLE,'effect_ms':STEP,'character_files_and_animation_byte_identical':True,'old_full_effect_animation_unchanged':True,'RGBA_unchanged_outside_registered_glass_mask':True,'all_alpha_unchanged':True,'distinct_light_samples':64,'frozen_pose_light_progression':True,'changed_pixel_range':[min(changes),max(changes)],'night_webp_sha256':sha(ROOT/'review/night.webp'),'native_installed':False}
    (ROOT/'review/repair-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
if __name__=='__main__':main()
