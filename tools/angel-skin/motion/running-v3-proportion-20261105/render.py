"""Assemble independently drawn hovering poses; no character warps or prop rotation."""
from pathlib import Path
import hashlib, importlib.util, json, math
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('night', ROOT.parent/'night-effects-v1-20261105/render_night.py')
night = importlib.util.module_from_spec(spec)
spec.loader.exec_module(night)
SIZE = (544, 544)
CYCLE = 3200
FEATHER = Image.open(ROOT.parent/'running-v1-20261105/effects/feather.png').convert('RGBA')

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def effects(ms, dome):
    t = ms/CYCLE
    back = night.fade_edges(night.night_atmosphere(ms, SIZE, CYCLE))
    feathers=Image.new('RGBA',SIZE)
    for j in range(6):
        q=(t+j/6)%1
        x=55+j*86+13*math.sin(math.tau*q+j)
        y=420-q*350
        night.stamp(feathers,FEATHER,(x,y),18+3*(j%3),
                    .42*math.sin(math.pi*q)**2,25*math.sin(math.tau*q+j),halo=False)
    back.alpha_composite(night.fade_edges(feathers))
    # Music leaves the actual glass, then fades before the cell edge.
    notes = Image.new('RGBA', SIZE)
    for j in range(5):
        q = (t+j/5)%1
        x = dome[0]+dome[2]/2 + math.sin(q*math.pi*1.5+j)*45
        y = dome[1]+35-q*100
        night.stamp(notes, night.music_note(15), (x,y), 15,
                    math.sin(math.pi*q)**2*.7, 10*math.sin(q*math.tau+j))
    back.alpha_composite(night.fade_edges(notes))
    # Sparse independent glints confined to glass interior below the muzzle.
    front = Image.new('RGBA', SIZE)
    d = ImageDraw.Draw(front)
    x0,y0,w,h = dome
    colours = [(255,237,177),(201,237,255),(255,203,241),(229,211,255)]
    for j in range(11):
        q = (t+j*.173)%1
        x = x0+w*(.2+(j*.618%1)*.6)
        y = y0+h*(.25+(j*.371%1)*.6)
        a = round(190*math.sin(math.pi*q)**6)
        r = 1+2*math.sin(math.pi*q)**4
        col = (*colours[j%4],a)
        d.line((x-r,y,x+r,y),fill=col,width=1)
        d.line((x,y-r,x,y+r),fill=col,width=1)
    glow = front.filter(ImageFilter.GaussianBlur(3))
    glow.alpha_composite(front)
    return back,glow

def save_webp(frames,path,ms):
    frames[0].save(path,save_all=True,append_images=frames[1:],duration=ms,loop=0,
                   lossless=True,method=4,minimize_size=False)

def main():
    raw = [ROOT/'raw'/f'{i:02}.png' for i in range(16)]
    assert all(p.exists() for p in raw), 'All16 independent source drawings required'
    assert len({sha(p) for p in raw})==16
    poses=[];registrations=[]
    hover=[0,-1,-3,-4,-5,-4,-2,0,2,4,5,4,3,1,0,0]
    anchor_top=None
    for i,p in enumerate(raw):
        im=Image.open(p).convert('RGBA')
        assert im.size==(1254,1254), (p,im.size)
        # Same-pose technical matte cleanup only. Generated low-alpha white
        # haze (especially11) is not costume art; retain RGB and opaque anatomy.
        im.putalpha(im.getchannel('A').point(lambda a:0 if a<=160 else min(255,round((a-160)*255/80))))
        # Ear tips are anatomical landmarks above the wing region. Use them
        # only for rigid whole-character vertical registration, never size fit.
        a=im.getchannel('A')
        ear_top=next(y for y in range(40,300) if sum(v>=240 for v in a.crop((300,y,900,y+1)).tobytes())>=8)
        if anchor_top is None:anchor_top=ear_top
        dy=round((anchor_top-ear_top)*512/1254)+hover[i]
        # One shared camera transform, never fit individual silhouettes.
        im=im.resize((512,512),Image.Resampling.LANCZOS)
        cell=Image.new('RGBA',SIZE)
        cell.alpha_composite(im,(16,16+dy))
        cell.save(ROOT/'character'/f'{i:02}.png')
        poses.append(cell)
        registrations.append({'id':f'{i:02}','measured_ear_tip_raw_y':ear_top,'whole_character_y_px':dy,'no_pose_or_scale_warp':True})
    # Per-drawing dome locations are inspected in source pixels and transformed
    # by the same camera. Boxes describe only glass, excluding base and face.
    domes=json.loads((ROOT/'dome-landmarks.json').read_text())
    full=[]; chars=[]; dark=[]
    for ms in range(0,CYCLE,50):
        i=ms//200
        dome=[16+domes[i][0]*512/1254,16+registrations[i]['whole_character_y_px']+domes[i][1]*512/1254,
              domes[i][2]*512/1254,domes[i][3]*512/1254]
        back,front=effects(ms,dome)
        back.alpha_composite(poses[i]); back.alpha_composite(front)
        full.append(back);chars.append(poses[i])
        bg=Image.new('RGBA',SIZE,(19,29,50,255));bg.alpha_composite(back)
        dark.append(bg.convert('RGB'))
    review=ROOT/'review'
    save_webp(full,review/'night.webp',50)
    save_webp(poses,review/'character.webp',200)
    dark[0].save(review/'running.gif',save_all=True,append_images=dark[1:],duration=50,loop=0,disposal=2)
    full[0].save(review/'preview.png')
    board=Image.new('RGB',(4*288,4*292),(19,29,50))
    d=ImageDraw.Draw(board)
    for i,cell in enumerate(poses):
        tile=Image.new('RGBA',SIZE,(19,29,50,255));tile.alpha_composite(cell)
        tile=tile.resize((272,272),Image.Resampling.LANCZOS)
        board.paste(tile.convert('RGB'),((i%4)*288+8,(i//4)*292))
        d.text(((i%4)*288+8,(i//4)*292+274),f'{i:02} / {i*22.5:g} deg',fill='white')
    board.save(review/'all-poses.png')
    light=Image.new('RGB',board.size,'#edf0f5')
    dl=ImageDraw.Draw(light)
    for i,cell in enumerate(poses):
        tile=Image.new('RGBA',SIZE,(237,240,245,255));tile.alpha_composite(cell)
        light.paste(tile.resize((272,272),Image.Resampling.LANCZOS).convert('RGB'),((i%4)*288+8,(i//4)*292))
        dl.text(((i%4)*288+8,(i//4)*292+274),f'{i:02}',fill='#302e39')
    light.save(review/'all-poses-light.png')
    # Side-by-side display-size comparison is evidence, not original anatomical certification.
    comp=Image.new('RGB',(1088,544),(19,29,50))
    approved=Image.open(ROOT/'references/approved-retto.png').convert('RGBA')
    approved.thumbnail((544,544),Image.Resampling.LANCZOS)
    comp.paste(approved.convert('RGB'),(16,0))
    shown=Image.new('RGBA',SIZE,(19,29,50,255));shown.alpha_composite(full[0])
    comp.paste(shown.convert('RGB'),(544,0))
    comp.save(review/'size-comparison.png')
    report={'source_count':16,'unique_source_hashes':len({sha(p) for p in raw}),
            'independent_full_character_drawings':True,'shared_camera_transform':[512/1254,16,16],
            'alpha_cleanup':'same-pose alpha-only ramp160..240; original raw RGB and files preserved',
            'whole_character_registration':registrations,
            'pose_ms':200,'effect_sample_ms':50,'cycle_ms':CYCLE,
            'character_source_hashes':{p.name:sha(p) for p in raw},
            'original_registration':'unverified','native_installed':False}
    for name in ['night.webp','character.webp','running.gif']:
        with Image.open(review/name) as im:
            duration=0; borders=[]
            for i in range(im.n_frames):
                im.seek(i);im.load();duration+=im.info['duration']
                if name.endswith('.webp'):
                    decoded=im.convert('RGBA')
                    expected=full[i] if name=='night.webp' else poses[i]
                    for colour in ['#131d32','#edf0f5']:
                        got=Image.new('RGBA',SIZE,colour);got.alpha_composite(decoded)
                        want=Image.new('RGBA',SIZE,colour);want.alpha_composite(expected)
                        assert max(c.getextrema()[1] for c in ImageChops.difference(got,want).split()[:3])<=1
                    a=decoded.getchannel('A')
                    borders.append(max(a.crop(b).getextrema()[1] for b in [(0,0,544,1),(0,543,544,544),(0,0,1,544),(543,0,544,544)]))
            assert duration==CYCLE
            if borders:assert max(borders)==0
            report[name]={'frames':im.n_frames,'duration_ms':duration,'edge_alpha_max':max(borders) if borders else None,'sha256':sha(review/name)}
    (review/'media-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
