from pathlib import Path
import subprocess,json,hashlib
p=Path(__file__).resolve().parent;exe=p/'Retto.app/Contents/MacOS/Retto'
r={}
for flag in ['--jeanne-self-test','--self-test','--hana-self-test','--pichi-self-test','--chocolat-self-test']:
 a=subprocess.run([str(exe),flag],capture_output=True,text=True);r[flag]={'exit':a.returncode,'output':(a.stdout+a.stderr)[-4500:]}
 print(flag,a.returncode,(a.stdout+a.stderr)[-250:])
a=subprocess.run([str(exe),'--render-jeanne-preview',str(p/'native-preview.png')],capture_output=True,text=True);r['nativeRender']={'exit':a.returncode,'output':(a.stdout+a.stderr)[-1500:]}
r['binary']=hashlib.sha256(exe.read_bytes()).hexdigest();(p/'build-checks.json').write_text(json.dumps(r,indent=2))
assert all(v['exit']==0 for v in r.values() if isinstance(v,dict)),r
