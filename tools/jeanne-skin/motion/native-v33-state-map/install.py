from pathlib import Path
import json,hashlib,subprocess,shutil,zipfile
p=Path(__file__).resolve().parent;stage=p/'Retto.app';app=Path('/Users/luxia/Applications/Retto.app');h=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
checks=json.loads((p/'build-checks.json').read_text());assert all(v['exit']==0 for v in checks.values() if isinstance(v,dict))
assert h(app/'Contents/MacOS/Retto')=='165f0fc9b7558912823049b431f1b0ae79446dda13ed3884fd0a8533f514e7c6','Installed executable changed'
changed={'Contents/Resources/JeanneFrames/manifest.json'}|{f'Contents/Resources/JeanneFrames/character-{r}-{i}.png' for r in [5,7] for i in range(16)}
lock={str(f.relative_to(app)):h(f) for f in (app/'Contents/Resources').rglob('*') if f.is_file()}
for f,sha in lock.items():
 if f not in changed:assert h(stage/f)==sha,f
backup=p/'before-state-map.zip';assert not backup.exists()
files=sorted(changed)+['Contents/MacOS/Retto','Contents/Info.plist','Contents/_CodeSignature/CodeResources']
with zipfile.ZipFile(backup,'w',zipfile.ZIP_DEFLATED) as z:
 for f in files:z.write(app/f,f)
subprocess.run(['/usr/bin/pkill','-x','Retto'],check=False)
for f in sorted(changed)+['Contents/MacOS/Retto','Contents/Info.plist']:shutil.copy2(stage/f,app/f)
subprocess.run(['/usr/bin/codesign','--force','--deep','--sign','-',str(app)],check=True)
subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)],check=True)
for f,sha in lock.items():
 if f not in changed:assert h(app/f)==sha,f
for f in changed:assert h(app/f)==h(stage/f),f
r={'signature':'verified','unchangedResourceFiles':len(lock)-len(changed),'correctedJeanneResourceFiles':len(changed),'installedExecutableMatchesBuild':h(app/'Contents/MacOS/Retto')==h(stage/'Contents/MacOS/Retto'),'backup':str(backup)}
(p/'installation.json').write_text(json.dumps(r,indent=2));print(json.dumps(r))
