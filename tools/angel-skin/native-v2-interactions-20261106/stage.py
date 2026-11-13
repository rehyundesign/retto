"""Recover the exact current installed source archive; do not overwrite another runtime update."""
from pathlib import Path
import hashlib,json,tarfile,subprocess
ROOT=Path(__file__).resolve().parent;REPO=ROOT.parents[2];APP=Path.home()/'Applications/Retto.app'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
binary=sha(APP/'Contents/MacOS/Retto');matches=subprocess.check_output(['rg','-l',binary,str(REPO/'tools'),'--glob','installation.json'],text=True).splitlines();chosen=None
for name in matches:
 try:
  d=json.loads(Path(name).read_text());a=Path(d.get('sourceArchive',''));stage=Path(name).parent/'stage.json'
  if d.get('executableSha256',d.get('executable_sha256'))==binary and a.is_file() and stage.is_file():chosen=(Path(name),d,a,json.loads(stage.read_text()));break
 except (OSError,ValueError):pass
assert chosen,'No hash-bound source record for current app; keep installed app intact'
record,d,archive,prior=chosen
assert sha(archive)==d['sourceArchive_sha256'];expected=prior['patched_sources'];src=ROOT/'build/Sources';src.mkdir(parents=True,exist_ok=True)
with tarfile.open(archive) as t:
 for m in t.getmembers():
  if m.isfile() and m.name.endswith('.swift'):
   data=t.extractfile(m).read();name=Path(m.name).name;assert hashlib.sha256(data).hexdigest()==expected[name];(src/name).write_bytes(data)
resources={str(p.relative_to(APP/'Contents/Resources')):sha(p) for p in (APP/'Contents/Resources').rglob('*') if p.is_file()}
(ROOT/'baseline.json').write_text(json.dumps({'installed':str(APP),'binary_sha256':binary,'source_record':str(record),'source_archive':str(archive),'source_archive_sha256':sha(archive),'sources':expected,'resources':resources},indent=2)+'\n');print('Recovered current source files',len(expected),'protected resources',len(resources))
