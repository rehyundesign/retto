from pathlib import Path
import subprocess,json,hashlib
p=Path(__file__).resolve().parent; app=p/'Retto.app'; exe=app/'Contents/MacOS/Retto'
r=[]
for flag in ['--jeanne-self-test','--jeanne-effects-self-test','--jeanne-state-self-test','--jeanne-fit-self-test','--discovery-cache-self-test','--hana-self-test','--pichi-self-test','--chocolat-self-test','--self-test']:
 q=subprocess.run([str(exe),flag],capture_output=True,text=True,timeout=120)
 r.append({'check':flag,'exit':q.returncode,'output':q.stdout[-12000:],'stderr':q.stderr[-2000:]});print(flag,q.returncode,flush=True)
q=subprocess.run([str(exe),'--render-jeanne-preview',str(p/'native-preview.png')],capture_output=True,text=True,timeout=120)
r.append({'check':'native-render','exit':q.returncode,'stderr':q.stderr[-2000:]})
(p/'checks.json').write_text(json.dumps(r,ensure_ascii=False,indent=2));assert all(x['exit']==0 for x in r)
