from pathlib import Path
from PIL import Image
import numpy as np
import json, subprocess, hashlib, argparse, time

ROOT=Path(__file__).resolve().parent
BASE=ROOT.parent/'integrated-repair-v27'
VENDOR=ROOT/'vendor/rife-ncnn-vulkan-20221029-macos'
parser=argparse.ArgumentParser();parser.add_argument('--pilot',action='store_true');parser.add_argument('--model',default='rife-v4.6');parser.add_argument('--variant',default='');args=parser.parse_args()
OUT=ROOT/args.variant if args.variant else ROOT
OUT.mkdir(parents=True,exist_ok=True)
records=[]
for state,indices in [('waving',[1] if args.pilot else range(16)),('waiting',[8] if args.pilot else range(16))]:
    d=OUT/state;d.mkdir(exist_ok=True)
    work=d/'work';work.mkdir(exist_ok=True)
    for i in indices:
        sources=[BASE/state/f'{j:02}.png' for j in [i,(i+1)%16]]
        images=[Image.open(f).convert('RGBA') for f in sources]
        for label,color in [('black','black'),('white','white')]:
            for k,im in enumerate(images):
                bg=Image.new('RGBA',im.size,color);bg.alpha_composite(im);bg.convert('RGB').save(work/f'{i:02}-{label}-{k}.png')
            out=work/f'{i:02}-{label}-mid.png'
            if not out.exists():
                cmd=[str(VENDOR/'rife-ncnn-vulkan'),'-0',str(work/f'{i:02}-{label}-0.png'),'-1',str(work/f'{i:02}-{label}-1.png'),'-o',str(out),'-m',str(VENDOR/args.model),'-g','-1','-j','1:2:1']
                result=subprocess.run(cmd,capture_output=True,text=True)
                if result.returncode:raise RuntimeError(result.stderr[-3000:])
        b=np.asarray(Image.open(work/f'{i:02}-black-mid.png').convert('RGB'),dtype=np.float32)/255
        w=np.asarray(Image.open(work/f'{i:02}-white-mid.png').convert('RGB'),dtype=np.float32)/255
        # Paired matte inference on complete frames, not object/body/garment layers.
        alpha=np.clip(1-np.median(w-b,axis=2),0,1)
        alpha[alpha<2/255]=0
        rgb=np.clip(b/np.maximum(alpha[:,:,None],1/255),0,1)
        rgba=np.concatenate([rgb,alpha[:,:,None]],axis=2)
        target=d/f'{2*i+1:02}.png'
        Image.fromarray(np.uint8(np.rint(rgba*255))).save(target)
        images[0].save(d/f'{2*i:02}.png')
        records.append({'state':state,'between':[i,(i+1)%16],'midpoint':target.name,'sourceHashes':[hashlib.sha256(f.read_bytes()).hexdigest() for f in sources],'method':'RIFE4.6 CPU midpoint + paired black/white alpha reconstruction','independentlyDrawn':False})
        (OUT/'progress.json').write_text(json.dumps({'phase':'pilot' if args.pilot else 'production','model':args.model,'completedPairs':records},indent=2))
        print(state,i,'midpoint generated',flush=True)
    if args.pilot:
        i=list(indices)[0]
        for label,bgcolor in [('dark','#181827'),('white','#fffdf8')]:
            board=Image.new('RGBA',(672,320),bgcolor)
            files=[BASE/state/f'{i:02}.png',d/f'{2*i+1:02}.png',BASE/state/f'{(i+1)%16:02}.png']
            for k,f in enumerate(files):board.alpha_composite(Image.open(f).convert('RGBA').resize((224,320),Image.Resampling.LANCZOS),(k*224,0))
            board.convert('RGB').save(d/f'pilot-{label}.png')
print('Done',len(records),'midpoints')
