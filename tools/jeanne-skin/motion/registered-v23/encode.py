from PIL import Image
from pathlib import Path
import json
p=Path(__file__).parent;root=p.parent
for row in json.loads((p/'rows.json').read_text()):
 if not row['files'][0].startswith('registered-v23/'):continue
 for theme,color in [('dark','#181827'),('white','#fffdf8')]:
  frames=[]
  for f in row['files']:
   im=Image.open(root/f).convert('RGBA').resize((224,320),Image.Resampling.LANCZOS);bg=Image.new('RGBA',im.size,color);bg.alpha_composite(im);frames.append(bg.convert('RGB'))
  out=p/row['id']/('animation-'+theme+'.webp');frames[0].save(out,save_all=True,append_images=frames[1:],duration=[round(t*1000) for t in row['times']] if row.get('times') else round(row['cycle']*1000/16),loop=0,lossless=True);check=Image.open(out);assert check.n_frames==16
 print(row['id'],16,'frames',row['cycle'],'seconds')
for row in json.loads((p/'rows.json').read_text()):
 for f in row['files']+[a['file'] for a in row['animations']]:assert (root/f).is_file(),f
print('All preview image and animation paths exist')
