from pathlib import Path
from PIL import Image
import torch, numpy as np, json, argparse

p=Path(__file__).resolve().parent;base=p.parent/'integrated-repair-v27'
parser=argparse.ArgumentParser();parser.add_argument('--all',action='store_true');args=parser.parse_args()
device='mps' if torch.backends.mps.is_available() else 'cpu'
torch.set_num_threads(4)
model=torch.jit.load(str(p/'vendor/film_net_fp32.pt'),map_location='cpu').eval().to(device)
print('FILM device',device,flush=True)
records=[]
for state,indices in [('waving',range(16) if args.all else [1]),('waiting',range(16) if args.all else [8])]:
 d=p/'film'/state;d.mkdir(parents=True,exist_ok=True)
 for i in indices:
  ims=[Image.open(base/state/f'{j:02}.png').convert('RGBA') for j in [i,(i+1)%16]]
  predictions=[]
  for theme,color in [('black','black'),('white','white')]:
   target=d/f'{i:02}-{theme}.png'
   if target.exists():out=np.asarray(Image.open(target).convert('RGB'),dtype=np.float32)/255
   else:
    tensors=[]
    for im in ims:
     bg=Image.new('RGBA',im.size,color);bg.alpha_composite(im)
     tensors.append(torch.from_numpy(np.asarray(bg.convert('RGB'),dtype=np.float32)/255).permute(2,0,1)[None].to(device))
    with torch.inference_mode():
     out=model(tensors[0],tensors[1],tensors[0].new_full((1,1),.5)).clamp(0,1)[0].permute(1,2,0).cpu().numpy()
    Image.fromarray(np.uint8(np.rint(out*255))).save(target)
   predictions.append(out)
  b,w=predictions;a=np.clip(1-np.median(w-b,axis=2),0,1);a[a<2/255]=0
  rgb=np.clip(b/np.maximum(a[:,:,None],1/255),0,1)
  Image.fromarray(np.uint8(np.rint(np.concatenate([rgb,a[:,:,None]],axis=2)*255))).save(d/f'{2*i+1:02}.png')
  ims[0].save(d/f'{2*i:02}.png')
  records.append({'state':state,'pair':i,'model':'FILM','device':device})
  (p/'film/progress.json').write_text(json.dumps(records,indent=2))
  print(state,i,'FILM midpoint generated',flush=True)
  if not args.all:
   for theme,color in [('dark','#181827'),('white','#fffdf8')]:
    board=Image.new('RGBA',(672,320),color)
    for k,f in enumerate([base/state/f'{i:02}.png',d/f'{2*i+1:02}.png',base/state/f'{(i+1)%16:02}.png']):board.alpha_composite(Image.open(f).convert('RGBA').resize((224,320),Image.Resampling.LANCZOS),(k*224,0))
    board.convert('RGB').save(d/f'pilot-{theme}.png')
