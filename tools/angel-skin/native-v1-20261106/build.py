from pathlib import Path
import subprocess,json,hashlib,shutil
ROOT=Path(__file__).resolve().parent;W=ROOT/'build';APP=Path.home()/'Applications/Retto.app';CAND=W/'Retto.app'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
baseline=json.loads((ROOT/'baseline.json').read_text());assert sha(APP/'Contents/MacOS/Retto')==baseline['binary_sha256'],'Installed binary changed during work'
if not CAND.exists():subprocess.run(['cp','-cR',str(APP),str(CAND)],check=True)
shutil.copytree(W/'AngelFrames',CAND/'Contents/Resources/AngelFrames',dirs_exist_ok=True)
args=['swiftc','-O','-whole-module-optimization','-module-name','Retto','-module-cache-path',str(W/'module-cache'),'-target','arm64-apple-macos13.0','-framework','AppKit','-framework','ServiceManagement',*map(str,sorted((W/'Sources').glob('*.swift'))),'-o',str(CAND/'Contents/MacOS/Retto')]
p=subprocess.run(args,capture_output=True,text=True);(W/'build.log').write_text(p.stdout+p.stderr)
if p.returncode:print(p.stderr[-7000:]);raise SystemExit(p.returncode)
subprocess.run(['/usr/libexec/PlistBuddy','-c','Set :RettoBuildStamp local-angel-body-fit-20261106',str(CAND/'Contents/Info.plist')],check=True)
for args in [['codesign','--force','--deep','--sign','-',str(CAND)],['codesign','--verify','--deep','--strict',str(CAND)]]:subprocess.run(args,check=True,capture_output=True)
for name,h in baseline['protected_resources'].items():assert sha(CAND/'Contents/Resources'/name)==h,name
(ROOT/'candidate.json').write_text(json.dumps({'candidate':str(CAND.resolve()),'binary_sha256':sha(CAND/'Contents/MacOS/Retto'),'all_prior_resources_preserved':len(baseline['protected_resources']),'patched_sources':{f.name:sha(f) for f in (W/'Sources').glob('*.swift')},'signed':True},indent=2)+'\n');print('Build/sign passed; preserved prior resources',len(baseline['protected_resources']))
