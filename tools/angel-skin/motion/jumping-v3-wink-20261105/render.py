"""Re-export the retained click motion with only protected eyelid RGB repairs."""
from pathlib import Path
import hashlib,importlib.util,json
from PIL import Image,ImageChops,ImageDraw

ROOT=Path(__file__).resolve().parent
OLD=ROOT.parent/'jumping-v2-trio-flight-20261105'
spec=importlib.util.spec_from_file_location('retained_click_motion',OLD/'render.py')
motion=importlib.util.module_from_spec(spec);spec.loader.exec_module(motion)
SIZE=(544,544);CYCLE=2400;STEP=50
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def maxdiff(a,b):return max(c.getextrema()[1] for c in ImageChops.difference(a,b).split()[:3])
def main():
    lock=json.loads((ROOT/'pre-edit-lock.json').read_text())
    assert sha(OLD/'render.py')==lock['effect_code_sha256']
    assert sha(OLD/'sources.json')==lock['source_records_sha256']
    assert sha(OLD/'wingtips.json')==lock['wingtips_sha256']
    old_records=json.loads((OLD/'sources.json').read_text())
    tips=json.loads((OLD/'wingtips.json').read_text())['points']
    old_frames=[Image.open(OLD/r['path']).convert('RGBA') for r in old_records]
    records=json.loads((ROOT/'sources.json').read_text())
    frames=[Image.open(ROOT/r['path']).convert('RGBA') for r in records]
    masks=[Image.open(ROOT/r['mask_path']).convert('L') for r in records]
    full=[];dark=[];effect_hashes=[]
    old_export=Image.open(OLD/'review/night.webp')
    for tick,ms in enumerate(range(0,CYCLE,STEP)):
        i=ms//150
        back,front=motion.effects(ms,old_records,tips)
        effect_hashes.append(hashlib.sha256(back.tobytes()+front.tobytes()).hexdigest())
        original=back.copy();original.alpha_composite(old_frames[i]);original.alpha_composite(front)
        old_export.seek(tick);old_export.load();decoded_old=old_export.convert('RGBA')
        for color in ['#10182a','#edf0f5']:
            a=Image.new('RGBA',SIZE,color);a.alpha_composite(original)
            b=Image.new('RGBA',SIZE,color);b.alpha_composite(decoded_old)
            assert maxdiff(a,b)<=1, 'Original FX no longer reproduces its locked export'
        repaired=back.copy();repaired.alpha_composite(frames[i]);repaired.alpha_composite(front)
        protected=ImageChops.invert(masks[i].point(lambda a:255 if a else 0))
        delta=ImageChops.difference(original,repaired)
        assert all(ImageChops.multiply(c,protected).getbbox() is None for c in delta.split())
        assert delta.getchannel('A').getbbox() is None
        full.append(repaired)
        bg=Image.new('RGBA',SIZE,'#10182a');bg.alpha_composite(repaired);dark.append(bg.convert('RGB'))
    motion.night.save_webp(full,ROOT/'review/night.webp',STEP)
    dark[0].save(ROOT/'review/jumping.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2)
    full[21].save(ROOT/'review/preview.png')
    board=Image.new('RGB',(544*4,568*4),'#10182a');d=ImageDraw.Draw(board)
    for i in range(16):
        x=i%4*544;y=i//4*568;board.paste(dark[i*3],(x,y));d.text((x+8,y+548),str(i),fill='#a38a64')
    board.save(ROOT/'review/effect-dark-board.png')
    report={'retained_complete_pose_drawings':16,'per_pose_eye_repairs':16,'pose_ms':150,
      'effect_sample_ms':50,'cycle_ms':CYCLE,'original_motion_effects_reproduced':True,
      'outside_eye_masks_RGBA_changed_pixels':0,'alpha_changed_pixels':0,
      'motion_or_character_geometry_changed':False,'effect_sample_hashes':effect_hashes,
      'native_installed':False,'original_registration':'inherited unverified','media':{}}
    for name in ['character.webp','night.webp','character.gif','jumping.gif']:
        total=0;unique=set()
        with Image.open(ROOT/'review'/name) as im:
            for i in range(im.n_frames):
                im.seek(i);im.load();total+=im.info['duration']
                if name.endswith('.webp'):
                    decoded=im.convert('RGBA');expected=frames[i] if name=='character.webp' else full[i]
                    assert motion.night.border_max(decoded.getchannel('A'))==0
                    for color in ['#10182a','#edf0f5']:
                        a=Image.new('RGBA',SIZE,color);a.alpha_composite(expected)
                        b=Image.new('RGBA',SIZE,color);b.alpha_composite(decoded)
                        assert maxdiff(a,b)<=1
                    if name=='character.webp':unique.add(hashlib.sha256(decoded.tobytes()).hexdigest())
            assert total==CYCLE
            if unique:assert len(unique)==16
            report['media'][name]={'frames':im.n_frames,'cycle_ms':total,'sha256':sha(ROOT/'review'/name)}
    (ROOT/'review/media-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='effect_sample_hashes'}))
if __name__=='__main__':main()
