# Changelog

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
