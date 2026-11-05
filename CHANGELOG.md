# Changelog

## 1.6.3

- Added **Hide while the chat log is open** under **Tracking > Visibility**. It starts off and hides the bar while you read the expanded log. The bar returns when you close it. Tracking, alerts, timers, and settings stay available.
- The choice stays saved with profiles and shared layouts. **Hide while typing** remains separate, and **Always visible** keeps the bar up without clearing your saved hide choices.
- All sound options, the Linux fix, and permanent custom-sound protections are kept.

### Updating

Enter `/addon unload momentum`, replace `addons/momentum/` with the release's `momentum` folder, then enter `/addon load momentum`. Settings, histories, recorded cooldowns, and custom sounds stay in the separate `config/addons/momentum/` folder. The update must leave that folder unchanged.

## 1.6.2

### Sounds

- **Alerts** now shows the permanent custom-sound folder, with **Copy sound folder path** and **Copy to permanent folder** for sounds still in the addon folder. Copying keeps the original file and alert selection, and never overwrites an existing file. No files are copied during startup or normal playback.
- Permanent custom sounds are user data. The release package excludes `config/addons/momentum/`, and updates must leave it untouched. Refresh and reopening Alerts recognize an existing permanent copy without offering another copy action.
- Custom MP3/WAV filenames now support Unicode while keeping older saved filenames working. A failed sound stays blocked from automatic retries even when another sound plays, its capitalization changes, or another alert selects None. **Play** and **Refresh** still let you retry it.
- All bundled and custom sound choices, volume controls, the isolated sound player, and the Linux sound fix are kept.

### Fixes

- Fixed shared readout edits being lost when a save failed before switching characters. Pending edits keep their normal retry and stay separate from each character's private settings.
- Fixed received-drop tracking for items already in the treasure pool when Momentum loads or reloads, across Farming, Dynamis, and other events.
- Fixed the next Imperial Army I.D. tag readout and entry waits that could stay at **0:00** after ending.
- Fixed **Reset this section** on Display loading EXP readouts in Farming or Automatic Merits, and corrected the active Farming layout label in Automatic.
- Fixed one character's alert cooldown suppressing alerts on another. Normal alert throttling through zoning is kept.

### Performance

- Reduced session-save work and retained memory by reusing unchanged history records. History files, retention, resume, reset, pause, and protection against corrupt or externally changed files are kept.

### Updating

Enter `/addon unload momentum`, replace `addons/momentum/` with the release's `momentum` folder, then enter `/addon load momentum`. Settings, histories, recorded cooldowns, and custom sounds stay in the separate `config/addons/momentum/` folder. The update must leave that folder unchanged.

## 1.6.1

- Refreshed the EXP, Dynamis, and event source references to Phoenix's October 30 live code.
- Updated the refresh tools for Phoenix's YAML EXP table and current module data folders, including the enabled era and Phoenix overlays.
- Added source checks for invalid EXP data and missing era Dynamis data. The tracked values remain the same as 1.6.0.

### Updating

Enter `/addon unload momentum`, replace the whole `momentum` folder in your Phoenix `addons` folder, including `bin`, then enter `/addon load momentum`. Keep `config/addons/momentum/` for your settings, profiles, history, recorded cooldowns, and custom sounds.

## 1.6.0

Farming mode adds personal drop counts, item rates, goals, and optional item values alongside your gil. This update also adds subjob text and reduces work during startup, reloads, and normal tracking.

### Farming

- Added **Farming** as a bar mode and starter layout with personal Items received, Items/HR, net gil, Gil/HR, and Inventory free slots. Its saved layout stays separate from EXP and Merits. **Use Farming outside events** is an optional Automatic fallback; detected event layouts still take priority.
- Added twelve optional Farming readouts in every mode, with watched-item counts and rates, time since the last item, item or stack goals, an optional goal fill, pool drops seen, and gil from defeated monsters. Item rates use observed, unpaused farming time and need one minute after the first received item.
- Farming lists received and recent items, supports watched-item and goal alerts plus low-space warnings, and copies a farming summary. New alerts start off and retain the existing notice, sound, volume, and quiet options. Only current-character Inventory and Mog Satchel space is used.
- Optional manual unit prices estimate loot value and value per hour separately from actual gil changes. Unpriced loot is not assigned a value, and estimated loot value is never added to wallet gil as profit.
- Farming follows confirmed personal treasure awards, including solo loot, crystals, seals, and normal treasure-pool chest drops. Purchases, trades, synthesis, bag moves, fishing, HELM, digging, and Steal do not become drops. Existing pool items seen on loading are not new pool drops, but count if later awarded to you.
- Farming totals follow the current character/job session through saving, pause, reset, and reload. Shared layouts share preferences, not totals. Pause and reset leave buff, chain, ring, and event timers running, and leave event-specific drop totals with their event run.

### Startup and tracking

- Momentum loads only your selected custom font instead of registering every Windows font on each reload. The Ashita font needs no extra font files. All font choices remain available, including when switching profiles and characters.
- Client searches finish one at a time across frames during startup. Tracking continues while they finish, and saved timers use the game clock before they are restored. The existing pointer and chat-window checks remain in place.
- Sound folders load only when a sound list is needed. Opening settings does not scan them, and reopening a sound list still picks up added files. Session saves also avoid encoding the same data twice.

### Jobs, layouts, and fixes

- Added a **Show subjob and level** toggle to the **Job and level** readout. It adds text such as `/ NIN 37` after your main job and keeps only the main job icon. It starts off and is saved with each layout and profile, including the layouts used by Automatic.
- The subjob level follows the game through Level Sync, job changes, and character changes. No available subjob leaves just the main job, and unavailable levels stay unknown. Pause and Reset session leave live job information updating.
- Fixed Assault, Limbus, BCNM, KSNM, and ENM alerts being rejected before they could appear or play. Their chosen quiet conditions and time between alerts still apply.
- Fixed false save-conflict warnings for Dynamis and event records when timer values contained fractional seconds. Actual conflicting file changes are still detected.
- Fixed Dynamis updates being skipped because its packet reader rejected Ashita's native event objects. Event timing, normal packet checks, and startup buffering now use the supported fields, avoiding errors from unavailable fields.
- Returning from the Farming fallback now restores the saved Merits layout correctly when EXP / Merits switching is off. Enabling Farming and returning to Automatic keeps the previous layout choice.
- Shared layouts load at startup, when switching characters, and when changing the sharing option. The shared settings file is no longer polled while you play.
- Recorded account timers keep counting down without reopening their file every few seconds. Character or group changes load the saved timers, and new entries still update the recorded deadlines.
- Long custom MP3 and WAV filenames now stay intact when their alert settings are saved. Names over the supported limit are cleared instead of being shortened into another filename.
- The Dynamis progress line stays empty until a current run has usable time remaining. Selecting Dynamis outside a run no longer shows unrelated EXP progress.
- Searching for subjob now leads directly to **Job and level**, where its toggle is available.
- Profiles no longer offers **Reset this section**, which had no effect. Its separately confirmed **Reset layout** option remains available.

### Updating

Enter `/addon unload momentum`, replace the whole `momentum` folder in your Phoenix `addons` folder, including `bin`, then enter `/addon load momentum`. Keep `config/addons/momentum/` for your settings, profiles, history, recorded cooldowns, and custom sounds. All MP3/WAV choices, volume controls, and the Linux sound fix are kept.

Choose **Bar mode > Farming** for the compact Farming layout. Set watched items, goals, and manual unit prices on the **Farming** page. Enable optional notices and sounds under **Alerts > Farming**. Item rates appear after one minute of unpaused farming time following your first received treasure item. To use Farming between events, select **Automatic** and turn on **Farming > Use Farming outside events**.

For subjob text, select **Display > Readouts and order > Job and level**, then enable **Selected readout > Show subjob and level**. It starts off in each saved layout.

## 1.5.0

- Added optional Inventory and Mog Satchel slot readouts in every bar mode. Choose used slots and capacity, free slots, or both. Only your current character's Inventory and Mog Satchel are tracked.
- Added Center to Readout alignment. The full row stays centered inside a custom-width bar while preserving its order, labels, icons, and dividers. Left remains the default, and Chat alignment still controls the bar's position separately.
- Slot counts keep updating during session pause and reset. Loading or unavailable counts stay unknown, and character changes clear the previous character's values. Only selected bags are read, using cached client slot counts rather than item scans.
- Choosing a sound no longer opens an audio decoder. Sounds load only when an alert or Play requests them.
- Sound playback runs in a separate hidden player so a decoder crash cannot close the game. MP3, WAV, custom sounds, volume controls, and the Linux directory scan are kept.
- The sound player starts in the background so process creation does not hold up the game's drawing thread on the first Play.
- Returning to a character keeps the latest saved bar layout and placement instead of reloading an older job profile. Job profiles still apply when you change main jobs on that character.

### Updating

Enter `/addon unload momentum`, replace the whole `momentum` folder in your Phoenix `addons` folder, including `bin`, then enter `/addon load momentum`. Keep `config/addons/momentum/` for your settings, profiles, history, recorded cooldowns, and custom sounds. The bar appears about three seconds after your character is ready.

Add slot readings under **Display > Add readout > Storage**. To center the whole row, choose **Display > Position and size > Readout alignment > Center**. Turn off separate alignment groups if you want one alignment for all readouts. Chat alignment still positions the bar separately.

## 1.4.0

Track Assault, Limbus, BCNM, KSNM, and ENM alongside EXP, merits, gil, and Dynamis. Each mode keeps its own layout, and Automatic can follow the event you enter.

- Added separate saved Assault, Limbus, BCNM, KSNM, and ENM layouts, manual selection, and optional Automatic switching. Leaving an event restores the previous layout. Existing readouts, themes, profiles, placement, and sounds are kept.
- Added Time in zone and Current zone readouts in every mode. Loading during a visit shows the time observed since loading, marked with `~`.
- Added the Events page for observed objectives, found treasure and personal awards, entry items, stored balances, wanted drops, optional alerts, fight references, and run history. The reference follows the pinned Phoenix source. Hidden progress and missed drops stay unknown.
- BCNM, KSNM, and ENM use the game's normal battlefield countdown when available. Assault and Limbus wait for usable remaining-time updates and mark estimates with `~`. An advertised full time limit does not restart an existing run's clock.
- Added Next ENM key item and Next Limbus entry readouts. ENM waits start when the entry key item is obtained; fights using the same item share one wait. Limbus starts its twenty-hour character wait on entry, when the entry key items are consumed. Normal NPC timer updates take priority over local estimates.
- Added optional local account groups for recorded Dynamis timers and Limbus reminders. Dynamis has a seventy-two-hour account-wide lockout from successful registration. Phoenix currently tracks Limbus per character, so its shared account reading is labeled as a reminder. Only activity observed on grouped characters on this computer can be shared.
- Added Chat alignment with Left and Center choices above or below chat. Center supports compact automatic width or a custom width, follows chat resizing, and holds its last position when chat closes. Returning to Left restores the saved starting point.
- Stored Beastmen's Seals and Kindred's Seals refresh when talking to Shami, depositing seals, buying an orb, or withdrawing seals. Purchases and withdrawals update after confirmed item receipt; cancelled or failed transactions leave the balance alone. Hover help separates seals stored with Shami from seals carried in Inventory.
- Resetting Display in an event mode restores that mode's starter. Resetting Events preserves your saved EXP and Merits readouts.
- Repeated treasure-pool updates no longer count the same event drop twice after entry.
- Clearer hover help for carried and stored seals and coins, EXP chain estimates, and Limbus floors. Hovering an event bar with text hidden now explains its time reading, including unknown or estimated time.
- Invalid saved event timers no longer break the bar or its alerts. Account timers retry failed file operations at a set interval instead of on every tracking update.
- EXP session pause and reset leave zone visits, event timers, objectives, drops, and cooldowns running. New alerts start off. Momentum stays client-only and sends no gameplay commands.

### Updating

Enter `/addon unload momentum`, replace the `momentum` folder in your Phoenix `addons` folder, then enter `/addon load momentum`. Keep `config/addons/momentum/` for your settings, profiles, history, recorded cooldowns, and custom sounds. The bar appears about three seconds after your character is ready.

Use **Bar mode** to choose a layout. For event switching, choose **Automatic** and enable **Events > Event tracking options > Switch event layouts in Automatic**. For a compact centered bar, use **Display > Position and size > Chat alignment > Center**. All new readings are available under **Display > Add readout**.

## 1.3.2

- Removed the Dedication and Level Sync tracking module that was erroneously kept from testing, along with its custom data feed, server-only readouts and alerts, and server packaging tools. Momentum is fully client-side and will never require a server module or custom server data feed.
- Dedication status, its available timer, and the wore-off alert still use normal client data. Older layouts with the removed bonus EXP reading switch to Dedication status and timer without the old Bonus left label.
- Level Sync still shows actual level, synced level, and level gap. The manual penalty calculator remains an estimate. The stored applied penalty is not available from normal client data and is no longer offered as a reading or alert.
- EXP chain timing stays a local estimate based on Phoenix's rules. Removed the unused custom deadline feed. Food, EXP rings, EXP, merits, gil, Dynamis, sounds, and session tracking remain available.
- Updated the menus, hover help, guide, and developer instructions to match the client-only behavior. Existing layout choices and profiles are kept apart from the removed options.

### Updating

Enter `/addon unload momentum`, replace the `momentum` folder in your Phoenix `addons` folder, then enter `/addon load momentum`. Keep `config/addons/momentum/` for your settings, profiles, history, and custom sounds. The bar appears about three seconds after your character is ready.

## 1.3.1

Dedication choices now explain which reading tracks the buff and which needs extra server data. This update also makes saved layouts in Automatic easier to identify and adds gil to session summaries.

- Renamed the buff readout to Dedication status and timer. Dedication bonus EXP (server data) and its low bonus EXP alert now explain that they need extra Phoenix server support. An unknown bonus amount does not mean the buff is inactive. The Dedication wore off alert uses the game's normal effect message.
- Renamed the Level Sync alert to Level Sync penalty changed (server data). Its help explains that it watches reported penalty changes; starting Level Sync or changing its level alone does not trigger it.
- Readouts and order shows Editing EXP layout, Editing Merits layout, or Editing Dynamis layout while using Automatic. It identifies the saved layout receiving your edits, including when automatic switching is off.
- Current session and Copy summary now include gil gained, gil spent, net gil change, and Gil/HR. Known zero values stay zero, unknown values show --, and spending can produce a negative net change or rate.
- Updated the Paused tooltip to explain that session gil changes stop counting while current gil and active EXP chain, food, Dedication, EXP ring recast, and Dynamis timers keep updating. Dynamis drops still count.

### Updating

Enter `/addon unload momentum`, replace the `momentum` folder in your Phoenix `addons` folder, then enter `/addon load momentum`. Keep `config/addons/momentum/` for your settings, profiles, history, and custom sounds. The bar appears about three seconds after your character is ready.

To track the Dedication buff, open **Display > Add readout > Buffs** and choose **Dedication status and timer**. **Dedication bonus EXP (server data)** may stay `--` without extra Phoenix server support; using a ring earlier or reloading does not supply that amount.

## 1.3.0

Track gil alongside EXP, merits, and Dynamis, keep your saved readouts in Automatic, and use the Linux sound fix without losing any sounds or settings.

- Added optional Current gil, Gil gained, Gil spent, Gil change, and Gil/HR readouts to every bar mode. Gil/HR subtracts spending and starts after one minute of tracking from the first observed gil change. Reset clears gil totals and the rate; pause leaves changes out of totals while current gil keeps updating.
- Gil totals save with your EXP/LP session. Loading your inventory sets a new balance without counting it as a gain or loss. Unloaded time and inventory gaps do not count toward Gil/HR.
- Automatic and manual EXP / Merits selection now use the same saved layouts. Added readouts, labels, dividers, and order stay with each mode across switches and reloads, including a reload inside Dynamis. Job changes no longer reapply starter layouts. Renamed the option to Switch saved EXP / Merits layouts.
- Momentum waits until your character has been in-game for three seconds before loading its settings, tracking, fonts, sounds and display. This applies to launcher startup and manual loads. Zoning or changing characters during the wait restarts the delay.
- Commands entered during the startup wait run once Momentum is ready. Free placement waits for an active UI frame before measuring the bar, including when entered during startup. Commands keep their order, and unloading cancels queued commands. Font setup waits until the UI is between frames and runs once.
- Sound support loads when an alert or sound test needs it. All sounds, alerts and saved settings are kept.
- Fixed a Linux/Proton issue that could freeze the game when using cooldown abilities or zooming the minimap. Momentum now scans sound files directly, avoiding the shared helper involved in the conflict. Bundled and custom sounds still work.

### Updating

Enter `/addon unload momentum`, replace the `momentum` folder in your Phoenix `addons` folder, then enter `/addon load momentum`. Keep `config/addons/momentum/` for your settings, profiles, history, and custom sounds. The bar appears about three seconds after your character is ready.

Open **Display > Add readout > Gil** to add the optional gil readings. To follow the EXP and Merits layouts you have saved, choose **Automatic** and enable **Switch saved EXP / Merits layouts**. Pausing keeps your current gil live while leaving those purchases and sales out of session totals and Gil/HR.

## 1.2.0

- Three Bar visibility choices under Tracking: Hide with chat, Keep visible when chat closes, and Always visible. Your choice stays selected when you attach or freely place the bar.
- Keep visible when chat closes is the default for new or reset settings and when no usable choice was saved. Saved choices are kept. The former placement-based setting still migrates to Hide with chat for an attached bar, or Keep visible when chat closes for Free placement.
- Hide with chat also works in Free placement. Keep visible when chat closes respects your other hide settings; Always visible keeps the bar up while typing, viewing the map, during cutscenes, and with the game UI hidden. Manual hiding still works when Sample preview is off.
- Keep visible when chat closes and Always visible keep the bar where it was drawn when chat closes or its position becomes unreadable. It follows the current chat position again when chat returns. The saved Free placement position is only a fallback before a bar position is available.
- Fixed Shift dragging and resizing while the bar is kept in place without chat. Moving or resizing it switches to Free placement and keeps your edit. With readable chat bounds, a dock without enough room stays hidden. Tracking and timers continue while the bar is hidden.
- A resize now stops safely if chat disappears, returns, or leaves no room for the bar partway through the drag. Your last valid size is kept.
- Reduced work while chat is closed without slowing tracking or alerts.

### Updating

Enter `/addon unload momentum` before replacing the addon files. Keep `config/addons/momentum/` for your settings, profiles, history, and custom sounds, then enter `/addon load momentum`. Open `/momentum` and choose **Tracking > Visibility > Bar visibility** to pick when the bar stays up.

## 1.1.1

Track Dynamis alongside EXP and merits, and choose which bar you want to use. Your existing settings and sounds carry over.

- Dynamis mode for Phoenix's ten Dynamis zones. Automatic can use its compact layout when you enter and restore your regular layout when you leave.
- Bar mode stays at the top of settings, with EXP, Merits, Dynamis, and Automatic choices. Manual modes stay selected through closing settings, reloading, and zone changes.
- Each manual mode keeps its own readouts, order, labels, and dividers. Automatic restores your regular setup and resumes the automatic layout options you have chosen.
- `/momentum mode exp`, `merits`, `dynamis`, and `auto` switch the bar from chat. The existing `lp` command still selects Merits.
- Switching bars leaves the game's EXP/merit mode, session totals, Dynamis tracking, and timers alone.
- Perpetual Hourglass countdown and time extensions, including recovery from the hourglass after joining late or reloading. Dynamis needs no server companion.
- Currency and relic armor found in the treasure pool, separate personal awards, currency by nation, hundred-pieces, currency per hour, and a searchable wanted-drop list.
- Observed monster defeats, zone objectives and boss weakening, support job restrictions, Weakness, clear key items, and treasure pool details. Unseen progress stays unknown; partial runs are labeled.
- Optional Dynamis time, extension, wanted-drop, treasure pool, clear, and support job alerts. All start off and use the existing notice, sound, and mute settings.
- Separate Dynamis run history for each character, local summary copying, and a confirmed action to clear drop and kill totals while keeping the hourglass and objectives. EXP session pause and reset leave Dynamis tracking running.
- A recorded 72-hour account lockout countdown after an observed registration. It cannot see registrations on other characters or confirm entry eligibility.
- Improved Dynamis run recovery when the computer clock is slightly behind the hourglass.
- Reduced repeated work while settings are open and when no Weakness effect is active. Timers and tracking keep updating normally.
- Pinned Phoenix Dynamis data export, offline packet and recovery tests, and a rendered Dynamis preview.

### Updating

Enter `/addon unload momentum`, then extract the release ZIP's `momentum` folder into your Phoenix `addons` folder and replace the old addon files. Keep `config/addons/momentum/` for your settings, profiles, history, and custom sounds. Enter `/addon load momentum`, then use **Bar mode** at the top of `/momentum` to choose EXP, Merits, Dynamis, or Automatic.

## 1.0.0

Initial release.

- Compact EXP and merit bar with automatic placement above or below chat, a starting-point slider, adjustable height, free dragging and resizing, and optional snapping.
- Job pictures and abbreviations, current EXP, TNL, EXP/HR, LP/HR, progress, and estimated time to the next level or merit point.
- Phoenix-based EXP chain bonuses and a local countdown, with a configurable warning color below 10 seconds. Unknown timing stays unknown, and local estimates are marked.
- Merit tracking for LP progress, stored points and capacity, free slots, points earned this session, and estimated merit pace. Full storage asks you to spend merits before another conversion.
- Minimal, Leveling, and Merits starter layouts, plus an optional automatic switch that follows the character's actual EXP/LP mode.
- Reorderable readouts with custom labels, dividers, left or right alignment, optional alignment groups, visibility conditions, and overflow priorities.
- Session rates, recent gain statistics, goals, death losses and recovery, saved history, and resume by character and job. Reset clears the session readings while preserving active chain, food, Dedication, and EXP ring recast timers; pause preserves those timers too.
- Food and Dedication status, readable EXP ring charges and recast, Level Sync details, and a separate Phoenix penalty calculator. Optional server reports can supply values the client does not expose.
- Optional visual and sound alerts, grouped by purpose with enabled counts. Food wear-off sounds stay off until chosen, and alerts respect pause and event mute settings.
- Eight skins, separate bar and settings colors and text sizes, custom fonts, rounded corners, opacity, and progress fill controls.
- Searchable settings, hover help, Live/Sample previews, Undo, saved profiles, job profiles, and shared layouts. Escape closes settings even during combat or an active edit.
- Reproducible runtime archives, source-rule checks, offline tests, and rendered UI checks for contributors.
