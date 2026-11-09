"""Reproduce approved motion/effects exactly; replace only protected main-eye RGB regions."""
from pathlib import Path
import json,hashlib,importlib.util
from PIL import Image,ImageChops,ImageDraw
ROOT=Path(__file__).resolve().parent;OLD=ROOT.parent/'idle-v3-airborne-20261106';SIZE=(544,544);CYCLE=3200;POSE=200;STEP=50
spec=importlib.util.spec_from_file_location('approved_idle_effects',OLD/'render.py');approved=importlib.util.module_from_spec(spec);spec.loader.exec_module(approved)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    lock=json.loads((ROOT/'pre-edit-lock.json').read_text());assert sha(OLD/'render.py')==lock['effect_code_sha256'];assert sha(OLD/'sources.json')==lock['sources_sha256'];assert sha(OLD/'review/night.webp')==lock['effect_animation_sha256']
    oldrecords=json.loads((OLD/'sources.json').read_text());records=json.loads((ROOT/'sources.json').read_text())
    previous=[Image.open(OLD/r['path']).convert('RGBA') for r in oldrecords];current=[Image.open(ROOT/r['path']).convert('RGBA') for r in records];masks=[Image.open(ROOT/r['mask_path']).convert('L') for r in records]
    assert all(sha(ROOT/r['path'])==r['sha256'] for r in records)
    full=[];dark=[];effect_hashes=[];prior_movie=Image.open(OLD/'review/night.webp')
    for j,ms in enumerate(range(0,CYCLE,STEP)):
        i=ms//POSE;back,front=approved.effects(ms,oldrecords);effect_hashes.append(hashlib.sha256(back.tobytes()+front.tobytes()).hexdigest())
        before=approved.compose(back,previous[i],front);after=approved.compose(back,current[i],front)
        outside=ImageChops.invert(masks[i].point(lambda a:255 if a else 0));assert all(ImageChops.multiply(c,outside).getbbox() is None for c in ImageChops.difference(before,after).split())
        assert ImageChops.difference(before.getchannel('A'),after.getchannel('A')).getbbox() is None
        prior_movie.seek(j);prior_movie.load();decoded=prior_movie.convert('RGBA')
        for color in ['#10182a','#edf0f5']:
            a=Image.new('RGBA',SIZE,color);a.alpha_composite(before);b=Image.new('RGBA',SIZE,color);b.alpha_composite(decoded);assert max(c.getextrema()[1] for c in ImageChops.difference(a,b).split()[:3])<=1
        full.append(after);bg=Image.new('RGBA',SIZE,'#10182a');bg.alpha_composite(after);dark.append(bg.convert('RGB'))
    approved.night.save_webp(full,ROOT/'review/night.webp',STEP);dark[0].save(ROOT/'review/idle.gif',save_all=True,append_images=dark[1:],duration=STEP,loop=0,disposal=2);full[0].save(ROOT/'review/preview.png')
    for color,label in [('#10182a','dark'),('#edf0f5','light')]:
        board=Image.new('RGB',(896,992),color);d=ImageDraw.Draw(board)
        for i in range(16):
            b=Image.new('RGBA',SIZE,color);b.alpha_composite(full[i*4]);x=i%4*224;y=i//4*248;board.paste(b.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));d.text((x+6,y+228),str(i),fill='#b9a37f')
        board.save(ROOT/'review'/f'effect-runtime-{label}.png')
    report={'retained_independent_complete_drawings':16,'open_eye_cosmetic_repairs':14,'closed_smile_frames_unchanged':['05','12'],'source_pose_interval_ms':200,'effect_interval_ms':50,'cycle_ms':3200,'original_effect_code_and_inputs_preserved':True,'entire_RGBA_unchanged_outside_eye_masks':True,'all_alpha_unchanged':True,'head_body_companion_motion_changed':False,'opaque_star_or_grip_changed':False,'native_installed':False,'original_registration':'inherited unverified','media':{}}
    for name in ['character.webp','character.gif','night.webp','idle.gif']:
        total=0;unique=set()
        with Image.open(ROOT/'review'/name) as im:
            for i in range(im.n_frames):
                im.seek(i);im.load();total+=im.info['duration']
                if name.endswith('webp'):
                    decoded=im.convert('RGBA');expected=current[i] if name=='character.webp' else full[i]
                    assert approved.night.border_max(decoded.getchannel('A'))==0
                    for color in ['#10182a','#edf0f5']:
                        a=Image.new('RGBA',SIZE,color);a.alpha_composite(decoded);b=Image.new('RGBA',SIZE,color);b.alpha_composite(expected);assert max(c.getextrema()[1] for c in ImageChops.difference(a,b).split()[:3])<=1
                    unique.add(hashlib.sha256(decoded.tobytes()).hexdigest())
            assert total==CYCLE
            if name=='character.webp':assert len(unique)==16
            report['media'][name]={'frames':im.n_frames,'cycle_ms':total,'sha256':sha(ROOT/'review'/name)}
    (ROOT/'review/media-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
if __name__=='__main__':main()
