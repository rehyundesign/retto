"""Same-pose whole-companion edits; retain original main core and lower body."""
from pathlib import Path
import hashlib,json,importlib.util
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops
ROOT=Path(__file__).resolve().parent;OLD=ROOT.parent/'failed-v2-tears-20261106';SIZE=(544,544)
s=importlib.util.spec_from_file_location('old_prepare',OLD/'prepare.py');old=importlib.util.module_from_spec(s);s.loader.exec_module(old)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def contact_boxes(i,nose):
    x,y=nose;boxes=[]
    if i in [2,3,4,5]:boxes.append([x-59,y-7,x-24,y+27])
    if i in [8,9,10,11,12]:boxes.append([x+24,y-7,x+62,y+27])
    return boxes
def edit_mask(original,record,i):
    a=record['attachment_proxies'];bell=a['tato_bell'];bow=a['melody_bow_ribbon_proxy'];nose=a['main_nose']
    mask=Image.new('L',SIZE);d=ImageDraw.Draw(mask)
    d.rectangle((0,max(20,bell[1]-135),min(180,bell[0]+55),min(344,bell[1]+95)),fill=255)
    d.rectangle((350,max(20,bow[1]-200),543,min(344,bow[1]+115)),fill=255)
    boxes=contact_boxes(i,nose)
    for b in boxes:d.rectangle(b,fill=255)
    mask=mask.filter(ImageFilter.GaussianBlur(1.1))
    protect=Image.new('L',SIZE);p=ImageDraw.Draw(protect);p.rectangle((180,150,350,543),fill=255)
    for b in boxes:p.rectangle(b,fill=0)
    upper=Image.new('L',SIZE);ImageDraw.Draw(upper).rectangle((155,45,375,150),fill=255)
    upper=ImageChops.multiply(upper,original.getchannel('A').point(lambda x:255 if x>16 else 0));protect=ImageChops.lighter(protect,upper)
    rgba=np.asarray(original).astype(int);rr,gg,bb,aa=[rgba[:,:,k] for k in range(4)];yy,xx=np.indices(aa.shape)
    eyes=(bb-rr>4)&(bb-gg>0)&(aa>180)&(xx>180)&(xx<350)&(yy>nose[1]-50)&(yy<nose[1]-3)
    eye_protect=Image.fromarray((eyes*255).astype('uint8')).filter(ImageFilter.MaxFilter(3));protect=ImageChops.lighter(protect,eye_protect)
    # Every source pixel below companion flight height is immutable (paws/tail).
    p=ImageDraw.Draw(protect);p.rectangle((0,348,543,543),fill=255)
    mask=ImageChops.multiply(mask,ImageChops.invert(protect));return mask,protect,boxes
def one(i):
    ident=f'{i:02}';record=json.loads((OLD/'sources.json').read_text())[i];source=Image.open(OLD/record['path']).convert('RGBA')
    assert sha(OLD/record['path'])==json.loads((ROOT/'pre-edit-lock.json').read_text())['source_sha256'][ident]
    donor,n=old.clean(Image.open(ROOT/'raw'/f'{ident}.png').convert('RGBA'))
    before=old.landmarks(source,i);after=old.landmarks(donor,i);dx=round(before['main_nose'][0]-after['main_nose'][0]);dy=round(before['main_nose'][1]-after['main_nose'][1]);assert abs(dx)<32 and abs(dy)<32,(i,dx,dy)
    aligned=Image.new('RGBA',SIZE);aligned.alpha_composite(donor,(dx,dy))
    mask,protect,boxes=edit_mask(source,record,i);fixed=Image.composite(aligned,source,mask)
    outside=ImageChops.invert(mask.point(lambda x:255 if x else 0));diff=ImageChops.difference(source,fixed)
    assert all(ImageChops.multiply(c,outside).getbbox() is None for c in diff.split())
    assert all(ImageChops.multiply(c,protect).getbbox() is None for c in diff.split()),'main protected pixels changed'
    assert old.support(fixed)==old.support(source)==484
    p=ROOT/'character'/f'{ident}.png';fixed.save(p);m=ROOT/'masks'/f'{ident}.png';mask.save(m)
    prompt=ROOT/'prompts'/f'{ident}-repair.txt'
    if not prompt.exists() or i==9:prompt=ROOT/'prompts'/f'{ident}.txt'
    info={'id':ident,'path':f'character/{ident}.png','sha256':sha(p),'original_path':str((OLD/record['path']).resolve()),'original_sha256':sha(OLD/record['path']),'donor_sha256':sha(ROOT/'raw'/f'{ident}.png'),'prompt_sha256':sha(prompt),'mask_sha256':sha(m),'mask_path':f'masks/{ident}.png','same_pose_complete_pet_repair':True,'new_main_pose_constructed':False,'donor_whole_scene_registration':[dx,dy],'changed_outside_pet_occlusion_mask_pixels':0,'protected_main_core_paws_tail_changed_pixels':0,'cheek_contact_boxes':boxes,'attachment_proxies':old.landmarks(fixed,i)}
    return fixed,info
def main():
    frames=[];records=[]
    for i in range(16):f,r=one(i);frames.append(f);records.append(r)
    frames[0].save(ROOT/'review/character.webp',save_all=True,append_images=frames[1:],duration=200,loop=0,lossless=True,method=4,exact=True)
    for color,label in [('#10182a','dark'),('#edf0f5','light')]:
        b=Image.new('RGB',(896,992),color);d=ImageDraw.Draw(b)
        for i,f in enumerate(frames):
            c=Image.new('RGBA',SIZE,color);c.alpha_composite(f);x=i%4*224;y=i//4*248;b.paste(c.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));d.text((x+6,y+228),str(i),fill='#b9a37f')
        b.save(ROOT/'review'/f'character-runtime-{label}.png')
    (ROOT/'sources.json').write_text(json.dumps(records,indent=2)+'\n');print({'retained_motion_poses':16,'protected_main_pixels_changed':0,'outside_companion_edit_masks_changed':0,'same_pose_only':True})
if __name__=='__main__':main()
