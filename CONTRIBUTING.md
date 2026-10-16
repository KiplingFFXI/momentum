# Contributing

Momentum is an Ashita v4 addon for Phoenix. Keep changes focused on EXP, LP, merit points, and the information that helps players track a session.

## Set up

Use Python 3.12 and an Ashita v4 installation for the offline checks. From the project folder:

```powershell
python -m venv tests/.venv
tests/.venv/Scripts/python -m pip install -r tests/requirements.txt
```

The tests read Ashita libraries from `C:/Games/PhoenixXI/addons/libs` by default. Set `ASHITA_LIBS` to use another install. Test settings and history go into temporary folders. Tests do not send gameplay commands or play audible alerts.

## Keep existing setups working

- Preserve readout IDs, settings keys, profiles, saved order, labels, colors, dividers, and character-owned records. Add a tested migration when a stored value must change.
- Keep unknown client data unknown. A missing value is not zero, and an estimate is not a confirmed server value.
- Keep Momentum fully client-side. Use client state and normal game packets only. Never add server modules, custom server data feeds, server commands, or server changes for the addon. Leave readings out when the client cannot supply them reliably.
- Use the pinned Phoenix source and its loaded modules for game rules. Record source changes through the exporter; do not substitute retail or another server's rules.
- Keep the addon observational. Do not add item use, gameplay commands, automatic mode changes, or new alerts that start enabled.
- Keep repeated frame work bounded. Avoid file reads, full inventory scans, history sorting, and unnecessary text measurements on every frame.
- Write labels and help in plain game terms. Explain what a control changes and when a reading is uncertain.

## Check a change

Run the focused tests for the code you changed, then the applicable full checks before a release:

```powershell
tests/.venv/Scripts/python tests/verify.py
tests/.venv/Scripts/python tests/preview/verify_preview.py
```

`tests/verify.py` runs the Lua tests, actual settings-library checks, and package and repository checks. For one Lua suite, run `tests/.venv/Scripts/python tests/run.py test_tracker.lua`. UI changes should include a rendered check at a narrow width or larger text size when relevant. Use a real input replay for changes to clicks, dragging, focus, or dropdowns. See [tests/README.txt](tests/README.txt) and [preview instructions](tests/preview/README.txt).

For performance changes, use the operation-count benchmark against a previous release. Keep the measured workload and correctness checks together; an offline count is not a live FPS measurement. Changes to Phoenix rules also need the pinned-source check described in [tools/README.txt](tools/README.txt).

## Send a useful report

Include the addon version, relevant settings, steps to reproduce, expected result, and what happened. A screenshot helps for placement or clipping. Say whether the result came from a live client, a mocked test, a rendered preview, or source inspection. Remove character identifiers or private paths from logs you share.

For a proposed change, explain the player-facing result, the affected saved settings, and the checks run. Keep generated outputs, test images, local settings, sessions, logs, and private files out of the source tree submitted for review.

## Release boundaries

See [tools/README.txt](tools/README.txt) for packaging and the draft-release workflow. A successful offline suite or draft archive does not establish Phoenix deployment, staff approval, or live-client testing. Check those separately and state what was actually verified. Publishing a release is a separate maintainer action.
