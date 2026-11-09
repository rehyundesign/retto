from pathlib import Path
import subprocess,json
ROOT=Path(__file__).resolve().parent;binary=ROOT/'build/Retto.app/Contents/MacOS/Retto';out=[]
for flag in ['--angel-self-test','--angel-state-self-test','--self-test-all-skins','--self-test','--amu-random-state-test']:
 p=subprocess.run([str(binary),flag],capture_output=True,text=True,timeout=180);out.append({'flag':flag,'exit':p.returncode,'output':(p.stdout+p.stderr)[-5000:]});(ROOT/'review/tests.json').write_text(json.dumps(out,indent=2)+'\n');print(flag,p.returncode,(p.stdout+p.stderr)[-450:],flush=True)
 if p.returncode:raise SystemExit(1)
for t in [0,0.9,1.65]:
 p=subprocess.run([str(binary),'--render-angel-preview',str(ROOT/'review'/f'native-{round(t*1000):04}.png'),str(t)],capture_output=True,text=True,timeout=180);assert p.returncode==0,(p.stdout+p.stderr)[-800:]
print('PASS Native7-state+review fixtures rendered3times',flush=True)
