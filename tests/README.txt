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
  tests/.venv/Scripts/python tests/run.py test_dynamis.lua
  tests/.venv/Scripts/python tests/run.py test_dynamis_ui.lua
  tests/.venv/Scripts/python tests/run.py test_events.lua test_events_client.lua test_events_runtime.lua test_events_entry.lua
  tests/.venv/Scripts/python tests/run.py test_event_layouts.lua test_event_readouts.lua test_event_ui.lua test_account_cooldowns.lua
  tests/.venv/Scripts/python tests/run.py test_event_resets.lua
  tests/.venv/Scripts/python tests/run.py test_shami_seals.lua test_shami_entry.lua test_startup_events.lua test_chat_center.lua
  tests/.venv/Scripts/python tests/test_event_rules.py
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
  EXP/LP mode, level sync, and optional saved-layout switching.
- Optional gil readouts in every bar mode, unknown and zero balances, negative
  changes and rates, short numbers, custom labels, and visible-value caching.
- Gil packet bursts, duplicate balances, inventory readiness, job data gaps,
  separate rate timing, pause/reset, old saves, and gil-only session checkpoints.
- Reset and pause behavior, including preserved chain, food, Dedication, and
  EXP ring recast deadlines and the chosen paused-alert setting.
- Notification arming, explicit food-end messages, quiet conditions, immediate
  pause/resume edges, sound throttling, failures, and retries.
- Sound-folder scans, bundled/custom ordering, duplicate names, bounded native
  filename reads, and search-handle cleanup when enumeration fails.
- Normal client status, observation gaps, identity, packet bounds, and ring data.
- Character/job session recovery, save failures, file conflicts, profiles,
  sharing, saved folds, search, Undo, layout preservation, and Escape handling.
- Bounded frame work, cache invalidation, counted alert-header measurements,
  hidden displays, readout fit, and readable colors across the existing skins.
- Chat visibility choices, retained anchors, temporary free placement, unknown
  chat state, hide-setting precedence, and continued tracking while chat closes.
- Centered chat placement, content and fixed widths, saved starting points,
  second-chat protection, snapping, locked movement, profiles, and held anchors.
- Dynamis hourglass and packet parsing, extensions, pool deduplication, found and
  received drops, observed objectives, partial runs, reloads, history, registration
  timing, separate layouts, wanted drops, and optional alerts. EXP reset and pause
  preserve Dynamis tracking; clearing Dynamis totals preserves the timer.
- Manual EXP, Merits, Dynamis, Assault, Limbus, BCNM, KSNM, and ENM selection,
  independent saved readout layouts, automatic switching, reloads, profile changes,
  commands, and unchanged session and event timers.
- Event Display resets restore the selected starter, while Events resets preserve
  the underlying EXP and Merits readouts across all five new modes.
- Zone-visit timing, partial visits, event identity, native and estimated countdowns,
  reloads, objective observation, repeated enemies, waves, crates, outcomes,
  deduplicated drops, personal awards, confirmed records, and bounded run history.
  Initial treasure-pool reads must preserve a just-observed drop so a repeated
  update cannot count it twice.
- Assault mission records, stored currencies and tags, carried seals and coins,
  ENM shared key-item groups and acquisition timers, Limbus entry timing, and
  unknown observations that must not become eligibility claims.
- Shami dialogue and deposit fields, confirmed orb purchases and seal withdrawals,
  cancellations and failed purchases, duplicate receipts, older balance updates,
  packet bounds and identity, and pause/reset without stopping balance updates.
- Bounded startup event replay, countdown aging, stale zone or character context,
  and no EXP reward replay during the three-second initialization wait.
- Local account-group sharing, Dynamis account timers, separate Limbus account
  reminders, concurrent records, saved-setting migration, and account preferences
  staying separate from profiles, shared layouts, resets, and appearance Undo.

The archive suite checks the exact runtime manifest, reproducibility, normalized
line endings, private-path rejection, links, missing or extra files, and sound
hashes. The public repository check validates text, release documents, local
Markdown links, and the changelog
version. Developer files do not enter the runtime ZIP.

The real UI preview uses Dear ImGui 1.92.3 to draw the actual Lua HUD and settings.
It covers narrow/default/wide bars, all settings pages, larger fonts, skins,
actual mouse and keyboard replays, readout order and alignment, Shift-dragging,
resizing, chat snapping, grouped alerts and counts, sound test controls, profiles,
and session actions. A Dynamis scene and dynamis_input.json replay cover the
compact bar, changing countdown, extensions, drops, and unknown time. Full-entry
fixtures run the registered addon callbacks. The manual_modes_input.json replay
switches the original three bar modes and returns to Automatic using the settings menu.
gil_readouts_input.json checks the compact gil bar, negative changes and rates,
and an unready rate using the actual Lua renderer.
event_modes_input.json clicks all five event modes, edits independent layouts,
and restores the original EXP layout. Event scenes cover compact bars, narrow
settings, wanted-drop pagination, cooldown choices, and the local account-group
field and sharing checkbox. No real account details are used in these fixtures.
chat_center_input.json selects centered placement and sizing through the actual
settings controls. chat_center_hold_input.json checks that a centered bar keeps
its drawn rectangle while chat is closed, then follows chat again when it opens.
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
hidden-display, mature-session, ring-demand, active-event, and Events-page fixtures. It counts layout work,
tracker views, rate-bucket visits, chat and inventory reads, profile reads,
history sorting, and date formatting. It does not measure live FPS.

Gil fixtures use a stable mock inventory manager before the player reader loads.
They count actual slot reads and cover idle/active rates plus 100-packet bursts
while tracking or paused. Unrelated inventory updates must not cause player or
inventory sampling. Automatic's idle fixture checks that no layouts are copied
or reapplied once the matching saved layout is active.

Event fixtures advance the countdown and check that unchanged inventory is not
scanned again. They also cover idle event tracking and the open Events page.

Closed-chat fixtures cover Hide with chat, both keep-visible choices, and Free
placement. The HUD holds its last rendered rectangle through failed chat reads;
previews cannot replace it, and deliberate edits and reopened chat still work.
Native reader tests separately count retained-position projections
and verify that skipping an unused anchor does not skip validation or add reads.

The release comparison sends the same EXP/LP trace through both versions and
compares tracking views and readouts, including pauses, resets, recovery, rates,
goals, and saved resumes. Compare only versions with compatible behavior; an
intentional change needs its own focused expectations.

Use --exclude-readout ID only for an intentionally retired reading. For example,
the 1.3.2 comparison with 1.3.1 excludes dedication_budget. The default comparison
stays strict; every tracking view and every other readout must still match.

Source checks and releases
--------------------------

tools/README.txt explains the pinned Phoenix rules checks and archive builder:

  tests/.venv/Scripts/python tools/export_rules.py --source ../Phoenix --check
  tests/.venv/Scripts/python tools/export_dynamis.py --source ../Phoenix --check
  tests/.venv/Scripts/python tools/export_events.py --source ../Phoenix --check

Each exporter reads its pinned Git revision. Dynamis and event exports include
the applicable enabled era and Phoenix overlays and need PyYAML from
tools/requirements.txt. These checks do not refresh any bundle or change the
Phoenix checkout.

docs/RELEASING.md describes the release checklist and manual draft workflow.
The Verify workflow runs the headless checks on Windows on pull requests or by
manual request. Ashita's settings library uses Windows paths. The draft workflow
must pass Verify before building its archive on Ubuntu. Neither refreshes Phoenix
rules automatically.

Offline tests and rendered previews do not validate live packet delivery, graphics
driver behavior, client reloads, or Phoenix gameplay. Report those separately.
Client-only regression checks cover normal buff timers, local chain estimates,
Level Sync levels, and migration of removed server-dependent settings. Former
custom status messages remain ordinary chat and cannot change tracking.
