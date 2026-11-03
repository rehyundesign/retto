from pathlib import Path
import subprocess,shutil,json,hashlib
p=Path(__file__).resolve().parent;stage=p/'Retto.app';target=Path('/Users/luxia/Applications/Retto.app')
h=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
checks=json.loads((p/'build-checks.json').read_text());assert all(v['exit']==0 for v in checks.values() if isinstance(v,dict))
assert h(target/'Contents/MacOS/Retto')=='eb9c4d42f8774abf005f07a9f673d19880806e504ff0a4feedc7fdfeb3bdb53d','installed executable changed since inspection'
lock=json.loads((p/'preserved-resources.json').read_text())
for r in lock:assert h(target/'Contents/Resources'/r['file'])==r['sha256'],r['file']
backup=p/'before-v31.zip';assert not backup.exists()
subprocess.run(['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',str(target),str(backup)],check=True)
subprocess.run(['/usr/bin/pkill','-x','Retto'],check=False)
shutil.copy2(stage/'Contents/MacOS/Retto',target/'Contents/MacOS/Retto')
shutil.copy2(stage/'Contents/Info.plist',target/'Contents/Info.plist')
assert not (target/'Contents/Resources/JeanneFrames').exists()
shutil.copytree(stage/'Contents/Resources/JeanneFrames',target/'Contents/Resources/JeanneFrames')
subprocess.run(['/usr/bin/codesign','--force','--deep','--sign','-',str(target)],check=True)
subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(target)],check=True)
for r in lock:assert h(target/'Contents/Resources'/r['file'])==r['sha256'],r['file']
new=[]
for f in (stage/'Contents/Resources/JeanneFrames').iterdir():
 assert h(f)==h(target/'Contents/Resources/JeanneFrames'/f.name);new.append(f.name)
r={'installed':str(target),'backup':str(backup),'preservedResources':len(lock),'jeanneResourcesVerified':len(new),'signature':'verified','binarySha256':h(target/'Contents/MacOS/Retto')}
(p/'installation.json').write_text(json.dumps(r,indent=2));print(json.dumps(r))
