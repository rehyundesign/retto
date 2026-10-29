"""Stage the current source with installed skins preserved; does not install or restart."""
from pathlib import Path
import hashlib, json, shutil, subprocess, tempfile
repo = Path(__file__).resolve().parents[3]
installed = Path.home()/'Applications/Retto.app'
root = Path(tempfile.mkdtemp(prefix='retto-amu-install-', dir='/private/tmp'))
src = root/'Sources'
shutil.copytree(repo/'macos/Sources',src)
app = root/'Retto.app';shutil.copytree(installed,app)
resources = app/'Contents/Resources'
shutil.copy2(repo/'assets/spritesheet-amu-ran.webp',resources)
shutil.copytree(repo/'assets/amu-ran-frames',resources/'AmuRanFrames',dirs_exist_ok=True)
subprocess.run(['swiftc','-O','-module-cache-path',str(root/'module-cache'),'-target','arm64-apple-macos13.0','-framework','AppKit','-framework','ServiceManagement',*map(str,sorted(src.glob('*.swift'))),'-o',str(app/'Contents/MacOS/Retto')],check=True)
subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
old={str(p.relative_to(installed/'Contents/Resources')):digest(p) for p in (installed/'Contents/Resources').rglob('*') if p.is_file() and 'AmuRanFrames' not in p.parts and p.name!='spritesheet-amu-ran.webp'}
assert all(digest(resources/p)==h for p,h in old.items())
(root/'build-verification.json').write_text(json.dumps({'preserved_resource_files':len(old),'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'installed':False},indent=2)+'\n')
print(root,flush=True)
