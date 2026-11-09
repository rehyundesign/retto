"""Remove reviewed idle-only background fragments; preserve every source RGB pixel."""
from pathlib import Path
import hashlib,json,sys,importlib.util,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageChops
ROOT=Path(__file__).resolve().parent
OLD=ROOT.parent/'matte-repair-v3-holes-20261105/idle'
sys.path.insert(0,str(OLD.parent));from holes import clean
spec=importlib.util.spec_from_file_location('sky',ROOT.parent/'night-effects-v1-20261105/render_night.py');sky=importlib.util.module_from_spec(spec);spec.loader.exec_module(sky)
POLYGONS={0:[[(69,309),(86,309),(86,318),(91,319),(88,324),(82,326),(69,326)]],1:[[(73,310),(82,310),(82,316),(79,320),(73,318)]],7:[[(68,308),(81,308),(84,316),(84,320),(82,324),(76,324),(68,322)]],8:[[(73,310),(81,310),(81,316),(73,316)]],9:[[(77,310),(82,310),(85,318),(84,322),(81,321),(77,315)],[(67,310),(73,310),(73,318),(67,318)]],15:[[(70,308),(84,308),(84,317),(89,319),(86,323),(80,322),(70,321)]]}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,indent=2)+'\n')
def main():
    before=[];after=[];records=[];masks=[]
    for i in range(16):
        source=OLD/'character'/f'{i:02}.png';im=Image.open(source).convert('RGBA');mask=Image.new('L',im.size);d=ImageDraw.Draw(mask)
        for polygon in POLYGONS.get(i,[]):d.polygon(polygon,fill=255)
        if i==13:
            _,hole,_=clean(im,());mask=ImageChops.lighter(mask,Image.fromarray((hole*255).astype('uint8')))
        v=np.asarray(im).copy();changed=(np.asarray(mask)>0)&(v[:,:,3]>0);v[:,:,3][changed]=0;fixed=Image.fromarray(v)
        assert np.array_equal(v[:,:,:3],np.asarray(im)[:,:,:3]);assert np.all(v[:,:,3][~changed]==np.asarray(im)[:,:,3][~changed])
        out=ROOT/'idle/character'/f'{i:02}.png'
        if changed.any():fixed.save(out)
        else:shutil.copyfile(source,out)
        Image.fromarray((changed*255).astype('uint8')).save(ROOT/'idle/masks'/f'{i:02}.png')
        records.append({'id':f'{i:02}','path':str(out.resolve()),'sha256':sha(out),'input_path':str(source.resolve()),'input_sha256':sha(source),'alpha_removed_pixels':int(changed.sum()),'RGB_changed_pixels':0,'outside_mask_RGBA_changed_pixels':0});before.append(im);after.append(fixed);masks.append(Image.fromarray((changed*255).astype('uint8')))
    sky.save_webp(after,ROOT/'idle/character.webp',200);write(ROOT/'idle/cleanup.json',{'reviewed_background_fragment_polygons':POLYGONS,'extra_hole13':'neutral-white enclosed background component53,315..84,333; previously misprotected as white fur','frames':records})
    # Rebuild unchanged underlying moon/star/feather composition around the repaired character.
    original=ROOT.parent/'idle-v2-20261105';sources=json.loads((original/'sources.json').read_text());raws=[Image.open(original/r['path']).convert('RGBA') for r in sources]
    module,star,effect=sky.load_original('idle','idle-v2-20261105',sources,raws)
    old_movie=Image.open(OLD/'night.webp');full=[]
    for j,ms in enumerate(range(0,3200,50)):
        back,front=effect(ms);bg=sky.night_atmosphere(ms,(544,544),3200);bg.alpha_composite(back);bg.alpha_composite(sky.point_effect('idle',ms,(544,544),3200,star));bg=sky.fade_edges(bg);front=sky.fade_idle_glow(front,module,star,sources,ms,3200)
        old=bg.copy();old.alpha_composite(before[ms//200]);old.alpha_composite(front)
        old_movie.seek(j);decoded=old_movie.convert('RGBA')
        for color in ['#10182a','#edf0f5']:
            a=Image.new('RGBA',old.size,color);a.alpha_composite(old);b=Image.new('RGBA',old.size,color);b.alpha_composite(decoded);assert max(c.getextrema()[1] for c in ImageChops.difference(a,b).split()[:3])<=1
        new=bg.copy();new.alpha_composite(after[ms//200]);new.alpha_composite(front)
        outside=ImageChops.invert(masks[ms//200]);assert all(ImageChops.multiply(c,outside).getbbox() is None for c in ImageChops.difference(new,old).split());full.append(new)
    sky.save_webp(full,ROOT/'idle/base-night.webp',50)
    inputs=json.loads((ROOT/'render-inputs.json').read_text());inputs['idle'].update(character=str((ROOT/'idle/character.webp').resolve()),character_sha256=sha(ROOT/'idle/character.webp'),effect=str((ROOT/'idle/base-night.webp').resolve()),effect_sha256=sha(ROOT/'idle/base-night.webp'),sources=[{'id':r['id'],'path':r['path'],'sha256':r['sha256']} for r in records]);write(ROOT/'render-inputs.json',inputs)
    board=Image.new('RGB',(1120,1000),'#070d1c');d=ImageDraw.Draw(board)
    for i,f in enumerate(after):
        tile=Image.new('RGBA',(90,76),'#070d1c');tile.alpha_composite(f.crop((45,280,135,356)));x=i%4*280;y=i//4*250;board.paste(tile.resize((270,228)).convert('RGB'),(x,y));d.text((x+5,y+231),str(i),fill='white')
    board.save(ROOT/'idle/ear-cleanup-review.png');print({'changed_frames':sum(r['alpha_removed_pixels']>0 for r in records),'background_pixels_removed':sum(r['alpha_removed_pixels'] for r in records),'RGB_changed_pixels':0})
if __name__=='__main__':main()
