"""Compose independently drawn moving parts over the immutable original Retto body."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import json,hashlib

ROOT=Path(__file__).resolve().parent
BASE=ROOT.parent.parent/'jeanne-base-reference.png'
base=Image.open(BASE).convert('RGBA').resize((448,640),Image.Resampling.LANCZOS)
clothes=Image.open(ROOT/'fitted-costume-overlay-v5.png').convert('RGBA')
master=Image.alpha_composite(base,clothes)
face_mask=Image.new('L',(448,640));d=ImageDraw.Draw(face_mask)
d.rectangle((40,224,298,424),fill=255)
for y in range(425,450):d.line((40,y,298,y),fill=max(0,int(255*(450-y)/25)))
face_mask=ImageChops.multiply(face_mask,base.getchannel('A'))
master=Image.composite(base,master,face_mask)
master.save(ROOT/'original-master-v3.png')

ear_mask=Image.new('L',(448,640));d=ImageDraw.Draw(ear_mask)
d.rectangle((62,224,164,324),fill=255);d.rectangle((187,224,282,324),fill=255)
ear_mask=ImageChops.multiply(ear_mask,base.getchannel('A')).filter(ImageFilter.MaxFilter(5))
for y in range(307,327):
    line=Image.new('L',(448,1),max(0,int(255*(327-y)/20)))
    row=ear_mask.crop((0,y,448,y+1));row=ImageChops.multiply(row,line);ear_mask.paste(row,(0,y))

tail_mask=Image.new('L',(448,640));ImageDraw.Draw(tail_mask).rectangle((288,410,438,628),fill=255)
eye_mask=Image.new('L',(448,640));d=ImageDraw.Draw(eye_mask)
d.ellipse((117,330,159,371),fill=255);d.ellipse((186,330,230,371),fill=255)
eye_mask=eye_mask.filter(ImageFilter.GaussianBlur(1))
wing_mask=Image.new('L',(448,640));d=ImageDraw.Draw(wing_mask)
d.rectangle((305,251,338,353),fill=255);d.rectangle((384,251,443,355),fill=255)
moving=ImageChops.lighter(ImageChops.lighter(ear_mask,tail_mask),wing_mask)

outdir=ROOT/'idle-v3';outdir.mkdir(exist_ok=True)
records=[]
for i in range(16):
    source=ROOT/'idle-v3-raw'/f'idle-{i:02d}.png'
    if not source.exists():continue
    if (ROOT/'idle-v3-raw'/f'idle-{i:02d}-bridge.png').exists():source=ROOT/'idle-v3-raw'/f'idle-{i:02d}-bridge.png'
    raw=Image.open(source).convert('RGBA').resize((448,640),Image.Resampling.LANCZOS)
    mask=ImageChops.lighter(moving,eye_mask) if 3<=i<=10 else moving
    out=Image.composite(raw,master,mask)
    # Preserve the complete outfit and grounded limbs at their original attachment.
    costume_keep=Image.new('L',(448,640));ImageDraw.Draw(costume_keep).rectangle((0,450,287,640),fill=255)
    out=Image.composite(master,out,costume_keep)
    target=outdir/f'idle-{i:02d}.png';out.save(target)
    protected=mask.point(lambda v:255 if v==0 else 0)
    diff=ImageChops.difference(out,master)
    channels=diff.split()
    changed=channels[0]
    for ch in channels[1:]:changed=ImageChops.lighter(changed,ch)
    locked_change=ImageChops.multiply(changed,protected).getbbox()
    assert locked_change is None
    records.append({'frame':i,'source':str(source),'sourceHash':hashlib.sha256(source.read_bytes()).hexdigest(),'decodedHash':hashlib.sha256(out.tobytes()).hexdigest(),'outsideMovingMaskChanged':False,'bodyAndSupportedFeet':'immutable original Retto body plus fixed clothing','fourLimbs':'original seated forelegs; rear pair occluded by seated torso and skirt'})
(ROOT/'idle-v3-composition.json').write_text(json.dumps({'status':'review candidate','mode':'overlay-only with independent anatomical ear tail blink wing drawings','originalBodySource':str(BASE),'bodySizeAndPosition':'unchanged from actual original atlas cell','registrationLimits':'ear/tail moving regions require visual review; not an all-state release pass','frames':records},indent=2))
for bg,name in [('#181827','dark'),('#fffdf8','white')]:
    board=Image.new('RGB',(896,1360),bg);d=ImageDraw.Draw(board)
    for r in records:
        i=r['frame'];im=Image.open(outdir/f'idle-{i:02d}.png').resize((224,320),Image.Resampling.LANCZOS)
        board.paste(im,(i%4*224,i//4*340),im);d.text((i%4*224+8,i//4*340+322),str(i+1),fill='white' if name=='dark' else 'black')
    board.save(ROOT/'review'/f'idle-v3-{name}.jpg')
print('Composed',len(records),'independent cells with protected original body, feet and outfit')
