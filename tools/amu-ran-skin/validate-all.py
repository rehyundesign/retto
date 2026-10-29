"""Structural delivery checks. Visual/anatomy judgments are recorded separately."""
from pathlib import Path
from PIL import Image
import numpy as np
import hashlib,json,subprocess
root=Path(__file__).resolve().parent;repo=root.parents[1]
config=json.loads((root/'review-config.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
states=[]
for entry in config:
 r=root/entry['path'];images=[Image.open(r/'character'/f'F{i:02}.png').convert('RGBA') for i in range(16)]
 assert all(im.size==(448,640) for im in images)
 assert len({hashlib.sha256(im.tobytes()).hexdigest() for im in images})==16,entry['id']
 assert len({sha(r/'raw'/f'F{i:02}.png') for i in range(16)})==16,entry['id']
 for theme in ['light','dark']:
  path=r/f"{entry['id']}-{theme}.gif";gif=Image.open(path);seconds=0
  for i in range(gif.n_frames):gif.seek(i);seconds+=gif.info['duration']/1000
  expected={'idle':16,'drag-right':8,'drag-left':8,'waving':24,'jumping':24,'failed':16,'waiting':16,'running':24,'review':16,'sleeping':32}[entry['id']]
  assert abs(seconds-expected)<1e-6,(entry['id'],seconds,expected)
 for layer in ['back','front']:
  for i in range(80):
   im=Image.open(r/('effect_'+layer)/f'{i:03}.png').convert('RGBA');assert im.size==(448,640)
   bb=im.getchannel('A').getbbox();assert not bb or (min(bb[:2])>=12 and bb[2]<=436 and bb[3]<=628),(entry['id'],layer,i,bb)
 for i in range(8):assert Image.open(r/'companion'/f'R{i:02}.png').size==(90,90)
 states.append({'id':entry['id'],'row':entry['row'],'drawings':16,'unique_sources':16,'unique_decoded_cells':16,'cycle_seconds':entry['cycle'],'effects_samples_per_layer':80,'effects_hz':10,'checks':'pass'})
for costume in ['school','heart']:
 r=root/'motion'/f'gaze-{costume}-v2';records=json.loads((r/'registration.json').read_text());assert len(records)==16
 assert all(x['natural_outline_preserved'] and not x['regional_face_trims'] and not x['head_body_compositing'] and x['entire_cell_one_source'] for x in records)
 pixels=[]
 for record in records:
  i=record['direction'];source=Image.open(repo/'tools/amu-ran-skin'/record['source'].split('/tools/amu-ran-skin/',1)[-1]).convert('RGBA');source.thumbnail((448,640),Image.Resampling.LANCZOS)
  canvas=Image.new('RGBA',(448,640));canvas.alpha_composite(source,((448-source.width)//2,(640-source.height)//2))
  s=record['whole_character_scale'];dx,dy=record['whole_character_translation']
  expected=np.array(canvas.transform((448,640),Image.Transform.AFFINE,(1/s,0,-dx/s,0,1/s,-dy/s),Image.Resampling.BICUBIC));expected[expected[:,:,3]==0,:3]=0
  actual=np.array(Image.open(r/'character'/f'G{i:02}.png').convert('RGBA'))
  assert np.array_equal(expected,actual),(costume,i,'whole-source integrity')
  assert abs(record['output_feet']['baseline']-record['base_feet']['baseline'])<=1,(costume,i,'grounded feet')
  pixels.append(actual.tobytes())
 assert len(set(pixels))==16
manifest=json.loads((root/'native/resources.json').read_text());assert len(manifest['files'])==1825
for item in manifest['files']:
 p=repo/item['destination'];assert sha(p)==item['sha256']==sha(repo/item['source']),item['destination']
 if p.suffix=='.png':
  with Image.open(p) as im:im.verify()
 else:assert len(json.loads(p.read_text())['rows'])==10
atlas=Image.open(repo/'assets/spritesheet-amu-ran.webp').convert('RGBA');assert atlas.size==(7168,7680)
for row in range(12):
 for i in range(16):
  name=f'gaze-{"school" if row==9 else "heart"}-{i}.png' if row in [9,10] else f'character-{row}-{i}.png'
  source=np.array(Image.open(repo/'assets/amu-ran-frames'/name).convert('RGBA'));cell=np.array(atlas.crop((i*448,row*640,(i+1)*448,(row+1)*640)))
  assert np.array_equal(source[:,:,3],cell[:,:,3]) and np.array_equal(source[:,:,:3][source[:,:,3]>0],cell[:,:,:3][source[:,:,3]>0]),name
approved=[f'tools/amu-ran-skin/motion/{d}/character' for d in ['idle-v2','drag-right-v1','drag-left-v1']]
assert subprocess.run(['git','diff','--quiet','HEAD','--',*approved],cwd=repo).returncode==0
report={'structural_checks':'pass','states':states,'character_cells':160,'gaze_cells':32,'effect_cells':1600,'companion_cells':32,'native_resources':1825,'approved_character_hashes_preserved':True,'atlas_visible_pixels_equal_native_cells':True,'gaze_construction':'32 independent complete-source seated cells; no head/body compositing','original_mask_certification':False,'proportion_scope':'original Retto neutral volume; user permits Hana-level pose/costume adaptations; pose-specific original diagnostics retained','visual_review':'see visual-review.json','native_build':'reported separately','installed':False}
(root/'validation-all.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:10x16 independent cells,32 gaze,1600 effects,32 companions;1825 hashes;192 atlas cell matches;approved characters unchanged')
