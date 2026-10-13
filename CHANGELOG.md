# Changelog

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
