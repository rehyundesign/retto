"""Persist each finished built-in image request immediately, including after later interrupts."""
from pathlib import Path
import json,shutil,hashlib,sys,fcntl
request=Path(sys.argv[1]);source=Path(sys.argv[2]);job=json.loads(request.read_text())
r=request.parent.parent;target=r/'raw'/(job['id']+'.png')
if target.exists():
 h=hashlib.sha256(target.read_bytes()).hexdigest()[:10];shutil.copy2(target,r/'rejected'/(job['id']+'-'+h+'.png'))
shutil.copy2(source,target)
record={**job,'generated_path':str(source),'source_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'generator':'built-in image_gen'}
with (r/'generation-records.jsonl').open('a') as f:
 fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(record,ensure_ascii=False)+'\n');f.flush();fcntl.flock(f,fcntl.LOCK_UN)
print(str(target))
