from pathlib import Path
import subprocess,json,hashlib,shutil,zipfile,time
p=Path(__file__).resolve().parent; app=Path('/Users/luxia/Applications/Retto.app'); stage=p/'Retto.app'
def hashes(d):return {str(f.relative_to(d)):hashlib.sha256(f.read_bytes()).hexdigest() for f in d.rglob('*') if f.is_file()}
before=json.loads((p/'installed-before.json').read_text());assert hashes(app)==before,'Installed app changed during preparation; installation cancelled'
assert all(x['exit']==0 for x in json.loads((p/'checks.json').read_text()))
backup=p/'installed-before-v40.zip';assert not backup.exists()
with zipfile.ZipFile(backup,'w',zipfile.ZIP_DEFLATED) as z:
 for rel in before:
  if rel.startswith('Contents/Resources/JeanneFrames/') or rel.startswith('Contents/_CodeSignature/') or rel in ['Contents/MacOS/Retto','Contents/Info.plist']:z.write(app/rel,rel)
exe=app/'Contents/MacOS/Retto'
processes=subprocess.check_output(['ps','-axo','pid=,comm='],text=True)
pids=[]
for line in processes.splitlines():
 parts=line.strip().split(None,1)
 if len(parts)==2 and parts[1]==str(exe):pids.append(int(parts[0]))
for pid in pids:subprocess.run(['kill','-TERM',str(pid)],check=True)
time.sleep(1)
shutil.copy2(stage/'Contents/MacOS/Retto',exe)
shutil.copytree(stage/'Contents/Resources/JeanneFrames',app/'Contents/Resources/JeanneFrames',dirs_exist_ok=True)
subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
after=hashes(app)
protected=[r for r in before if r.startswith('Contents/Resources/') and not r.startswith('Contents/Resources/JeanneFrames/')]
assert all(after[r]==before[r] for r in protected)
for r,h in hashes(stage/'Contents/Resources/JeanneFrames/v40').items():assert after['Contents/Resources/JeanneFrames/v40/'+r]==h
assert (app/'Contents/Resources/JeanneFrames/manifest.json').read_bytes()==(stage/'Contents/Resources/JeanneFrames/manifest.json').read_bytes()
for flag in ['--jeanne-self-test','--jeanne-effects-self-test','--jeanne-state-self-test','--self-test']:
 q=subprocess.run([str(exe),flag],capture_output=True,text=True,timeout=120);assert q.returncode==0,(flag,q.stderr);print(flag,'PASS',flush=True)
subprocess.run(['open',str(app)],check=True)
(p/'installation.json').write_text(json.dumps({'installed':str(app),'version':40,'protectedResources':len(protected),'protectedResourcesUnchanged':True,'nativeChecksPassed':True,'legacyGazePreserved':True,'backup':str(backup),'stoppedPIDs':pids,'time':time.time()},indent=2))
print('Installed v40; other resources preserved',len(protected))
