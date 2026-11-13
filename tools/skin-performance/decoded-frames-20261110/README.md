# Angel decoded-frame optimization — 2026-11-10

Profiling the installed app showed repeated PNG loading/decoding during animation. AngelSkin and AngelInteractions previously held separate file-backed NSImage caches with advisory budgets of 112 and 96 MiB. Under memory pressure, cache eviction and lazy image decoding repeated work.

Both now use one decoded-pixel LRU with a strict 96 MiB retained-pixel budget. This fits the 64-frame working cycle and the 64-background/16-direction gaze set without changing source art, display geometry or timing. Leaving the skin clears the shared cache through the existing purge path. The budget covers retained pixel data; it is not a limit on total process memory, temporary decoding buffers, or AppKit rendering allocations.

The same 512-frame running animation benchmark ran three times per binary, alternating baseline and candidate. Median process CPU time fell from 2.056572s to 0.898400s (56.3%). The benchmark renders into an offscreen bitmap and measures decoding/drawing, not total application CPU. `--benchmark-angel-frames` repeats it against the app bundle’s own resources.

Live samples were about 32% CPU before and 18–33% after. Physical-footprint snapshots were 211.1 MB before and 254.9 MB after; these were separate live sessions and are not a controlled memory comparison. This change demonstrably reduces rendering CPU and bounds retained decoded pixels; it does not establish a reduction in whole-app memory. Retaining decoded pixels intentionally trades memory for less repeated decoding.

Validation: source build, 21 runtime/cache checks and three status-integration Python checks passed. The installed candidate passed four additional checks and strict codesign verification. All 31,492 resources were preserved. At 0.75s the eight-state light/dark preview was pixel-identical when the existing random idle variant matched. Cache checks cover repeated access, actual pixel cost, LRU eviction, missing/oversized files and purge.

Applied to the local installed app. Recovery copy: `/private/tmp/retto-performance-20261110/Retto-before.bundle`. No remote push, PR or release update was performed for this optimization; the previously published snapshot remains unchanged.
