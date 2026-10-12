# Momentum

Momentum is an EXP and merit tracking bar for Phoenix on Ashita v4, by Kipling. It sits above or below your chat window, or anywhere you want to drag it. The default bar shows your job, current EXP, TNL, EXP/HR, and EXP chain in a compact, rounded row.

[Download the latest release](https://github.com/KiplingFFXI/momentum/releases/latest) | [Guide](docs/GUIDE.md) | [Changelog](CHANGELOG.md) | [Contributing](CONTRIBUTING.md)

## Install or update

1. Download `momentum-1.0.0.zip` from the release page. If updating a running copy, enter `/addon unload momentum` first. Extract the `momentum` folder into your Phoenix client's `addons` folder. The result should be `addons/momentum/momentum.lua`.
2. Enter `/addon load momentum` in game.
3. Enter `/momentum` to open settings. Escape closes them, including during combat or while editing a field or dropdown.

For an update, enter `/addon unload momentum` first, replace the addon files, then enter `/addon load momentum`. Leave `config/addons/momentum/` alone. That separate folder holds your settings, profiles, session history, and custom sounds. Back it up if you want a copy of your setup. The release ZIP contains only the addon; developer tools and the optional server companion are separate.

## Set up your bar

Open **Display** and choose a **Starter layout**: Minimal, Leveling, or Merits. The Merits layout shows LP/HR, stored merit points, LP needed, and time to the next merit point. The optional **Automatically switch EXP / Merits layouts** follows your character's earning mode, including LP overflow at a full level-75 EXP buffer. It starts off and never changes the game's EXP/LP setting.

Drag readout handles to change their order, or use Up, Down, First, and Last. Add fields from the grouped **Add readout** list. Set labels and dividers for each field, choose Left or Right alignment, or use separate left, center, and right groups. Hover the bar for full values and explanations, including readings hidden behind `...` when space is short.

Under **Position and size**, choose **Below chat**, **Above chat**, or **Free placement**. An attached bar follows chat's width and stays outside its text and border. **Starting point** moves the left end along chat, **Gap from chat** adds space, and **Bar height** makes the bar taller or shorter. An attached bar waits if its chosen side has no room or chat cannot be read.

Choosing Free placement keeps the visible size and position, turns snapping off, and unlocks movement and resizing. Hold Shift to drag the bar or resize its right and bottom edges. **Lock movement and resizing** holds it in place afterward. You can also enable snapping when dropped near chat. The bar lets mouse input pass through during normal use, and **Hide while typing** is on by default.

Choose from eight skins under **Appearance**, including Phoenix's burgundy, warm white, and red. Bar and settings colors, fonts, text sizes, corners, opacity, and progress fill can be changed separately. Job pictures come from your installed client, with the job name and level beside them, such as `(WAR) 32`.

## EXP, merits, and sessions

- Track EXP and LP together or separately, with rates over the last 5, 15, or 30 minutes or the whole session. Choose reported gains or points kept after losses and recovery.
- Show LP toward the next 10,000-point merit conversion, stored merit points and capacity, free slots, merits earned this session, and merit pace. Spending merits does not reduce session earnings. Full storage shows **Spend merits** instead of promising another point.
- Follow EXP chains with a local countdown from Phoenix's rules. It is marked `~` because the monster's EXP level and exact server deadline may be unknown. The chain may remain open longer. Below 10 seconds, the timer turns red by default; you can change that color.
- Add goals, recent gain averages, food and Dedication timers, EXP ring charges and recast, and Level Sync details.
- Save, name, and review sessions by character and job. Resuming after a reload excludes time while the addon was unloaded.

**Pause session** and **Reset session** stay at the top of settings. Pause excludes session gains and time while current balances keep updating. Reset saves the old session and starts a new one; EXP/HR, LP/HR, and Next clear until enough new data is collected. Neither action restarts or clears active EXP chain, food, Dedication, or EXP ring recast timers. Your current EXP, LP, stored merits, and layout stay the same. Paused alerts follow your choice under **When to mute alerts**.

Rates need one minute of session time before they appear. Unknown readings stay `--`; estimates use `~`. Momentum reads client state and incoming packets. It does not send gameplay commands, use items, or switch your character's EXP/LP mode.

## Alerts and saved choices

The **Alerts** page groups food, EXP chains, Dedication, EXP rings, levels and merit points, and Level Sync or missed EXP. Collapsed headings show how many alerts are on. Open a group and check **Show notice**, **Play sound**, or both; all alerts start off. Each alert counts once even when both choices are on.

For a food wear-off sound, open **Food** and check **Play sound** under **Food effect wore off**. Select a file, set the volume, and use **Play** to try it. The alert follows a confirmed food-end message, which can also occur when food is removed. Loading, zoning, or a missing icon alone does not trigger it.

Settings save after an edit finishes. **Undo** keeps the last eight edits. Search and hover help explain the controls, and the fixed Live/Sample preview lets you try layouts. Save profiles for different jobs, or share one layout across characters while keeping their session records separate.

## Phoenix rules and limits

The bundled rules come from a pinned Phoenix source revision. Current EXP, LP, and merit capacity come from the client. Reported awards can exceed points kept at a cap; EXP lost, recovered, and otherwise adjusted are tracked separately when observed.

The addon and its local EXP chain countdown work without server changes. Exact applied Level Sync penalties and remaining Dedication bonus EXP need an optional report from Phoenix. Without one, those values stay unknown. Your EXP/HR still includes the effect of any penalty on the EXP you receive or keep. The separate **Level Sync estimate** calculator is a planning aid and does not claim to be your applied penalty.

The [optional server companion](server/README.txt) is for server operators. Its native chain reader can provide a server deadline instead of a local estimate. Including it in this repository does not mean it is deployed on Phoenix.

See the [guide](docs/GUIDE.md) for controls, commands, and tracking limits. Developer setup and offline checks are in [Contributing](CONTRIBUTING.md) and [tests/README.txt](tests/README.txt); packaging instructions are in [tools/README.txt](tools/README.txt).

## License

Addon code is licensed under GPL-3.0-or-later. See [LICENSE](LICENSE). The bundled Final Fantasy VII and Final Fantasy IX sounds belong to Square Enix and are not covered by that license; see [the sound notice](momentum/sounds/README.txt). Job artwork is read from the installed game client and is not distributed in the addon.
