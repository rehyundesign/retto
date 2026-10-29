"""Install a verified cache-only candidate, preserving every skin resource and setting."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time

from build import sha, run


def resources(app):
    root = app / 'Contents/Resources'
    return {str(p.relative_to(root)): sha(p) for p in root.rglob('*') if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    args = parser.parse_args()
    work = args.workspace
    evidence = json.loads((work / 'verification.json').read_text())
    assert evidence['cacheProbes']['after']['ok']
    assert evidence['cacheProbes']['after']['retainedDecodedBytes'] == 0
    checks = json.loads((work / 'checks.json').read_text())
    assert len(checks) >= 10 and all(c['exit'] == 0 for c in checks)
    app = Path(evidence['installedApp'])
    candidate = Path(evidence['candidate'])
    exe = app / 'Contents/MacOS/Retto'
    assert sha(exe) == evidence['installedBinaryBefore'], 'Installed binary changed; rebase first'
    before = json.loads((work / 'installed-before.json').read_text())
    assert {str(p.relative_to(app)): sha(p) for p in app.rglob('*') if p.is_file()} == before, 'Installed bundle changed'
    protected = resources(app)
    assert resources(candidate) == protected, 'Candidate changed skin resources'
    run(['codesign', '--verify', '--deep', '--strict', candidate])
    assert sha(candidate / 'Contents/MacOS/Retto') == evidence['candidateBinary'], 'Candidate changed after testing'
    backup = work / 'installed-backup'
    backup.mkdir(exist_ok=False)
    shutil.copy2(exe, backup / 'Retto')
    shutil.copytree(app / 'Contents/_CodeSignature', backup / '_CodeSignature')
    processes = run(['ps', '-axo', 'pid=,comm=']).stdout.splitlines()
    pids = []
    for line in processes:
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[1] == str(exe):
            pids.append(int(parts[0]))
    for pid in pids:
        run(['kill', '-TERM', pid])
    time.sleep(1)
    installed_checks = []
    try:
        shutil.copy2(candidate / 'Contents/MacOS/Retto', exe)
        run(['codesign', '--force', '--deep', '--sign', '-', app])
        run(['codesign', '--verify', '--deep', '--strict', app])
        assert resources(app) == protected
        for check in checks:
            output = run([exe, check['flag']], timeout=180)
            installed_checks.append({'flag': check['flag'], 'exit': output.returncode, 'output': output.stdout.strip()})
        if pids:
            run(['open', app])
    except Exception:
        shutil.copy2(backup / 'Retto', exe)
        run(['codesign', '--force', '--deep', '--sign', '-', app])
        run(['codesign', '--verify', '--deep', '--strict', app])
        if pids:
            run(['open', app])
        raise
    receipt = {'installed': str(app), 'backup': str(backup), 'resourcesPreserved': len(protected),
               'resourcesByteIdentical': True, 'signatureVerified': True, 'checks': installed_checks,
               'binary': sha(exe), 'restarted': bool(pids), 'stoppedPIDs': pids,
               'runtimeVisualVerified': False}
    (work / 'installation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: v for k, v in receipt.items() if k not in ['checks', 'stoppedPIDs']}, indent=2))


if __name__ == '__main__':
    main()
