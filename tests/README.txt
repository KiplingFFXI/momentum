Momentum developer checks
=========================

Run these commands from the project folder with Python 3.12. The offline checks
need the Ashita v4 Lua libraries, but do not need a running game client.

Setup
-----

  python -m venv tests/.venv
  tests/.venv/Scripts/python -m pip install -r tests/requirements.txt

That installs the test and rendered-preview dependencies. For checks without a
rendered preview, tools/requirements.txt installs only the headless dependencies.

ASHITA_LIBS selects the Ashita addons/libs folder. Its default is
C:/Games/PhoenixXI/addons/libs. On another install, set it before running:

  $env:ASHITA_LIBS = 'D:/Games/PhoenixXI/addons/libs'

The preview also reads the installed Ashita.dll for its font. Dependency
installation needs network access. Tests themselves do not fetch new game rules.

Running
-------

  tests/.venv/Scripts/python tests/verify.py
  tests/.venv/Scripts/python tests/preview/verify_preview.py

verify.py runs all Lua suites, the Python test suites, and the public repository
check. It stops on the first failed command. The preview command is separate
because it needs the renderer and client font.

For focused checks:

  tests/.venv/Scripts/python tests/run.py test_tracker.lua
  tests/.venv/Scripts/python tests/test_settings_client.py
  tests/.venv/Scripts/python tests/test_release.py
  tests/.venv/Scripts/python tools/check_repository.py

On Windows, tests/run_tests.bat creates its own .venv, installs requirements, and
runs the same complete verify.py checks. It keeps the window open for the result.

What the tests cover
-------------------

run.py compiles every runtime Lua file and runs each test_*.lua in a fresh LuaJIT
2.1 runtime. Mock client state supplies frames, packets, input, and commands.
Settings and session writes go to temporary folders. No gameplay commands or
packets are sent. Windows audio calls are intercepted, so sound checks stay silent.

The actual-client-settings test loads Ashita's common, sugar, chat, and settings
libraries without changing them. It covers first load, existing and corrupt
settings, reloads, character callbacks, merged defaults, migration, and saves.

The focused suites cover:
- EXP and LP gains, caps, losses, recovery, rates, goals, duplicate rewards, and
  unknown client data.
- Merit rollover, spending, capacity, session earnings, full storage, actual
  EXP/LP mode, level sync, and optional starter-layout switching.
- Reset and pause behavior, including preserved chain, food, Dedication, and
  EXP ring recast deadlines and the chosen paused-alert setting.
- Notification arming, explicit food-end messages, quiet conditions, immediate
  pause/resume edges, sound throttling, failures, and retries.
- Optional Phoenix reports, freshness, identity, packet bounds, and ring data.
- Character/job session recovery, save failures, file conflicts, profiles,
  sharing, saved folds, search, Undo, layout preservation, and Escape handling.
- Bounded frame work, cache invalidation, counted alert-header measurements,
  hidden displays, readout fit, and readable colors across the existing skins.

The archive suite checks the exact runtime manifest, reproducibility, normalized
line endings, private-path rejection, links, missing or extra files, sound hashes,
and the separate optional server package. The public repository
check validates text, release documents, local Markdown links, and the changelog
version. Developer files do not enter the runtime ZIP.

The real UI preview uses Dear ImGui 1.92.3 to draw the actual Lua HUD and settings.
It covers narrow/default/wide bars, all settings pages, larger fonts, skins,
actual mouse and keyboard replays, readout order and alignment, Shift-dragging,
resizing, chat snapping, grouped alerts and counts, sound test controls, profiles,
and session actions. Full-entry fixtures run the registered addon callbacks.
Close and reopen cases include combat, Escape, the title-bar X, a dropdown, an
active text edit, and pending confirmations.
Synthetic game data and a marked icon fixture remain separate from live captures.

Read tests/preview/README.txt for individual commands. Images and reports go to
tests/out; extracted fonts and generated outputs are ignored by Git.

Performance and compatibility
-----------------------------

Compare against a saved runtime archive when a change needs that evidence:

  tests/.venv/Scripts/python tests/benchmark_runtime.py --baseline path/to/previous-release.zip --out tests/out/performance.json
  tests/.venv/Scripts/python tests/compare_release.py path/to/previous-release.zip

The benchmark counts repeated work in fixed HUD, countdown, settings, packet,
hidden-display, mature-session, and ring-demand fixtures. It counts layout work,
tracker views, rate-bucket visits, chat and inventory reads, profile reads,
history sorting, and date formatting. It does not measure live FPS.

The release comparison sends the same EXP/LP trace through both versions and
compares tracking views and readouts, including pauses, resets, recovery, rates,
goals, and saved resumes. Compare only versions with compatible behavior; an
intentional change needs its own focused expectations.

Source checks and releases
--------------------------

tools/README.txt explains the pinned Phoenix rules check and archive builder.
docs/RELEASING.md describes the release checklist and manual draft workflow.
The Verify workflow runs the headless checks on Windows on pull requests or by
manual request. Ashita's settings library uses Windows paths. The draft workflow
must pass Verify before building its archive on Ubuntu. Neither refreshes Phoenix
rules automatically.

Offline tests and rendered previews do not validate live packet delivery, graphics
driver behavior, client reloads, or Phoenix gameplay. Report those separately.
Server companion tests mock engine bindings; they do not establish deployment.
