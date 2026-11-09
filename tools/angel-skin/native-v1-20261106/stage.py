from pathlib import Path
import tarfile,json,hashlib,importlib.util,shutil
ROOT=Path(__file__).resolve().parent;REPO=ROOT.parents[2];APP=Path.home()/'Applications/Retto.app'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
s=importlib.util.spec_from_file_location('preserve',REPO/'tools/hachupingping-skin/native-v5-royal-companions/deliver.py');p=importlib.util.module_from_spec(s);s.loader.exec_module(p)
record=json.loads((REPO/'tools/amu-ran-skin/native-random-20261106/installation.json').read_text());assert sha(APP/'Contents/MacOS/Retto')==record['executableSha256']
archive=Path(record['sourceArchive']);assert sha(archive)==record['sourceArchive_sha256'];src=ROOT/'build/Sources';src.mkdir(parents=True,exist_ok=True)
with tarfile.open(archive) as tar:
 for m in tar.getmembers():
  if m.isfile() and m.name.endswith('.swift'):(src/Path(m.name).name).write_bytes(tar.extractfile(m).read())
expected=json.loads((REPO/'tools/amu-ran-skin/native-random-20261106/stage.json').read_text())['patched_sources'];actual={f.name:sha(f) for f in src.glob('*.swift') if f.name in expected};assert actual==expected,'Archive source hashes no longer match verified installed runtime'
resources={str(f.relative_to(APP/'Contents/Resources')):sha(f) for f in (APP/'Contents/Resources').rglob('*') if f.is_file()}
(ROOT/'baseline.json').write_text(json.dumps({'installed':str(APP),'binary_sha256':sha(APP/'Contents/MacOS/Retto'),'program_text_sha256':p.program(APP/'Contents/MacOS/Retto'),'source_archive':str(archive),'archive_sha256':sha(archive),'sources':actual,'protected_resources':resources},indent=2)+'\n');print('Recovered exact46-source installed runtime; protected resources',len(resources))
