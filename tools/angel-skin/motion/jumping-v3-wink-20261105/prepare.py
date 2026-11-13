"""Same-pose protected eyelid/brow repair; preserve every other pixel and all alpha."""
from pathlib import Path
import hashlib,json
from PIL import Image,ImageChops,ImageDraw,ImageFilter
from eyes import locate

ROOT=Path(__file__).resolve().parent
OLD=ROOT.parent/'jumping-v2-trio-flight-20261105'
SIZE=(544,544)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def one(i,record):
    ident=f'{i:02}';original=OLD/record['path'];target=Image.open(original).convert('RGBA')
    assert sha(original)==json.loads((ROOT/'pre-edit-lock.json').read_text())['character_sha256'][ident]
    path=ROOT/'donors'/f'{ident}.png';donor=Image.open(path).convert('RGBA').resize(SIZE,Image.Resampling.LANCZOS)
    before=locate(target,record);after=locate(donor,record)
    mask=Image.new('L',SIZE);d=ImageDraw.Draw(mask);boxes={}
    for key,box in before.items():
        other=after[key];actor=key.split('_')[0]
        px,py={'retto':(7,10),'tato':(4,5),'melody':(5,5)}[actor]
        x0=min(box[0],other[0])-px;y0=min(box[1],other[1])-py
        x1=max(box[2],other[2])+px;y1=max(box[3],other[3])+py
        assert x1-x0<90 and y1-y0<65,(ident,key,'donor moved beyond eye scope')
        d.rounded_rectangle((x0,y0,x1,y1),radius=5,fill=255);boxes[key]=[x0,y0,x1,y1]
    mask=mask.filter(ImageFilter.GaussianBlur(1))
    # Even the soft mask fringe must not repaint the original noses/mouths.
    protected_features=Image.new('L',SIZE);p=ImageDraw.Draw(protected_features)
    for actor in ['retto','tato','melody']:
        left=before[f'{actor}_0'];right=before[f'{actor}_1']
        if actor=='retto':region=(left[2]-3,max(left[3],right[3])+4,right[0]+3,max(left[3],right[3])+72)
        elif actor=='tato':region=(left[2]+2,min(left[3],right[3])+8,right[0]-2,max(left[3],right[3])+35)
        else:region=(left[2]-4,max(left[3],right[3])+2,right[0]+4,max(left[3],right[3])+30)
        if region[0]<region[2]:p.rectangle(region,fill=255)
    mask=ImageChops.subtract(mask,protected_features)
    fixed=Image.composite(donor.convert('RGB'),target.convert('RGB'),mask).convert('RGBA')
    fixed.putalpha(target.getchannel('A'))
    protected=ImageChops.invert(mask.point(lambda a:255 if a else 0))
    diff=ImageChops.difference(target,fixed)
    assert all(ImageChops.multiply(c,protected).getbbox() is None for c in diff.split())
    assert ImageChops.difference(target.getchannel('A'),fixed.getchannel('A')).getbbox() is None
    out=ROOT/'character'/f'{ident}.png';fixed.save(out);mask.save(ROOT/'masks'/f'{ident}.png')
    return fixed,{'id':ident,'path':f'character/{ident}.png','sha256':sha(out),
       'original_path':str(original.resolve()),'original_sha256':sha(original),'donor_sha256':sha(path),
       'mask_path':f'masks/{ident}.png','mask_sha256':sha(ROOT/'masks'/f'{ident}.png'),
       'eye_boxes':boxes,'changed_outside_eye_mask_pixels':0,'alpha_changed_pixels':0,
       'anatomical_pose_changed':False,'original_anatomical_landmarks':'inherited unverified'}
def main():
    old=json.loads((OLD/'sources.json').read_text());frames=[];records=[]
    for i,r in enumerate(old):
        im,report=one(i,r);frames.append(im);records.append(report)
    for label,color in [('dark','#10182a'),('light','#edf0f5')]:
        board=Image.new('RGB',(544*4,568*4),color);d=ImageDraw.Draw(board)
        for i,im in enumerate(frames):
            b=Image.new('RGBA',SIZE,color);b.alpha_composite(im);x=i%4*544;y=i//4*568
            board.paste(b.convert('RGB'),(x,y));d.text((x+8,y+548),str(i),fill='#a38a64')
        board.save(ROOT/'review'/f'character-{label}-board.png')
    frames[0].save(ROOT/'review/character.webp',save_all=True,append_images=frames[1:],duration=150,loop=0,lossless=True,method=4,exact=True)
    dark=[]
    for im in frames:
        b=Image.new('RGBA',SIZE,'#10182a');b.alpha_composite(im);dark.append(b.convert('RGB'))
    dark[0].save(ROOT/'review/character.gif',save_all=True,append_images=dark[1:],duration=150,loop=0,disposal=2)
    (ROOT/'sources.json').write_text(json.dumps(records,indent=2)+'\n')
    print(json.dumps({'retained_complete_drawings':16,'same_pose_eye_repairs':16,'outside_masks_changed_pixels':0,'alpha_changed_pixels':0}))
if __name__=='__main__':main()
