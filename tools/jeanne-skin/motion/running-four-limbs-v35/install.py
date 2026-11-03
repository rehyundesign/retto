from pathlib import Path
import json,hashlib,zipfile,subprocess,shutil,struct
p=Path(__file__).resolve().parent;app=Path('/Users/luxia/Applications/Retto.app');res=app/'Contents/Resources';h=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
review=json.loads((p/'anatomy-review.json').read_text());assert review['approvedFrames']==list(range(16)) and review['nativeReady']
lock=json.loads((p/'installed-lock.json').read_text());original={r['file']:r['sha256'] for r in lock['resources']}
for i in range(16):assert h(res/'JeanneFrames'/f'character-7-{i}.png')==original[f'JeanneFrames/character-7-{i}.png'],'Running art changed concurrently'
m=json.loads((res/'JeanneFrames/manifest.json').read_text());running=next(s for s in m['states'] if s['id']=='running');assert running['row']==7 and len(running['files'])==16 and abs(running['cycle']-2.4)<1e-8
protected={str(f.relative_to(res)):h(f) for f in res.rglob('*') if f.is_file() and str(f.relative_to(res)) not in {f'JeanneFrames/character-7-{i}.png' for i in range(16)}}
def machine_code(f):
 b=f.read_bytes();n=struct.unpack_from('<I',b,16)[0];o=32
 for _ in range(n):
  cmd,size=struct.unpack_from('<II',b,o)
  if cmd==0x19:
   for k in range(struct.unpack_from('<I',b,o+64)[0]):
    a=o+72+80*k
    if b[a:a+16].split(b'\0')[0]==b'__text':
     sz=struct.unpack_from('<Q',b,a+40)[0];offset=struct.unpack_from('<I',b,a+48)[0];return hashlib.sha256(b[offset:offset+sz]).hexdigest()
  o+=size
 raise AssertionError('Missing code section')
code=machine_code(app/'Contents/MacOS/Retto');backup=p/'before-running-repair.zip';assert not backup.exists()
with zipfile.ZipFile(backup,'w',zipfile.ZIP_DEFLATED) as z:
 for f in ['Contents/MacOS/Retto','Contents/_CodeSignature/CodeResources']+[f'Contents/Resources/JeanneFrames/character-7-{i}.png' for i in range(16)]:z.write(app/f,f)
subprocess.run(['/usr/bin/pkill','-x','Retto'],check=False)
for i in range(16):shutil.copy2(p/f'{i:02}.png',res/'JeanneFrames'/f'character-7-{i}.png')
subprocess.run(['/usr/bin/codesign','--force','--deep','--sign','-',str(app)],check=True)
subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)],check=True)
assert machine_code(app/'Contents/MacOS/Retto')==code
for f,sha in protected.items():assert h(res/f)==sha,f
for i in range(16):assert h(res/'JeanneFrames'/f'character-7-{i}.png')==h(p/f'{i:02}.png')
(p/'installation.json').write_text(json.dumps({'runningFramesReplaced':16,'unchangedResources':len(protected),'executableCodeUnchanged':True,'timingUnchanged':True,'signature':'verified','backup':str(backup)},indent=2));print('Only running16 cells replaced; other resources and executable code preserved')
