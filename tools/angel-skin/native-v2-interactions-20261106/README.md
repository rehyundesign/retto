# Angel interactions local delivery

Added to the existing locally installed Angel skin on 2026-11-09:

- Left and right airborne dragging, 16 independent full-trio drawings per direction. Body animation: 100 ms per pose, 1.6 s per loop. Effects: 64 samples at 50 ms, 3.2 s per loop.
- Cursor gaze in 16 clockwise sectors from up. Each sector is a complete connected character drawing, with both companions responding. Fifteen new sources and one retained approved left-facing source. Gaze is allowed only during idle, resets after the existing 0.8 s hold, and keeps effects moving while the pose holds.
- The approved prior left-look interaction becomes a random idle variation. Selection changes only at a complete 3.2 s cycle boundary.

Display fit uses the existing Angel main-body camera: 544 source square, 448 body reference units, 1.06 scale, support y=484. Wings, pets and alpha bounds never determine a new body scale. Flight registration is a rigid whole-trio translation, constrained to retain extremities. Head/neck/body patch construction and image mirroring were not used.

The source of truth for the installed executable was recovered from the current installed Amu routing source archive, verified by executable and archive hashes. Only Angel branches of `PetView.swift` and diagnostic entry points in `main.swift` changed; 45 existing source files and all 30,614 prior resources were preserved. `AngelInteractions.swift` and an optional `AngelInteractions/` package were added. The old seven `AngelFrames` states remain byte-identical.

Six native tests passed before installation and again from the installed executable: base Angel resources, actual state routing, interaction resources/clocks/random policy, actual 16-sector cursor/gaze-reset/drag return, all-skins availability, and Amu state routing. Actual `RettoView.draw` fixtures cover all 16 gaze directions, both 16-pose drag loops, and both idle choices; fixed gaze renders differ at separate effect times. Source alpha borders, decoded source uniqueness, media durations and HTML JavaScript syntax passed. Installed signature verification passed.

The installed app was restarted as one instance, Angel was selected through its menu, and its appearance and drag release were observed through CUA. Mid-drag animation was reviewed in native fixtures rather than captured during live mouse movement. Browser rendering of the HTML was not re-verified; its JavaScript syntax and referenced media were checked. Original anatomical landmark certification remains unverified; these scoped checks do not claim it.

Local evidence: `installation.json`, `candidate.json`, `source-preservation.json`, `review/tests.json`, `review/native-render-check.json`, `resource-map.json`. `source-snapshot.tar.gz` binds all 48 native source files to this executable. `recovery/` is a local backup and is excluded from the commit.

Build continuation: recover the baseline with `stage.py`, apply `patch.py`, then `add_fixture.py`; export accepted media with `export.py`, build with `build.py`, and run `test.py` with AppKit access. Installation is scoped and asserts the original installed executable/resource hashes before modification. Do not rerun installation over another delivery without restaging its current source.
