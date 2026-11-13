from pathlib import Path
import subprocess,json,hashlib,shutil
R=Path(__file__).resolve().parent;W=R/'build';APP=Path.home()/'Applications/Retto.app';C=W/'Retto.app'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
b=json.loads((R/'baseline.json').read_text());assert sha(APP/'Contents/MacOS/Retto')==b['binary_sha256'],'Installed app changed; recover latest source before building'
if not C.exists():subprocess.run(['cp','-cR',str(APP),str(C)],check=True)
if (W/'AngelInteractions').exists():shutil.copytree(W/'AngelInteractions',C/'Contents/Resources/AngelInteractions',dirs_exist_ok=True)
a=['swiftc','-O','-whole-module-optimization','-module-name','Retto','-module-cache-path',str(W/'module-cache'),'-target','arm64-apple-macos13.0','-framework','AppKit','-framework','ServiceManagement',*map(str,sorted((W/'Sources').glob('*.swift'))),'-o',str(C/'Contents/MacOS/Retto')]
p=subprocess.run(a,capture_output=True,text=True);(W/'build.log').write_text(p.stdout+p.stderr)
if p.returncode:print(p.stderr[-7000:]);raise SystemExit(p.returncode)
subprocess.run(['/usr/libexec/PlistBuddy','-c','Set :RettoBuildStamp local-angel-interactions-20261106',str(C/'Contents/Info.plist')],check=True)
for a in [['codesign','--force','--deep','--sign','-',str(C)],['codesign','--verify','--deep','--strict',str(C)]]:subprocess.run(a,check=True,capture_output=True)
for name,h in b['resources'].items():assert sha(C/'Contents/Resources'/name)==h,name
(R/'candidate.json').write_text(json.dumps({'candidate':str(C),'binary_sha256':sha(C/'Contents/MacOS/Retto'),'all_prior_resources_preserved':len(b['resources']),'patched_sources':{f.name:sha(f) for f in (W/'Sources').glob('*.swift')},'signed':True},indent=2)+'\n');print('Build/sign passed, protected resources',len(b['resources']))

shutil.copy2(R/'candidate.json',R/'stage.json')
