from pathlib import Path
import subprocess,json
R=Path(__file__).resolve().parent;B=R/'build/Retto.app/Contents/MacOS/Retto';O=R/'review';O.mkdir(exist_ok=True)
flags=['--angel-self-test','--angel-state-self-test','--angel-interactions-self-test','--angel-interactions-state-test','--self-test-all-skins','--amu-approved-state-test']
results=[]
for flag in flags:
 p=subprocess.run([str(B),flag],capture_output=True,text=True,timeout=120)
 results.append({'flag':flag,'exit':p.returncode,'output':(p.stdout+p.stderr)[-7000:]});print(flag,p.returncode,(p.stdout+p.stderr)[-1000:])
(O/'tests.json').write_text(json.dumps(results,indent=2)+'\n')
assert all(z['exit']==0 for z in results)
p=subprocess.run([str(B),'--render-angel-interactions',str(O/'native')],capture_output=True,text=True,timeout=180)
(O/'render.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stderr
print('Native interaction renders saved')
