# Balanced CPU and memory optimization — 2026-11-10

This local build preserves the fourteen skins, artwork, display sizes, frame clocks, and notification behavior. No dependencies were added; frame compression uses Apple's Compression framework.

## Changes

- Replace the previous 96 MiB decoded-pixel cache with a shared 48 MiB LZ4 lossless cache plus one hot decoded image. The budget includes both compressed entries and the hot image; leaving a skin purges its frames. Pixel equality and complete-cycle reuse are checked.
- Stream Codex lifecycle JSONL in 64 KiB reads with per-record and per-read autorelease pools. Memory depends on the largest individual JSON record plus buffers, rather than total transcript size. Keep existing lifecycle and partial-line behavior.
- Skip duplicate fully baked Angel samples, including alternating timer ticks during sleep. Preserve procedural gaze, independent UI invalidations, animation clocks, and frame order.
- Keep asynchronous Slack state updates and callbacks on the main actor. A startup crash exposed a background callback racing UI/status-cache access. Mocked read-sync tests now check callback thread affinity.

## Controlled measurements

Three alternating runs per version; table shows medians. Footprint is macOS peak physical footprint, not maximum RSS. Decimal MB. Raw measurements are in [comparison.json](comparison.json).

| Workload | Metric | Before | After |
| --- | --- | ---: | ---: |
| 512 Angel frames | CPU seconds | 0.860 | 1.024 |
| 512 Angel frames | Peak physical footprint | 80.45 MB | 48.10 MB |
| 512 Angel frames | Maximum RSS | 102.51 MB | 104.32 MB |
| 66.11 MB synthetic JSONL scan | CPU seconds | 1.425 | 0.861 |
| 66.11 MB synthetic JSONL scan | Peak physical footprint | 207.90 MB | 4.28 MB |
| 66.11 MB synthetic JSONL scan | Maximum RSS | 216.66 MB | 13.17 MB |

The frame comparison uses the previous 96 MiB raw cache as its baseline. Compression lowers charged physical memory by 40%, at a 19% CPU cost versus that raw cache; frame RSS is essentially unchanged. The transcript comparison uses the original whole-file reader: CPU decreases 40% and physical footprint decreases 98%. These are subsystem benchmarks, not whole-app reduction guarantees. The synthetic fixture contains no user data and is not committed.

An uncontrolled live observation before the final actor fix showed footprint around 304 MB with the previous cache and 206 MB with the balanced build, with CPU interval samples of 4–9%. Different app lifetimes and workloads prevent a causal percentage claim.

## Validation and delivery

The final actor-fix source build passed all 22 runtime checks and three Python status checks via `python3 scripts/build-public.py --app-only`. This includes frame losslessness/budget/reuse, stream parsing boundaries, all skins, Angel interactions, and mocked Slack read-sync callbacks. `git diff --check` and `python3 -m py_compile scripts/build-public.py` also passed.

The final installed build was visually verified running, with no new crash report during a 47-second observation. Its live CPU interval samples were 12–28%, with a 230.8 MB physical footprint (394.3 MB peak); a later top sample showed 219–226 MB resident memory and 15–24% CPU. These active-state observations are not a controlled before/after comparison and do not establish an overall CPU reduction. Installation details and final running-process observations are recorded in verification.json. Installation replaces only the executable in a clone of the existing app, retains metadata and settings, checks the entire resource inventory, verifies the signature, and keeps a backup.

These optimization changes are local only. The previously published GitHub release download has not been replaced.
