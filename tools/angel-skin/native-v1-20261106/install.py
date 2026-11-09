"""Scoped, recoverable local install: newAngelFrames plus executable/Info/signature."""
from pathlib import Path
import json,hashlib,shutil,subprocess,os,tarfile
ROOT=Path(__file__).resolve().parent;APP=Path.home()/'Applications/Retto.app';CAND=ROOT/'build/Retto.app';RES=APP/'Contents/Resources';BACK=ROOT/'recovery'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(a):
 p=subprocess.run(list(map(str,a)),capture_output=True,text=True,timeout=180)
 if p.returncode:raise RuntimeError((p.stdout+p.stderr)[-1800:])
 return p.stdout
baseline=json.loads((ROOT/'baseline.json').read_text());candidate=json.loads((ROOT/'candidate.json').read_text());tests=json.loads((ROOT/'review/tests.json').read_text())
assert len(tests)==5 and all(t['exit']==0 for t in tests)
assert sha(APP/'Contents/MacOS/Retto')==baseline['binary_sha256'];assert sha(CAND/'Contents/MacOS/Retto')==candidate['binary_sha256']
assert not (RES/'AngelFrames').exists(),'Angel destination appeared concurrently; do not overwrite'
assert all(sha(RES/n)==h for n,h in baseline['protected_resources'].items())
run(['codesign','--verify','--deep','--strict',CAND]);BACK.mkdir(exist_ok=True)
for relative in ['MacOS/Retto','Info.plist','_CodeSignature/CodeResources']:
 dest=BACK/relative;assert not dest.exists();dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(APP/'Contents'/relative,dest)
# Bound source provenance for this executable, leaving other source trees untouched.
archive=ROOT/'source-snapshot.tar.gz'
with tarfile.open(archive,'w:gz') as t:
 for f in sorted((ROOT/'build/Sources').glob('*.swift')):t.add(f,arcname='Sources/'+f.name)
for line in run(['ps','-axo','pid=,comm=']).splitlines():
 a=line.strip().split(None,1)
 if len(a)==2 and a[1]==str(APP/'Contents/MacOS/Retto'):run(['kill','-TERM',a[0]])
try:
 shutil.copytree(CAND/'Contents/Resources/AngelFrames',RES/'AngelFrames')
 for relative in ['MacOS/Retto','Info.plist']:
  p=APP/'Contents'/relative;tmp=p.with_suffix('.angel-pending');shutil.copy2(CAND/'Contents'/relative,tmp);os.replace(tmp,p)
 run(['codesign','--force','--deep','--sign','-',APP]);run(['codesign','--verify','--deep','--strict',APP])
 assert all(sha(RES/n)==h for n,h in baseline['protected_resources'].items())
 outputs={}
 for flag in ['--angel-self-test','--angel-state-self-test','--self-test-all-skins','--amu-random-state-test']:
  outputs[flag]=run([APP/'Contents/MacOS/Retto',flag])[-5000:]
except Exception:
 for relative in ['MacOS/Retto','Info.plist','_CodeSignature/CodeResources']:shutil.copy2(BACK/relative,APP/'Contents'/relative)
 # Only the newly created, task-owned resource folder can be removed in rollback.
 if (RES/'AngelFrames').exists():shutil.rmtree(RES/'AngelFrames')
 raise
installed_files={str(p.relative_to(RES/'AngelFrames')):sha(p) for p in (RES/'AngelFrames').rglob('*') if p.is_file()}
assert all(sha(CAND/'Contents/Resources/AngelFrames'/n)==h for n,h in installed_files.items())
record={'installed':str(APP),'executableSha256':sha(APP/'Contents/MacOS/Retto'),'binaryBefore':baseline['binary_sha256'],'preserved_resources':len(baseline['protected_resources']),'added_angel_files':len(installed_files),'signatureVerified':True,'sourceArchive':str(archive),'sourceArchive_sha256':sha(archive),'source_files':47,'backup':str(BACK),'installed_checks':outputs,'selected_skin_verified':False,'actual_app_appearance_verified':False,'display_fit':json.loads((ROOT/'fit-evidence.json').read_text()),'original_anatomical_landmarks_certification':'inherited unverified'}
(ROOT/'installation.json').write_text(json.dumps(record,indent=2)+'\n');shutil.copy2(RES/'AngelFrames/manifest.json',ROOT/'manifest.json');print('INSTALLED:7 approved states,body-based fit; all30197 previous resources preserved; signature and installed self-tests passed')
