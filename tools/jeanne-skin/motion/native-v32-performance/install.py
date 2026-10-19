from pathlib import Path
import json,hashlib,subprocess,shutil,zipfile
p=Path(__file__).resolve().parent;stage=p/'Retto.app';app=Path('/Users/luxia/Applications/Retto.app');h=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
checks=json.loads((p/'build-checks.json').read_text());assert all(v['exit']==0 for v in checks.values() if isinstance(v,dict))
assert h(app/'Contents/MacOS/Retto')=='04b87c3132e8394c00e0c7fdf0f229d5b04e00b794f2f351c33af5bfbcac1b8e','Installed executable changed'
lock={str(f.relative_to(app)):h(f) for f in (app/'Contents/Resources').rglob('*') if f.is_file()}
for f,sha in lock.items():assert h(stage/f)==sha,f
backup=p/'before-performance.zip';assert not backup.exists()
with zipfile.ZipFile(backup,'w',zipfile.ZIP_DEFLATED) as z:
 for f in ['Contents/MacOS/Retto','Contents/Info.plist','Contents/_CodeSignature/CodeResources']:z.write(app/f,f)
subprocess.run(['/usr/bin/pkill','-x','Retto'],check=False)
for f in ['Contents/MacOS/Retto','Contents/Info.plist']:shutil.copy2(stage/f,app/f)
subprocess.run(['/usr/bin/codesign','--force','--deep','--sign','-',str(app)],check=True)
subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)],check=True)
for f,sha in lock.items():assert h(app/f)==sha,f
r={'signature':'verified','unchangedResourceFiles':len(lock),'installedExecutableMatchesBuild':h(app/'Contents/MacOS/Retto')==h(stage/'Contents/MacOS/Retto'),'backup':str(backup)}
(p/'installation.json').write_text(json.dumps(r,indent=2));print(json.dumps(r))
