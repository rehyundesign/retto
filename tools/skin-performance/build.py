"""Build a scoped all-skins candidate and repeatable before/after cache probes.
The source tree must match the recorded installed-app baseline. Never installs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_hash(path):
    """Hash Mach-O program text, excluding resource-signing changes."""
    data = path.read_bytes()
    magic, _, _, _, count, _, _, _ = struct.unpack_from('<8I', data)
    assert magic == 0xFEEDFACF
    offset = 32
    for _ in range(count):
        cmd, size = struct.unpack_from('<II', data, offset)
        if cmd == 0x19:
            sections = struct.unpack_from('<I', data, offset + 64)[0]
            for i in range(sections):
                section = offset + 72 + i * 80
                if data[section:section + 16].rstrip(b'\0') == b'__text':
                    length, start = struct.unpack_from('<QI', data, section + 40)
                    return hashlib.sha256(data[start:start + length]).hexdigest()
        offset += size
    raise ValueError('No program text section')


def run(args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, text=True, capture_output=True, **kwargs)


def compile_app(sources, app, work):
    run(['swiftc', '-O', '-module-cache-path', work / 'module-cache', '-target', 'arm64-apple-macos13.0',
         '-framework', 'AppKit', '-framework', 'ServiceManagement', *sorted(sources.glob('*.swift')),
         '-o', app / 'Contents/MacOS/Retto'], timeout=300)
    run(['codesign', '--force', '--deep', '--sign', '-', app])
    run(['codesign', '--verify', '--deep', '--strict', app])


def add_probe(sources):
    # These diagnostics share each cache's file so private caches stay private in production.
    probes = {
        'JeanneSkin.swift': ('JeanneSkin', '''guard let s = state(row: 7) else { return [] }
            return [s.files[0], s.effects[0].back, s.effects[0].front].compactMap { image($0) }'''),
        'HanaSkin.swift': ('HanaFrameCache', '''return [image("character-7-0", character: true),
            image("running-back-0"), image("running-front-0")].compactMap { $0 }'''),
        'PichiSkin.swift': ('PichiSkin', '''guard let s = state(row: 7) else { return [] }
            return [s.cells[0].file, s.effects[0].back.file, s.effects[0].front.file].compactMap { image($0) }'''),
        'ChocolatHeart.swift': ('ChocolatHeart', '''return ["character-7-0", "running-back-0", "running-front-0"].compactMap { image($0) }'''),
        'AmuRanSkin.swift': ('AmuRanFrames', '''return ["character-7-0", "back-7-0", "front-7-0"].compactMap { key in
            let cache = key.hasPrefix("character") ? characters : effects
            if let cached = cache.object(forKey: key as NSString) { return cached }
            guard let url = resource(key), let image = NSImage(contentsOf: url) else { return nil }
            cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height) * 4)
            return image
        }'''),
    }
    for name, (enum, body) in probes.items():
        path = sources / name
        path.write_text(path.read_text() + '\nextension ' + enum + ' {\n'
                        + '    static func cacheProbeImages() -> [NSImage] {\n' + body + '\n    }\n}\n')
    shutil.copy2(HERE / 'cache-probe.swift', sources / 'CacheProbe.swift')
    path = sources / 'main.swift'
    path.write_text('import AppKit\nif CommandLine.arguments.contains("--skin-cache-probe") { exit(runSkinCacheProbe()) }\n'
                    + path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resume', action='store_true', help='Resume this same verified workspace after a probe interruption')
    parser.add_argument('--sources', type=Path, required=True)
    parser.add_argument('--installed-app', type=Path, default=Path.home() / 'Applications/Retto.app')
    parser.add_argument('--reference-binary', type=Path, required=True,
                        help='Unmodified v56 binary compiled from the hashed source baseline')
    parser.add_argument('--output', type=Path, required=True, help='New workspace; must not exist')
    args = parser.parse_args()
    expected = json.loads((HERE / 'source-hashes.json').read_text())
    actual = {p.name: sha(p) for p in args.sources.glob('*.swift')}
    assert actual == expected, 'Source baseline changed; inspect and rebase the patch first'
    binary = args.installed_app / 'Contents/MacOS/Retto'
    assert text_hash(binary) == text_hash(args.reference_binary), 'Installed code differs from source baseline'
    args.output.mkdir(parents=True, exist_ok=args.resume)
    work = args.output
    before = {str(p.relative_to(args.installed_app)): sha(p)
              for p in args.installed_app.rglob('*') if p.is_file()}
    if args.resume:
        assert json.loads((work / 'installed-before.json').read_text()) == before
    else:
        (work / 'installed-before.json').write_text(json.dumps(before, indent=2) + '\n')
    sources = work / 'Sources'
    if not args.resume:
        shutil.copytree(args.sources, sources)
        run(['patch', '-p1', '-i', HERE / 'runtime.patch'], cwd=sources)
    if args.resume:
        with tempfile.TemporaryDirectory(prefix='patch-check-', dir=work) as scratch:
            check_sources = Path(scratch) / 'Sources'
            shutil.copytree(args.sources, check_sources)
            run(['patch', '-p1', '-i', HERE / 'runtime.patch'], cwd=check_sources)
            assert {p.name: sha(p) for p in check_sources.glob('*.swift')} == {
                p.name: sha(p) for p in sources.glob('*.swift')}, 'Candidate sources changed'
    stage = work / 'Retto.app'
    if not args.resume:
        shutil.copytree(args.installed_app, stage)
        print('Compiling production candidate', flush=True)
        compile_app(sources, stage, work)
    run(['codesign', '--verify', '--deep', '--strict', stage])
    # Probe apps share read-only resources; no duplicate asset bundles or installed-app writes.
    results = {}
    for name, src, optimized in [('before', args.sources, False), ('after', sources, True)]:
        probe_sources = work / (name + '-probe-sources')
        if not probe_sources.exists():
            shutil.copytree(src, probe_sources)
            add_probe(probe_sources)
        app = work / (name + '-probe.app')
        if not app.exists():
            (app / 'Contents/MacOS').mkdir(parents=True)
            shutil.copy2(stage / 'Contents/Info.plist', app / 'Contents/Info.plist')
            (app / 'Contents/Resources').symlink_to(stage / 'Contents/Resources', target_is_directory=True)
        print('Compiling ' + name + ' cache probe', flush=True)
        # Do not sign a bundle whose resources are a symlink into the candidate.
        if not (app / 'Contents/MacOS/Retto').exists():
            run(['swiftc', '-O', '-module-cache-path', work / 'module-cache', '-target', 'arm64-apple-macos13.0',
                 '-framework', 'AppKit', '-framework', 'ServiceManagement', *sorted(probe_sources.glob('*.swift')),
                 '-o', app / 'Contents/MacOS/Retto'], timeout=300)
        output = run([app / 'Contents/MacOS/Retto', '--skin-cache-probe']
                     + (['--expect-released'] if optimized else []), timeout=120)
        results[name] = json.loads(output.stdout)
        (work / (name + '-probe.json')).write_text(output.stdout)
        print(name + ': ' + str(results[name]['retainedDecodedBytes']) + ' retained decoded bytes', flush=True)
    protected = {r: h for r, h in before.items() if r.startswith('Contents/Resources/')}
    assert all(sha(stage / r) == h for r, h in protected.items())
    assert {str(p.relative_to(stage / 'Contents/Resources')) for p in (stage / 'Contents/Resources').rglob('*') if p.is_file()} == {
        r.removeprefix('Contents/Resources/') for r in protected}
    evidence = {'candidate': str(stage), 'sources': str(sources), 'installedApp': str(args.installed_app),
                'installedBinaryBefore': sha(binary), 'candidateBinary': sha(stage / 'Contents/MacOS/Retto'), 'resourcesPreserved': len(protected),
                'cacheProbes': results, 'installed': False}
    (work / 'verification.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(stage, flush=True)


if __name__ == '__main__':
    main()
