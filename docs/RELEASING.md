# Releasing Momentum

This checklist prepares a reviewable release. It does not publish one or establish live-client or server testing.

## Prepare the version

1. Choose the next `major.minor.patch` version, then set `addon.version` in `momentum/momentum.lua` to match.
2. Move the **Unreleased** notes in [CHANGELOG.md](../CHANGELOG.md) into that version's entry. Review them against the final changes and preserve the notes for previous releases.
3. Update installation examples and the [guide](GUIDE.md) when names or behavior change. Preserve saved settings, profiles, and session compatibility.
4. For game-rule changes, review the pinned Phoenix revision and loaded modules, regenerate the rules deliberately, and run the source check. A release build does not refresh them.

Keep new work under **Unreleased** until a release version is assigned. Assign the version and promote those notes before building the release archive or generating release notes. An Unreleased entry does not change the installed version or publish an update.

To review the pending notes without assigning a release version:

```powershell
python tools/release_notes.py --unreleased --out tests/out/next-release-notes.md
```

## Verify

From the project folder with Python 3.12 and the dependencies described in [tests/README.txt](../tests/README.txt):

```powershell
python tests/verify.py
python tests/preview/verify_preview.py
python tools/export_rules.py --source ../Phoenix --check
python tools/export_dynamis.py --source ../Phoenix --check
```

The first command runs the offline Lua suites, Python tests, and repository checks. The second draws the real Lua UI with simulated client data and replays input. Both source checks require their pinned Phoenix revision in a local checkout. The Dynamis exporter checks the enabled era and Phoenix overlays as well as the base data; it does not read uncommitted server changes.

For a performance change, compare operation counts with a previous archive and review the affected behavior checks. Inspect relevant screenshots after a UI change. Record any client checks separately, including loading or reloading, chat placement, real EXP/LP gains, merit conversion, effect timers, and chosen alerts. Do not describe offline results as live testing.

For Dynamis, check a readable Perpetual Hourglass, extensions, a reload and late join, zone changes, found drops versus personal awards, duplicate pool updates, and the separate clear-totals action. Check that EXP reset and pause preserve Dynamis timing and collection, the prior layout returns on exit, unseen objectives stay unknown, and chosen alerts stay quiet during initial loading. Verify the recorded registration countdown without describing it as confirmed account eligibility. Include partial-run and saved-history behavior in the results.

For Bar mode, switch among EXP, Merits, and Dynamis from both settings and chat. Check that each keeps its readout edits through switching, closing settings, reloading, and zoning, with both automatic layout options enabled. Return to Automatic and check that the previous regular setup and configured switching resume. Selecting a bar must not change gameplay mode, reset a session or run, or stop timers or Dynamis collection. Check manual Dynamis outside the zone with unknown run readings.

Before releasing the visibility changes, record these live-client checks separately from the offline results:

- Try all three Bar visibility choices above chat, below chat, and in Free placement. Changing placement must keep the chosen visibility option. Close and reopen the main chat log, then change the chat size and resolution. Confirm the native active flag follows the visible chat window.
- In Keep visible when chat closes and Always visible, check that the last drawn bar stays put when chat closes or its position becomes unreadable. Test both a confirmed inactive window and unknown bounds, including a failed read. A smaller client window should move or shrink the bar only enough to stay on screen; returning chat should restore its current anchor.
- Check the saved Free placement fallback before any bar position is available, then Shift drag and resize a held bar. The edit should switch to Free placement. Close and reopen chat during a held resize; keep the last valid size until a new drag. With readable chat but no room on the chosen side, keep the dock hidden and clear of both chat windows.
- Check typing, map, cutscene, hidden game UI, and idle behavior. Always visible should bypass those hide settings, while `/momentum hide` still works with Sample preview off. Escape must close settings during combat and an active edit.
- Load profiles and check their saved visibility policy and placement. Switch bar modes, zone, and reload without changing that choice or carrying a stale chat rectangle into another character or zone.
- Check fresh settings, resets, and missing or invalid visibility choices: all should use Keep visible when chat closes. Only the former placement choice should become Hide with chat for an attached bar or Keep visible when chat closes for Free placement. Preserve each explicit saved choice through loading, profiles, character changes, and reloads.
- Hide and show the bar during an active session and Dynamis run. Confirm rates, drops, alerts, and EXP chain, food, Dedication, EXP ring recast, and Dynamis timers keep updating. Reset and Pause must still preserve their active timers.

## Build and inspect

```powershell
python tools/build_release.py
```

The archive goes to Downloads by default. Use `--out PATH` for another output folder. The builder prints its SHA-256. Inspect the ZIP contents and use the printed hash when recording the build.

The runtime ZIP contains `momentum/` with the reviewed addon files and license. It must not include settings, profiles, sessions, Dynamis run records, test output, private paths, or developer files. See [tools/README.txt](../tools/README.txt) for the manifest checks and reproducibility rules.

Review the public source, release notes, archive contents, and image and sound metadata for personal information. Keep only the approved author name, email, and GitHub details. Use sample data in examples; do not include real character names or IDs, chat logs, machine or account names, private paths, credentials, or saved player files. The automated checks cover known markers and the archive manifest, so inspect the media and final files as well.

Generate the release notes from the same version entry used by the draft workflow:

```powershell
python tools/release_notes.py --out tests/out/release-notes.md
```

Check the notes against the final changes and include the update steps that preserve `config/addons/momentum/`. Keep verification results separate from feature claims, and do not describe a local archive as published.

If an operator specifically needs the optional server package, build it separately with `--server` and review [its instructions](../server/README.txt). Packaging it is not deployment, and the client addon does not require it. Dynamis uses the client hourglass and incoming state and needs no server companion.

## Create a draft

After the reviewed source is available in the GitHub repository, a maintainer can open **Actions > Draft release > Run workflow** and choose the intended branch. The workflow:

1. Runs the reusable **Verify** workflow on Windows with pinned Ashita libraries.
2. Reads the current version and changelog entry.
3. Refuses an existing release or tag named `v<version>`, keeping the archive tied to the reviewed source.
4. Builds the runtime ZIP and a SHA-256 file on Ubuntu.
5. Creates a draft named `Momentum <version>` for the selected commit.

The workflow runs only by manual request. Version edits, pushes, tags, and schedules do not create a release. It does not regenerate Phoenix data or upload the optional server package.

Review the draft's version, target commit, notes, archive, and checksum. Publishing remains a separate maintainer action on the Releases page. An existing release's files should not be silently replaced.

## Update an installed copy

If Momentum is running, enter `/addon unload momentum` before replacing `addons/momentum/` with the reviewed runtime folder. Keep `config/addons/momentum/`, which holds settings, profiles, shared layouts, sessions, Dynamis runs, and custom sounds. Enter `/addon load momentum` after replacing the files.
