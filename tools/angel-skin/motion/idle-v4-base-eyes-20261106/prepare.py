"""Same-pose eye/eyelid donor patches only, preserve all approved motion pixels and alpha."""
from pathlib import Path
import hashlib,json,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops
from eyes import locate
ROOT=Path(__file__).resolve().parent;OLD=ROOT.parent/'idle-v3-airborne-20261106';SIZE=(544,544)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def nose_protection(im,eye_centers):
    a=np.asarray(im).astype(int);r,g,b,alpha=[a[:,:,i] for i in range(4)];yy,xx=np.indices(alpha.shape);mx=np.mean([c[0] for c in eye_centers]);my=np.mean([c[1] for c in eye_centers])
    pink=(r-g>35)&(b-g>-25)&(r>180)&(g<220)&(alpha>200)&(abs(xx-mx)<30)&(yy>my+5)&(yy<my+55)
    return Image.fromarray((pink*255).astype('uint8')).filter(ImageFilter.MaxFilter(9))
def one(i):
    ident=f'{i:02}';source=OLD/'character'/f'{ident}.png';assert sha(source)==json.loads((ROOT/'pre-edit-lock.json').read_text())['character_sha256'][ident]
    target=Image.open(source).convert('RGBA');out=ROOT/'character'/f'{ident}.png';mask=Image.new('L',SIZE)
    report={'id':ident,'path':f'character/{ident}.png','input_path':str(source.resolve()),'input_sha256':sha(source),'changed_outside_eye_mask_pixels':0,'alpha_changed_pixels':0,'body_pose_changed':False}
    if i in [5,12]:
        shutil.copyfile(source,out);fixed=target;report['reason']='approved closed smiling eyelids retained byte-for-byte';report['eye_boxes']=[]
    else:
        donor_path=ROOT/'donors'/f'{ident}.png';donor=Image.open(donor_path).convert('RGBA').resize(SIZE,Image.Resampling.LANCZOS)
        before=locate(target);after=locate(donor);d=ImageDraw.Draw(mask);boxes=[]
        for a,b in zip(before,after):
            assert abs(a['center'][0]-b['center'][0])<10 and abs(a['center'][1]-b['center'][1])<10,(ident,'donor eye centers moved too far',a,b)
            old,new=a['bbox'],b['bbox'];box=[min(old[0],new[0])-8,min(old[1],new[1])-7,max(old[2],new[2])+8,max(old[3],new[3])+7]
            assert box[2]-box[0]<64 and box[3]-box[1]<58,(ident,box)
            d.rounded_rectangle(box,radius=8,fill=255);boxes.append(box)
        mask=mask.filter(ImageFilter.GaussianBlur(.8));mask=ImageChops.subtract(mask,nose_protection(target,[v['center'] for v in before]))
        fixed=Image.composite(donor.convert('RGB'),target.convert('RGB'),mask).convert('RGBA');fixed.putalpha(target.getchannel('A'));fixed.save(out)
        report.update(donor_sha256=sha(donor_path),eye_boxes=boxes,source_iris_detection=before,donor_iris_detection=after)
    protected=ImageChops.invert(mask.point(lambda a:255 if a else 0));diff=ImageChops.difference(target,fixed)
    assert all(ImageChops.multiply(c,protected).getbbox() is None for c in diff.split())
    assert ImageChops.difference(target.getchannel('A'),fixed.getchannel('A')).getbbox() is None
    mask_path=ROOT/'masks'/f'{ident}.png';mask.save(mask_path);report.update(sha256=sha(out),mask_path=f'masks/{ident}.png',mask_sha256=sha(mask_path))
    return fixed,report

def main():
    frames=[];records=[]
    for i in range(16):im,r=one(i);frames.append(im);records.append(r)
    for color,label in [('#10182a','dark'),('#edf0f5','light')]:
        board=Image.new('RGB',(896,992),color);d=ImageDraw.Draw(board)
        for i,im in enumerate(frames):
            b=Image.new('RGBA',SIZE,color);b.alpha_composite(im);x=i%4*224;y=i//4*248;board.paste(b.resize((224,224),Image.Resampling.LANCZOS).convert('RGB'),(x,y));d.text((x+6,y+228),str(i),fill='#b9a37f')
        board.save(ROOT/'review'/f'character-runtime-{label}.png')
    frames[0].save(ROOT/'review/character.webp',save_all=True,append_images=frames[1:],duration=200,loop=0,lossless=True,method=4,exact=True)
    dark=[]
    for f in frames:
        b=Image.new('RGBA',SIZE,'#10182a');b.alpha_composite(f);dark.append(b.convert('RGB'))
    dark[0].save(ROOT/'review/character.gif',save_all=True,append_images=dark[1:],duration=200,loop=0,disposal=2)
    (ROOT/'sources.json').write_text(json.dumps(records,indent=2)+'\n');print({'retained_complete_drawings':16,'open_eye_repairs':14,'closed_smile_frames_unchanged':2,'outside_eye_masks_RGBA_changes':0,'alpha_changes':0})
if __name__=='__main__':main()
