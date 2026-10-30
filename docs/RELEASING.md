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

## Check an upgrade

Keep a backup of `config/addons/momentum/` and test with a copy of an existing setup as well as fresh settings. Replacing the addon must not replace settings, profiles, shared layouts, session or run history, recorded cooldowns, or custom sounds. Check the existing EXP, Merits, and Dynamis readouts, order, labels, dividers, placement, visibility, and alert choices before and after loading the update.

New event layouts should start from their compact defaults only when that mode has no saved setup. Enter and leave each mode manually and through Automatic, then reload with the event layout active. The correct saved setup must return. New optional readouts must not appear in an older saved layout unless selected, and new alerts must stay off until chosen. Account groups stay local character preferences and must not enter an exported profile or shared appearance.

## Verify

For Farming, test confirmed solo and party treasure awards separately from new pool drops. Old pool refreshes must not increase Pool drops seen, and an existing item later won by the current player must count once. Lot/pass updates, another player's win, failed or lost awards, purchases, trades, crafting, and bag moves must not add received loot. Check current character/job recovery, duplicate packets, slot reuse, zoning, and saved sessions. Fishing, HELM, digging, and Steal remain outside Farming's supported sources.

Check all twelve Farming readouts, item and stack goals, wanted-item and low-space alerts, and manual prices. Validate zero against unknown values and confirm that estimates remain separate from actual gil. Rate warm-up uses the first personal item and unpaused observed time; Gil/HR keeps its existing clock. Pause/reset must affect Farming session statistics without changing active chain, buff, ring, zone, or event timers and event-specific drop totals. Do not replay missed or paused items after resume.

Packet checks must include Ashita-style userdata with only the supported event fields. Missing compatibility aliases must not stop normal reads or startup buffering. Reject blocked, injected, malformed, and truncated packets, and confirm that Dynamis receives the same valid updates as the other trackers.

Switch Farming manually and through **Use Farming outside events**, including entering and leaving each automatic event layout. Existing customized EXP/Merits/Farming banks must return intact, and the fallback starts off. Repeat with shared layouts on and off during sequential character switches; share settings without mixing statistics. Check the Farming page, watched-item search, item IDs, unit prices, goal fill, received/recent lists, and copied summary. Name search must remain incremental and do no startup catalog scan.

From the project folder with Python 3.12 and the dependencies described in [tests/README.txt](../tests/README.txt):

```powershell
python tests/verify.py
python tests/preview/verify_preview.py
python tools/export_rules.py --source ../Phoenix --check
python tools/export_dynamis.py --source ../Phoenix --check
python tools/export_events.py --source ../Phoenix --check
```

The first command runs the offline Lua suites, Python tests, and repository checks. The second draws the real Lua UI with simulated client data and replays input. The source checks require their pinned Phoenix revision in a local checkout. The Dynamis and event exporters check the applicable enabled era and Phoenix overlays as well as the base data; they do not read uncommitted server changes.

For a performance change, compare operation counts with a previous archive and review the affected behavior checks. Inspect relevant screenshots after a UI change. Record any client checks separately, including loading or reloading, chat placement, real EXP/LP gains, merit conversion, effect timers, and chosen alerts. Do not describe offline results as live testing.

For Dynamis, check a readable Perpetual Hourglass, extensions, a reload and late join, zone changes, found drops versus personal awards, duplicate pool updates, and the separate clear-totals action. Check that EXP reset and pause preserve Dynamis timing and collection, the prior layout returns on exit, unseen objectives stay unknown, and chosen alerts stay quiet during initial loading. Verify the recorded registration countdown without describing it as confirmed account eligibility. Include partial-run and saved-history behavior in the results.

For Bar mode, switch among EXP, Merits, Farming, Dynamis, Assault, Limbus, BCNM, KSNM, and ENM from both settings and chat. Check that each keeps its readout edits through switching, closing settings, reloading, and zoning, with automatic switching enabled. Return to Automatic and check that it uses the saved event, Farming fallback, or earning-mode layout. Selecting a bar must not change gameplay mode, reset a session or run, or stop timers or event collection. Check manual event layouts outside their zones with unknown run readings.

Check event alerts and saved records:

- Enable each Assault or battlefield alert, then check its notice and sound through a normal observed event and its test button. Observed alerts must honor Quiet conditions and Time between alerts. Test buttons must still work while muted, and loading a saved run must not replay old alerts.
- Save, reload, and continue Dynamis and event records with fractional timer values, including fallback-clock timing. Unchanged records must save without a false conflict, and an actual external edit must still be detected. A clean record must not encode JSON on every frame or empty save attempt.

For the optional subjob display, check the following and record actual client results separately:

- Fresh settings and older layouts without this option start with **Show subjob and level** off. An already saved choice must stay saved. Add or select **Job and level**, then toggle the option under **Selected readout**. Only its subjob text should change, with one main job icon and the existing labels, dividers, and order kept. Check the text fallback when no icon is available, wide and narrow bars, and centered readouts.
- Compare both jobs and levels with the game menu before, during, and after Level Sync. Include a subjob below its possible level cap, no available subjob, and a support job restriction. A missing level stays `--`; a missing subjob does not retain an earlier job name. Pause and Reset session must leave this live information updating.
- Give EXP and Merits different subjob choices, with **Job and level** enabled in each. Check manual switching, Automatic with **Switch saved EXP / Merits layouts** on and off, and entering and leaving each event layout. Each layout must restore its own choice through reloads and profile loading.
- With shared layouts off, give two characters different choices, switch main-to-alt-to-main, and reload. Each must restore its own layout and show only its current job information. Repeat with **Use one layout for all characters** on: the shared choice follows both characters, while the displayed jobs and levels remain character-specific. Turn sharing off, edit the active character's layout, and switch through both again; the other character must retain its own layout. Returning to a character must not reapply an older linked job profile. Shared settings must not be polled between these actions.
- With the option off or the Job readout disabled, there must be no subjob getters. With it on, query it only during existing player samples. Unchanged job text must reuse its cached readings and layout between frames.
- Search for **subjob**, choose **Job and level**, and change the actual checkbox. It must not open an unrelated readout editor. Check that normal searches such as divider still open the intended editor. Profiles must omit the unsupported **Reset this section** action while other tabs retain their own resets; the separately confirmed **Reset layout** must keep saved profiles.

For Time in zone and event tracking, keep source, offline, and live results separate:

- Add **Time in zone** and **Current zone** to an EXP and event layout. Check an observed zone entry, leaving and returning, loading during a visit, and a reload. Partial visits need the `~` marker. Pause and Reset session must leave the visit timer running.
- Check all five supported Assault missions, normal objective messages, required enemy deaths, Rune of Release readiness, mission results, points, stored versus carried tags, and Rytaal's normal updates. A missed enemy death must not become a guessed remaining count. The mission checklist must keep unobserved clears unknown.
- Check Limbus route detection, last identified floor, floor hints, extension messages, coins, materials, chips, and trophy drops. Distinguish found items, personal awards, Inventory counts, and stored balances. Moving items or restoring the treasure pool must not add drops. A vortex interaction alone must not claim a new floor.
- Check Stored Beastmen's Seals and Stored Kindred's Seals against Shami after talking, depositing either seal type, buying each supported orb, and withdrawing seals. Confirmed item receipt must update the affected stored balance once. Cancelling, a full Inventory, duplicate updates, and an unrelated item receipt must not spend seals. Carried readouts must count Inventory only, including while the EXP session is paused or reset.
- Check BCNM, KSNM, and ENM countdown packets, late entry, reloads, and normal remaining-time messages. An advertised full limit must not start a fresh countdown for an existing run. Estimates need `~`; absent timing information stays unknown. Check repeated enemies, reinforcements, changing waves, reward crates, confirmed results, and personal bests without treating every death as a win.
- Check ENM key-item acquisition and the timer NPC's ready timestamp. Consuming the item and winning must not start another wait. Fights sharing the same key item must share one cooldown. **ENM wait on bar** must select the correct group outside the fight without claiming every ENM is ready.
- Check Limbus at Cosmo-Cleanse consumption on entry, with the twenty-hour character wait kept separate from the optional **Limbus account reminder**. Check Dynamis at successful registration with its account-wide seventy-two-hour lockout. Switch between two local characters with the same **Account group**, then different groups and a blank group. Only recorded activity can be shared. A finished wait must not claim full entry eligibility.
- A successfully loaded account record must not be re-read while its countdown advances. Changing characters or groups and reloading must load the saved timers; a newly observed deadline must refresh the record before updating it. Failed reads must retry at a bounded interval.
- Check all nine saved mode layouts through Automatic entry/exit, EXP or merit earning changes, profiles, reloads, shared layouts, and settings resets. Account grouping must remain a character preference through profiles, shared layouts, appearance Undo, and resets.
- Reset Display in each event mode and check that its own starter returns. Reset Events while an event layout is active, then switch through EXP and Merits; their saved readouts must remain intact. These settings resets must stay separate from Reset session.
- Check wanted-drop filtering and pagination, event history and copied summaries, corrupt/conflicting save files, alert enabled counts, and all new alerts starting off. Pause or Reset session must preserve event timers, objectives, drops, cooldowns, and the selected layout.
- Load at launcher startup and during a run. Normal entry, menu, balance, and countdown updates during the three-second startup wait must stay in order, without adding time to a countdown or replaying EXP rewards. Zoning, changing characters, unloading, or invalid data must discard stale context.
- Keep idle work bounded. Closed event pages must not rebuild reference or drop lists, and an idle character without an inventory readout must not trigger event inventory scans. Repeat the operation-count checks after any runtime or readout cache change.

Check startup, sound support, gil, and saved layouts:

- Check launcher startup, loading after login, unloading during the startup wait, and commands entered before the bar appears. Font setup must run between UI frames; commands that measure the bar must wait for an active UI frame. Verify bundled and custom sound choices and sound-handle cleanup. A prior successful Linux check covers that setup, not every Proton version.
- Compare Current gil with the game, then buy and sell to check gained, spent, net change, and Gil/HR. Include zero gil, repeated balances, same-frame updates, inventory loading, zoning, job changes, and reloading a saved session. Inventory loading must not become income, and gil activity must not start EXP/HR.
- While paused, current gil stays live but gains, spending, net change, and Gil/HR hold. Resuming counts only new changes. Reset clears totals and rates while keeping the current balance. Active EXP chain, food, Dedication, EXP ring, and Dynamis timers keep running.
- In the matching game EXP or merit mode, customize the manual layout and return to Automatic with **Switch saved EXP / Merits layouts** enabled. Keep the same readouts, order, labels, colors, and dividers through reloads and profiles. Load inside Dynamis while earning LP, leave, and check that the saved Merits layout returns. Repeat for EXP. Older saved layouts must keep their choices.

Check Dedication, Level Sync, and session UI text as well as the values:

- Dedication status and timer follows the ordinary buff data, and Dedication wore off follows the normal effect-end message. The removed bonus EXP reading and low bonus EXP alert must not appear. Older enabled bonus EXP readings migrate to Dedication status and timer in every saved layout and profile without carrying the old Bonus left label. Other readout choices stay intact.
- Level Sync shows actual level, synced level, and level gap. The manual calculator clearly describes an estimate, never a current applied penalty. The removed penalty-change alert must not appear. Standard missed EXP messages and alerts still work.
- Former custom status messages remain ordinary chat and cannot change readings or trigger extra player sampling. Packaging and source contain no server module or custom feed implementation. Check repeated loading and profile migration without reintroducing removed options.
- In Automatic, the editing label follows the actual saved mode layout, even with automatic switching off or a different EXP/LP display choice. Manual selection needs no duplicate label. Showing the label must not alter settings or rebuild saved layouts.
- Current session and Copy summary show the same current gil gained, spent, net change, and Gil/HR. Check unknown data, known zero, negative values, and held paused totals. The paused-bar help must still name the live timers that keep running.

Check visibility and placement in the live client, and record those results separately from the offline checks:

- Try all three Bar visibility choices above chat, below chat, and in Free placement. Changing placement must keep the chosen visibility option. Close and reopen the main chat log, then change the chat size and resolution. Confirm the native active flag follows the visible chat window.
- In Keep visible when chat closes and Always visible, check that the last drawn bar stays put when chat closes or its position becomes unreadable. Test both a confirmed inactive window and unknown bounds, including a failed read. A smaller client window should move or shrink the bar only enough to stay on screen; returning chat should restore its current anchor.
- Check the saved Free placement fallback before any bar position is available, then Shift drag and resize a held bar. The edit should switch to Free placement. Close and reopen chat during a held resize; keep the last valid size until a new drag. With readable chat but no room on the chosen side, keep the dock hidden and clear of both chat windows.
- Check typing, map, cutscene, hidden game UI, and idle behavior. Always visible should bypass those hide settings, while `/momentum hide` still works with Sample preview off. Escape must close settings during combat and an active edit.
- Load profiles and check their saved visibility policy and placement. Switch bar modes, zone, and reload without changing that choice or carrying a stale chat rectangle into another character or zone.
- Check fresh settings, resets, and missing or invalid visibility choices: all should use Keep visible when chat closes. Only the former placement choice should become Hide with chat for an attached bar or Keep visible when chat closes for Free placement. Preserve each explicit saved choice through loading, profiles, character changes, and reloads.
- Try Chat alignment Center above and below chat with automatic and custom widths. Resize chat, close and reopen it, and check a second chat window. Keep the centered bar outside the chat borders and within its width. Closing chat must hold its last drawn position and size. Switching back to Left must restore Starting point without changing readout order or text alignment.
- Hide and show the bar during an active session and Dynamis run. Confirm rates, drops, alerts, and EXP chain, food, Dedication, EXP ring recast, and Dynamis timers keep updating. Reset and Pause must still preserve their active timers.

## Build and inspect

For Inventory and Mog Satchel readouts, check used/capacity and free slots in each mode, including Automatic. Move, stack, split, buy, sell, and drop items, then check both bags against the game menu. Confirm zero used slots and a full bag display correctly, unavailable counts stay unknown, and capacity follows unlocked space. Test a reload, zoning, and main-to-alt-to-main without showing the previous character's amounts. Pause and Reset session must leave live slot counts updating. With all four readouts off, there must be no storage count reads or item scans.

For centered readouts, check a wide fixed-width bar and a narrow bar with overflow. Keep icons, labels, dividers, and the chosen order together. Check both priority fitting and separate alignment groups, the HUD and inline preview, profiles, shared settings, and every Bar mode. The saved Center choice must survive reloads. Left remains the default; Chat alignment moves the bar separately.

For sounds, check both bundled MP3s and a custom WAV, volumes, repeated Play, chosen alerts, character changes, and unload while playback is starting. File selection must not open an audio decoder. The first Play must leave the game responsive while the player starts. Record actual Windows and Proton results separately from standalone and offline tests.

Include a custom MP3 and WAV with filenames longer than 160 bytes and at the supported 200-byte limit. Both food and event alerts must keep the exact filename through saving, profile loading, and reloading. A 201-byte name must be rejected without selecting an existing shorter filename. Select Dynamis outside a run and with unknown time: its progress fill must stay empty. A known active timer must fill normally, and EXP or LP progress must return when those layouts are selected.

```powershell
python tools/build_release.py
```

The archive goes to Downloads by default. Use `--out PATH` for another output folder. The builder prints its SHA-256. Inspect the ZIP contents and use the printed hash when recording the build.

The runtime ZIP contains `momentum/` with the reviewed addon files and license. It must not include settings, profiles, sessions, event histories, account groups or cooldown records, test output, private paths, or developer files. See [tools/README.txt](../tools/README.txt) for the manifest checks and reproducibility rules.

Review the public source, release notes, archive contents, and image and sound metadata for personal information. Keep only the approved author name, email, and GitHub details. Use sample data in examples; do not include real character names or IDs, chat logs, machine or account names, private paths, credentials, or saved player files. The automated checks cover known markers and the archive manifest, so inspect the media and final files as well.

Record the candidate's version, source commit or pending diff, archive hash, checks run, and any remaining live-client checks in a local verification report. A green offline suite, rendered preview, or matching installed hash proves only that specific check. Keep those results separate from source-rule verification and actual gameplay results.

Generate the release notes from the same version entry used by the draft workflow:

```powershell
python tools/release_notes.py --out tests/out/release-notes.md
```

Check the notes against the final changes and include the update steps that preserve `config/addons/momentum/`. Keep verification results separate from feature claims, and do not describe a local archive as published.

Before release, reload in game with the Ashita font and a selected Windows font.
Check the chosen font after changing it in Appearance, loading a profile, and
switching characters with sharing on and off. A missing font must use Ashita.
Record any reload hitch separately from the normal three-second startup wait.
Check rewards, gil changes, effect-end alerts, and event countdowns received
while the remaining client searches finish. Queued Momentum commands must run
once, after the bar is ready. Unloading during setup must cancel further work.

## Create a draft

After the reviewed source is available in the GitHub repository, a maintainer can open **Actions > Draft release > Run workflow** and choose the intended branch. The workflow:

1. Runs the reusable **Verify** workflow on Windows with pinned Ashita libraries.
2. Reads the current version and changelog entry.
3. Refuses an existing release or tag named `v<version>`, keeping the archive tied to the reviewed source.
4. Builds the runtime ZIP and a SHA-256 file on Ubuntu.
5. Creates a draft named `Momentum <version>` for the selected commit.

The workflow runs only by manual request. Version edits, pushes, tags, and schedules do not create a release. It does not regenerate Phoenix data. Momentum is fully client-side; do not add or package server modules or custom server data feeds.

Review the draft's version, target commit, notes, archive, and checksum. Publishing remains a separate maintainer action on the Releases page. An existing release's files should not be silently replaced.

## Update an installed copy

If Momentum is running, enter `/addon unload momentum` before replacing `addons/momentum/` with the reviewed runtime folder. Keep `config/addons/momentum/`, which holds settings, profiles, shared layouts, sessions, event histories, recorded cooldowns, and custom sounds. Enter `/addon load momentum` after replacing the files.
