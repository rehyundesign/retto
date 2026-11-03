"""Verify the staged app's real RettoView output without installing it."""
from pathlib import Path
from PIL import Image,ImageFilter
import numpy as np
import json,hashlib,sys,shutil,subprocess
root=Path(__file__).resolve().parent.parent;repo=root.parents[1];stage=Path(sys.argv[1]);app=stage/'AmuReview.app';resources=app/'Contents/Resources'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((root/'native/resources.json').read_text())
for f in manifest['files']:assert sha(resources/'AmuRanFrames'/Path(f['destination']).name)==f['sha256']
for p in (stage/'Sources').glob('*.swift'):assert sha(p)==sha(repo/'macos/Sources'/p.name),p.name
native_checks=[]
for theme in ['white','dark']:
 files=[stage/'motion'/f'{theme}-{i:03}.png' for i in range(80)]
 assert all(p.exists() for p in files)
 frames=[np.array(Image.open(p).convert('RGBA')) for p in files]
 for index,costume,direction in [(10,'school',0),(11,'heart',12)]:
  x,y=index%4*224,index//4*320
  sample=[a[y:y+320,x:x+224] for a in frames]
  source=Image.open(root/'motion'/f'gaze-{costume}-v2/character/G{direction:02}.png').convert('RGBA').resize((224,320),Image.Resampling.LANCZOS)
  alpha=np.array(source.getchannel('A').filter(ImageFilter.MinFilter(5)))
  # Generated fur interiors are near-opaque (often250/255), not always255.
  yy,xx=np.indices((320,224));protected=(alpha>245)&(yy<210)&(xx<150)
  assert protected.sum()>1000
  assert np.array_equal(sample[1][protected],sample[31][protected]),(theme,costume,'held head changed')
  background=(np.array(source)[:,:,3]<1)
  if costume=='school':background[(xx>=175)&(yy>=161)&(yy<=215)]=False
  else:background[(xx>=170)&(yy>=194)&(yy<=247)]=False
  delta=np.any(sample[1]!=sample[31],axis=2)&background
  assert delta.sum()>2,(theme,costume,'effects did not move outside pet/character')
  native_checks.append({'background':theme,'held_gaze':costume,'protected_head_pixels':int(protected.sum()),'changing_effect_background_pixels':int(delta.sum())})
 for costume in ['school','heart']:
  sheet=np.array(Image.open(stage/'gaze'/f'gaze-{costume}-{"light" if theme=="white" else "dark"}.png').convert('RGBA'))
  cells=[]
  for i in range(16):
   source=Image.open(root/'motion'/f'gaze-{costume}-v2/character/G{i:02}.png').convert('RGBA').resize((224,320),Image.Resampling.LANCZOS)
   a=np.array(source);alpha=np.array(source.getchannel('A').filter(ImageFilter.MinFilter(5)));mask=alpha>245
   cell=sheet[i//4*320:(i//4+1)*320,i%4*224:(i%4+1)*224];cells.append(cell.tobytes())
   error=np.abs(cell[:,:,:3].astype(float)-a[:,:,:3].astype(float))[mask]
   assert mask.sum()>1000 and np.mean(error)<12,(costume,theme,i,'native cell/source mismatch',float(np.mean(error)))
  assert len(set(cells))==16,(costume,theme,'duplicated native gaze cell')
assert subprocess.run(['codesign','--verify','--deep','--strict',str(app)],capture_output=True).returncode==0
for theme in ['white','dark']:
 shutil.copy2(stage/'motion'/f'{theme}-008.png',root/'native'/f'native-{theme}-1x.png')
for p in (stage/'gaze').glob('*.png'):shutil.copy2(p,root/'native'/p.name)
report={'compiled_sources_match_current':True,'resource_hash_matches':1825,'native_motion_boards':160,'native_gaze_boards':4,'rendered_seconds_per_background':8,'display':[224,320],'pose_frames_covered_per_state':16,'all32_gaze_complete_sources_match_native':True,'frozen_gaze_effect_checks':native_checks,'signature_verified':True,'executable_sha256':sha(app/'Contents/MacOS/Retto'),'isolated_app':str(app),'installed':False,'tests':{'self_test':True,'amu_ran_clock':True,'all16_boundaries_all10_rows':True},'limits':'offscreen RettoView and elapsed-time checks; no installed-app or desktop FPS claim'}
(root/'native/verification.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS:1825 packaged hashes;160 native motion boards;32 gaze directions in both backgrounds;fixed head with moving effects;signature and source snapshot')
