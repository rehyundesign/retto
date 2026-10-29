# Installed all-skins cache optimization — 2026-10-29

The installed personal app has more skins and newer Jeanne resources than `macos/Sources`. This change uses its verified v56 all-skins source baseline and preserves the v58 art revision and every other installed resource. Do not replace the personal installation with a public-checkout build.

`runtime.patch` changes six Swift files. Leaving Jeanne, Hana, Pichi, Chocolat Heart, or Amu & Ran releases that skin's character/effect caches. Selecting the current skin preserves its cache. Frame timing, image decoding, drawing, and resource contents are unchanged. Returning to a previous skin loads its frames again; this trades retained memory for a cold load on that switch.

## Evidence

- `verification.json`: before/after cache probes and binary provenance. The probe loads one character and two effect images per skin, switches through the real `RettoView.skin` setter, checks weak image references, and reloads the same pixels.
- Baseline: 15 retained image objects, estimated decoded storage 11,182,080 bytes (10.66 MiB). Optimized: 0 retained objects. This is a bounded fixture measurement, not a whole-process RSS measurement or a claim of total app savings.
- All 15 reloaded TIFF pixel representations are identical. Same-skin selections retain useful cache entries.
- `checks.json`: 12 native checks passed: full app, Jeanne resource/effect/state/fit, Amu clock, Hana resource/gaze, Pichi, Chocolat, Slack, and Codex input.
- `installation.json`: the installed app passed the same 12 checks and strict signature verification, then restarted. All 15,886 resource files remain byte-identical. No art or settings were replaced. Live mouse interaction and visual appearance were not manually inspected.
- Code review found no blocking issue in the cache purge or switch handling. Both operations execute on the overlay's main thread. Static caches shared by offscreen previews can reload safely if another view switches skins.

## Reproduction and recovery

`build.py` requires a source directory matching every entry in `source-hashes.json`, a reference executable with the same Mach-O program text as the installed app, and a fresh output directory. It copies the installed bundle, applies the patch, builds the production candidate and separate diagnostic executables, checks cache behavior, and verifies every resource hash. It never installs. AppKit probes require access to the graphical session.

The source snapshots and pre-install executable/signature backup are retained under `local/` and excluded from Git. The original build workspace is `/private/tmp/retto-skin-cache-20261029`. The local source copies remain available if temporary directories are cleared.

The original build command was:

```sh
python3 tools/skin-performance/build.py \
  --sources /private/tmp/retto-jeanne-v56-bo8w1ch4/Sources \
  --reference-binary /private/tmp/retto-jeanne-v56-bo8w1ch4/Retto.app/Contents/MacOS/Retto \
  --output /private/tmp/retto-skin-cache-20261029
```

After this installation, the original baseline no longer matches the installed executable. Rebase the patch against any later source/app change; do not bypass that check. The original source snapshots are local inputs, not a replacement for the public app source tree.

`install.py --workspace <verified-workspace>` checks the tested candidate hash, the entire unchanged baseline bundle, the cache probe, and at least ten passing native checks. It backs up the executable/signature, stops only processes running that exact app executable, replaces only the executable, signs and verifies the bundle, runs every recorded check, and restarts if the app was running. A failure restores the executable and re-signs it. The persistent backup is `local/installed-backup/Retto`; preserve current resources when recovering it.
