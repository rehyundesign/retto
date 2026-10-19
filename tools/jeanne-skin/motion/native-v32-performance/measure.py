from pathlib import Path
import subprocess,time,json,sys
p=Path(__file__).parent
pid=subprocess.check_output(['/usr/bin/pgrep','-x','Retto'],text=True).strip().splitlines();assert len(pid)==1,pid
pid=pid[0]
def cpu():
 s=subprocess.check_output(['/bin/ps','-p',pid,'-o','time='],text=True).strip();parts=s.replace('-',':').split(':');v=0.0
 for x in parts:v=v*60+float(x)
 return v
samples=[]
for _ in range(2):
 a=cpu();start=time.monotonic();time.sleep(3);b=cpu();elapsed=time.monotonic()-start;samples.append(round((b-a)/elapsed*100,2))
r={'pid':pid,'intervalSeconds':3,'cpuPercentOneCore':samples,'mean':sum(samples)/len(samples)}
(p/(sys.argv[1]+'.json')).write_text(json.dumps(r,indent=2));print(json.dumps(r))
