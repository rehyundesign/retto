#!/usr/bin/env python3
"""Build the downloadable Mac app using only versioned sources and artwork."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.11.1'
CHECKS = ['--transcript-stream-self-test', '--frame-cache-self-test', '--self-test', '--self-test-all-skins', '--self-test-slack', '--self-test-codex-input',
          '--self-test-status-rendering', '--amu-approved-self-test', '--amu-approved-state-test',
          '--amu-random-state-test', '--hachuping-self-test', '--hachuping-state-self-test',
          '--hana-self-test', '--hana-ground-self-test', '--hana-gaze-self-test',
          '--angel-self-test', '--angel-interactions-state-test', '--howl-state-self-test',
          '--jeanne-state-self-test', '--pichi-self-test', '--chocolat-self-test', '--classic-gaze-self-test']


def run(args, **kwargs):
    result = subprocess.run(list(map(str, args)), capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed\n{result.stdout[-4000:]}{result.stderr[-4000:]}')
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-only', action='store_true')
    parser.add_argument('--keep-build', action='store_true', help='Keep isolated build directory (always retained).')
    parser.add_argument('--install', action='store_true')
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix='retto-public-')).resolve()
    app = work / 'Retto.app'
    contents = app / 'Contents'
    resources = contents / 'Resources'
    binary = contents / 'MacOS/Retto'
    binary.parent.mkdir(parents=True)
    resources.mkdir()
    manifest = json.loads((ROOT / 'macos/runtime-resources.json').read_text())['resources']
    for relative, item in manifest.items():
        source = (ROOT / item['source']).resolve()
        target = resources / relative
        if not source.is_relative_to(ROOT) or not target.resolve().is_relative_to(resources):
            raise ValueError('Resource path escapes project or bundle')
        if hashlib.sha256(source.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError(f'Resource mismatch: {relative}')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    for name in ['spritesheet-rilakkuma.webp', 'spritesheet-rilakkuma-cape.webp']:
        assert (resources / name).is_file(), 'All fourteen approved skins must be included'
    hook = resources / 'hook'
    hook.mkdir()
    for name in ['hook.cjs', 'hook.sh', 'install.cjs']:
        shutil.copy2(ROOT / 'hook' / name, hook / name)
    shutil.copytree(ROOT / 'hook/lib', hook / 'lib')
    (hook / 'hook.sh').chmod(0o755)
    revision = run(['git', '-C', ROOT, 'rev-parse', 'HEAD']).strip()
    info = plistlib.loads((ROOT / 'macos/Info.plist').read_bytes())
    info.update(CFBundleShortVersionString=VERSION,
                CFBundleVersion=run(['git', '-C', ROOT, 'rev-list', '--count', 'HEAD']).strip(),
                RettoBuildStamp=f'{VERSION} · {revision[:9]}')
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    print(f'Compiling Retto {VERSION}; build directory: {work}', flush=True)
    run(['swiftc', '-O', '-whole-module-optimization', '-module-name', 'Retto',
         '-module-cache-path', work / 'module-cache', '-target', 'arm64-apple-macos13.0',
         '-framework', 'AppKit', '-framework', 'ServiceManagement',
         *sorted((ROOT / 'macos/Sources').glob('*.swift')), '-o', binary])
    run(['codesign', '--force', '--deep', '--sign', '-', app])
    run(['codesign', '--verify', '--deep', '--strict', app])

    def check(flag):
        output = run([binary, flag], timeout=240)
        (work / (flag[2:] + '.log')).write_text(output)
        print(flag + ' PASS', flush=True)

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(check, CHECKS))
    for name in ['test-codex-status-stream.py', 'test-status-reliability.py', 'test-external-read.py']:
        output = run(['python3', ROOT / 'scripts' / name, binary], timeout=240)
        (work / (name + '.log')).write_text(output)
        print(name + ' PASS', flush=True)
    report = {'version': VERSION, 'revision': revision, 'app': str(app),
              'publicResources': len(manifest), 'checks': CHECKS, 'personalSkinsExcluded': False}
    if not args.app_only:
        stage = work / f'Retto {VERSION}'
        stage.mkdir()
        shutil.copytree(app, stage / 'Retto.app')
        (stage / 'Applications').symlink_to('/Applications')
        (stage / '먼저-읽어주세요.txt').write_text(
            (ROOT / 'scripts/beta-readme.txt').read_text().replace('__VERSION__', VERSION))
        shutil.copy2(ROOT / 'scripts/doctor.command', stage / '진단.command')
        output = ROOT / 'dist'
        output.mkdir(exist_ok=True)
        # hdiutil never changes the installed app or Finder preferences.
        dmg = output / f'Retto-{VERSION}.dmg'
        if dmg.exists():
            raise FileExistsError(f'Release artifact already exists: {dmg}')
        run(['hdiutil', 'create', '-volname', f'Retto {VERSION}', '-srcfolder', stage,
             '-format', 'UDZO', '-imagekey', 'zlib-level=9', dmg], timeout=600)
        report['dmg'] = str(dmg)
        report['sha256'] = hashlib.sha256(dmg.read_bytes()).hexdigest()
        print(f'DMG: {dmg}\nSHA256: {report["sha256"]}', flush=True)
    (work / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    if args.install:
        destination = Path.home() / 'Applications/Retto.app'
        backup = work / 'Retto-before.app'
        # Retain private art on the creator’s Mac; public artifacts stay unchanged.
        local = work / 'Retto-local.app'
        shutil.copytree(app, local)
        for name in ['spritesheet-rilakkuma.webp', 'spritesheet-rilakkuma-cape.webp']:
            old = destination / 'Contents/Resources' / name
            if old.exists():
                shutil.copy2(old, local / 'Contents/Resources' / name)
        run(['codesign', '--force', '--deep', '--sign', '-', local])
        run(['codesign', '--verify', '--deep', '--strict', local])
        known = {str(destination / 'Contents/MacOS/Retto'),
                 str(ROOT / 'macos/build/Retto.app/Contents/MacOS/Retto')}
        for line in run(['ps', '-axo', 'pid=,comm=']).splitlines():
            parts = line.strip().split(None, 1)
            if len(parts) == 2 and parts[1] in known:
                run(['kill', '-TERM', parts[0]])
        if destination.exists():
            os.replace(destination, backup)
        try:
            shutil.move(local, destination)
            run(['codesign', '--verify', '--deep', '--strict', destination])
        except Exception:
            if destination.exists():
                os.replace(destination, work / 'Retto-failed.app')
            if backup.exists():
                os.replace(backup, destination)
            raise
        run(['open', '-a', destination])
    print(f'VERIFIED: {work}', flush=True)


if __name__ == '__main__':
    main()
