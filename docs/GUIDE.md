# Momentum guide

Enter `/momentum` to open or close settings. Press Escape to close the menu, including during combat, while editing a setting, or with a dropdown open. Your edits are kept, and pending reset or delete confirmations are canceled. The compact, rounded bar attaches to the chat window automatically.

**Pause session** and **Reset session** stay at the top of settings on every page. Reset saves the current session and starts a fresh one with one click. **Reset...** contains separate actions for settings, so resetting a session does not change your layout.

Open or close settings sections by their headings. Their open state stays with your character. Searching can open sections temporarily without replacing your saved choices. Hover a **(?)** for an explanation. **Use a tab dropdown** under Appearance replaces the page buttons with a dropdown when you prefer a smaller header.

## Install and update

If updating a running copy, enter `/addon unload momentum` first. Extract the `momentum` folder from the release ZIP into your Phoenix client's `addons` folder. Check that the result is `addons/momentum/momentum.lua`, then enter `/addon load momentum`.

Keep `config/addons/momentum/` when updating. Settings, profiles, shared layouts, session history, and custom sounds live there, separate from the addon files. Copy that folder somewhere safe to back up your setup. Updating the addon does not require resetting settings or deleting old sessions.

## Arrange the readouts

Open **Display** and drag a readout's handle to another position, or select it and use **Up**, **Down**, **First**, or **Last**. The checkboxes control visibility. Hidden readouts keep their place in the order.

**Readout alignment** chooses Left or Right inside the bar. The whole row, including icons and dividers, moves together. Readouts keep their selected order from left to right. This also applies to the inline preview and saved profiles.

**Label position** chooses Before value or After value. Before value is the default: `EXP/HR 8,500` and `TNL 7,550`. After value shows `8,500 EXP/HR` and `7,550 TNL`. This changes the text within each readout; Readout alignment still chooses which end of the bar holds the row.

Independent alignment groups can place selected readouts on the left, center, or right of the same bar. **Keep visible first** and **Display priority** choose which fields stay visible when space is short, without rearranging the remaining fields. A very narrow bar can still run out of space. **Show when** can limit a readout to EXP, LP, a running EXP chain timer, a food effect, Dedication, Level Sync, or a known value. Hidden fields do not leave stray dividers.

Each row in **Readouts and order** has Show and Divider checkboxes. The list starts with your chosen readouts. Use **Add readout** to browse Progress, Merit points and LP, Session, Buffs, or Detailed statistics, or switch to **All readouts**. Filtering does not change the bar's order or visibility. The divider follows its readout when you change the order. The first visible readout in each alignment group never starts with a divider. The selected readout puts its label, divider, and colors first, with conditions and overflow controls under **More options**. Clear a label to show only its value and any built-in EXP or LP unit. Selecting **EXP chain timer** also gives you the **Below 10 seconds** text color, which defaults to red.

The **Divider style** choice sits beside the readout list. Choose a line, slash, dash, dot, asterisk, spaces, or no divider. **Add dividers to all** enables a divider between every visible readout; **Remove all dividers** turns them off. Adding a divider when the style is blank chooses a visible line. Hidden readouts never leave stray dividers. Under **Dividers and formatting**, enter custom text or change the gap and divider color; **Label separator** controls the separator inside a readout.

Starter layouts provide Minimal, Leveling, and Merits arrangements. Merits shows a compact row of LP/HR, stored merit points, LP to the next merit, and the next-merit timer, in that order. These four readings follow LP regardless of the main display mode. Applying a starter changes the enabled readouts and order. The selector shows **Custom** when your chosen readouts or order differ from a starter layout. Save your preferred arrangement as a profile if you want to return to it later.

**Automatically switch EXP / Merits layouts** is an optional checkbox beside Starter layout. It starts off. Turn it on to choose Leveling for the character's EXP mode and Merits for LP mode. It follows actual job level and the client's earning mode, including LP overflow at a full level-75 EXP buffer. A level-75 job still follows merit mode while level synced below 75. It waits for usable character data during loading and zoning.

Automatic switching changes the shown readouts and their order. It keeps labels, colors, dividers, alignment, placement, and session totals. Readout edits you make afterward remain until the next actual mode change; disabling the option keeps the current arrangement. Changing the sample preview or **Show EXP or LP** does not trigger a layout switch. The option never changes the character's earning mode. Each client switches locally, even when characters share an appearance.

| Readout | What it shows |
| --- | --- |
| Job and level | Main job picture, abbreviation in parentheses, and actual level, with an effective level when synced. |
| EXP / LP progress | Current EXP or LP and the amount needed to fill the bar. |
| TNL / LP needed | Points to the next level or merit; EXP buffer space at level 75. |
| EXP/HR | EXP per hour over the selected time period; changes to LP/HR in merit display. |
| Time to next level or merit | An estimate using the current pace. |
| EXP chain | Last confirmed chain and its bonus. |
| EXP chain timer | One local countdown from Phoenix's timing tables, marked with `~`; red by default below 10 seconds. Change Chain ending text under Appearance > Bar colors. Shows `--` before an observed chain or after the estimate expires. |
| Last EXP / LP reward | Last reported EXP or LP award. |
| Progress percent | Percentage filled. |
| Stored merit points | Unspent merit points and the client-reported capacity. |
| Merit points per hour | LP/HR divided by 10,000, independent of the displayed EXP/LP mode. |
| Merit points earned this session | Observed whole merit points earned; spending does not reduce this count. |
| Merit points before cap | How many more merit points you can store. |
| LP to next merit point | LP needed for the next conversion, or Spend merits when storage is full. |
| Time to next merit point | An estimate from LP/HR, or Spend merits when storage is full. |
| Goal progress | Remaining progress toward the selected level, session EXP, earned merits, stored merits, or buffer target. |
| EXP buffer | Current EXP buffer while viewing LP. |
| Session EXP / LP received | Reported awards in the displayed mode. |
| Session progress | Observed retained progress in the displayed mode. |
| Session time | Session duration, excluding manual pauses. |
| Average EXP / LP gain | Average reported award in the displayed mode. |
| Best EXP chain | Highest confirmed chain in the session. |
| Dedication | Whether the status is active, with time remaining when available. |
| Tracking status | Paused, collecting a rate, or capped state. |

Additional selectable fields cover EXP and LP progress/rates/totals independently, averages of recent gains, gains counted, Level Sync penalty and level gap, food effects, EXP rings, Dedication's remaining bonus EXP, and server no-EXP reasons. These start disabled to keep the default bar compact. **Recent gains to average** under Tracking sets the number of gains to compare. **Recent EXP and LP** under Details shows the full breakdown, including the middle, lowest, and highest recent gains.

## Place the bar

Expand **Position and size** under **Display**, then choose **Below chat**, **Above chat**, or **Free placement**. Selecting Free placement unlocks movement and resizing, even if a saved layout was locked. Hold Shift to drag or resize the bar. Enable **Lock movement and resizing** afterward to hold it in place. It ignores movement while you type in chat.

Use **Bar height** directly below Placement to make the bar taller or shorter, from 12 to 120 pixels. The text size stays separate under **Appearance > Bar text size**. An attached bar fits the space outside chat without covering its text or border.

For either chat anchor, **Starting point** sets the bar's left end in pixels from the left edge of chat. Its right end stays aligned with chat, leaving at least 120 pixels for the bar where possible. The starting point is limited automatically when chat becomes narrower. **Gap from chat** leaves space outside its border. The bar fits the available height on the selected side; it stays hidden if chat cannot be read or that side has no room.

**Free placement** preserves the visible size and position and turns snapping off, so dragging near chat keeps the bar free. Drag the right edge for width and the bottom edge for height. Above chat, use the outer top edge to change height while keeping the anchor. Dragging the right edge of an attached bar detaches it. **Fit width to readouts** uses the space the visible readouts need, up to **Maximum width**; turn it off for a fixed **Custom bar width**.

The bar lets mouse input pass through unless you hold Shift to move or resize it. **Hide while typing** is on by default and can be turned off. It reads the game's chat bounds without moving or resizing the chat window.

Enable **Snap to chat when dropped nearby** to attach the bar when you release it within 18 pixels of either chat edge's dock. The nearer edge wins. Free bars are kept on screen when the client size changes. Set **Lock movement and resizing** after placing it.

When the text will not fit, the bar shows `...`. Hide less useful readouts, shorten labels, use short numbers, or make the bar wider. Hover a readout to see its full value and explanation; hover the overflow marker for the hidden readings and their full values. Hovering keeps the bar click-through. Holding Shift to move it or typing in chat suppresses hover help.

The settings preview stays visible while you scroll. Its fit feedback uses the actual bar width, including the detected chat width when anchored. A settings panel that is narrower than your bar does not mean the bar itself is out of room.

## EXP, LP, and rates

Under **Show EXP or LP**, **Automatic** uses the client's EXP/LP mode. At the full level-75 EXP buffer it follows overflow into LP. You can choose EXP or Limit points (LP) without changing the character's gameplay mode.

Under **EXP/HR time period**, choose the last 5, 15, or 30 minutes, or the whole session. The session begins when progress or a reward is observed. Rates wait for one minute of session time before appearing. A break with no new rewards lowers the rate; pause the session if you want to exclude a break.

Under **Rate calculation**, **EXP/LP received** measures awards reported by the server, including EXP items. **EXP/LP kept** measures retained progress, including losses and recovery. At a cap, reported rewards may exceed retained progress. Unknown values display as `--`; estimates use `~`. The main EXP/HR readout follows the displayed mode; EXP/HR (always) and LP/HR (always) let you show both at once.

Monstrosity uses a separate progression system and is not tracked as normal job EXP.

One merit requires 10,000 LP. Stored-merit capacity comes from the client. With full merit storage, LP can fill to 9,999 but cannot convert into another merit point. The next-merit readouts show **Spend merits** until space is available. Stored points, free slots, LP progress, session merits, LP/HR, and merit estimates can all appear alongside EXP.

A stored-merit goal changes when you spend merits; a session-merits goal counts observed merits earned in that session. LP held at the start can help earn the first point. Spending stored points does not subtract from session earnings or count as an LP loss. Unobserved changes during a reload, zone transition, or pause are not reconstructed. Other goals cover a target level, session EXP earned, or current EXP buffer. ETAs use a matching EXP or LP rate and remain estimates. At level 75, the EXP bar shows the buffer instead of promising level 76.

Chain bonuses follow Phoenix's rules: 20%, 25%, 30%, 40%, then 50% for chain 5 onward. Phoenix chooses the next-chain window from the defeated monster's EXP level. After an observed chain reward, Momentum starts one local countdown using those tables. The reward packet does not identify the monster's level, so the addon uses the shortest applicable window when that level is unavailable. The actual chain can remain open longer. The next monster must still qualify.

Local timing needs no server installation. The single countdown is marked with `~` because it starts when the reward reaches your client. It shows `--` before an observed chain or when the estimate expires; that is not proof that the server chain ended. An ordinary reward without a chain number cannot start the timer because it may come from a monster that does not qualify. Zoning and other observation gaps discard old timing. If the optional companion provides a fresh native deadline, that takes precedence and can also show the initial window before chain 1.

## Sessions

The **Session** page separates reported EXP and LP, net progress, EXP lost, recovery, and other adjustments. Recovery is tracked from observed death and revival; a gain that cannot be matched to a reward or recovery remains an adjustment.

**Pause session** stops collecting session rewards, progress, and elapsed time until you resume. Current EXP, LP, and stored merit balances keep updating. **Reset session** is always available at the top of settings. One click saves the previous record and starts a new session. EXP/HR, LP/HR, and Next clear until the new session has enough data. Reset also switches sample previews back to live readings. Your current EXP, LP, stored merits, and layout stay the same. **Copy summary** on Session copies the displayed breakdown to the clipboard.

Pause and reset leave active EXP chain, food, Dedication, and EXP ring recast timers running toward their original end times. They do not restart expired timers. The current chain can advance when another qualifying reward arrives, including while paused; the session's best chain starts over on reset and does not increase while paused. Warnings keep following their timers, subject to **When to mute alerts**. Pausing does not stop an effect from wearing off or a ring from becoming ready in the game. Death, zoning, missing data, and other real observation gaps can still clear or hide a timer when it is no longer reliable.

**Resume this character and job after a reload** is on by default. Reloading restores observed totals and recent samples, excludes offline time, and establishes a fresh progress baseline. It does not reconstruct rewards missed while Momentum was unloaded. Chain timing waits for a newly observed chain reward or an optional fresh server report instead of restoring an old countdown. Zoning and other gaps also clear the comparison baseline.

Under **Current session**, enter a **Current session name** and choose **Rename current session** to name this run. **Save current session** saves your current totals and keeps tracking. **Saved sessions** lists other records separately. Choose one, enter a **Session name**, and use **Rename selected**, or delete it after confirmation. History records the job, date, elapsed session time, EXP/LP totals, net progress, merit points gained, and best EXP chain. **Sessions to keep** is adjustable from 1 to 100 under **Saved session options**. Session preferences are separate from appearance profiles.

Records are saved every 30 seconds and on normal unload in `config/addons/momentum/sessions-<character ID>.json`. An unexpected client crash can lose the last unsaved interval. Corrupt or conflicting history files are preserved and reported instead of silently overwritten. Separate characters use separate files.

## Phoenix status and planning

The **Details** page shows **Level Sync is off** when sync is off. While synced, it shows your actual and synced levels, plus the applied penalty when the server provides it. **Level Sync penalty unknown** means the addon has no fresh exact percentage. Your rate still uses the EXP you actually receive or retain, including any applied penalties.

The optional **Level Sync estimate** section starts closed. Choose a **Level Sync level** and **Estimated players online** to calculate a possible penalty. Phoenix uses actual main-job level minus effective level. A fresh calculation returns zero for a gap of ten or fewer. Above ten, the entire gap is multiplied by the sampled population-tier rate, rounded down, and capped at 50 percent. The tier rates are 0 below 500 sessions, 1.5 from 500, 2 from 1,000, and 2.5 from 2,000.

Phoenix stores the applied penalty on the character. Its population tier and effective level can change without immediately replacing that stored amount. Only a fresh report from the optional server companion establishes the applied penalty. Unknown stays Unknown; the planner does not replace it. This penalty changes the EXP bonus modifier, not necessarily that percentage of the final award.

Server no-EXP notices identify an out-of-range recipient or a sync target that is dead or too far from the defeated monster. A missing reward alone does not establish either cause.

The [optional companion](../server/README.txt) is supplied separately under `server/`, with operator installation instructions. It includes a Lua publisher and a C++ reader for the native chain deadline. The native deadline requires the server to be configured and rebuilt with the C++ module; the Lua status feed can run without that reader. Installing or reloading the client addon does not activate either module, and this repository does not establish that they are deployed. Players can opt in with `!momentumstatus on` only after an operator installs the service, and opt out with `!momentumstatus off`. Momentum never sends those commands itself. The client accepts only valid, current reports for its own character and leaves ordinary chat alone.

## Rings, food, and Dedication

**EXP rings** under Details uses Phoenix's ring definitions and readable inventory data for charges, recast, and the wait after equipping. A finished recast does not guarantee that all equipment or other use requirements are satisfied. The addon never equips or uses an item.

Food and Dedication durations are shown only when the client supplies usable timers. Food names require an observed successful item use followed by the food effect. An effect already active at load can have an unknown source. Dedication's exact remaining bonus EXP requires the optional server companion; its icon alone does not expose that value.

## Alerts

On the **Alerts** page, open the group you want:

- **Food:** food wearing off or ending soon.
- **EXP chains:** the EXP chain timer running low.
- **Dedication:** Dedication wearing off or its bonus EXP running low.
- **EXP rings:** a ring's recast finishing.
- **Levels and merit points:** levels, merit points, goals, and nearly full merit points.
- **Level Sync and missed EXP:** confirmed Level Sync penalty changes and reasons Phoenix gives for missed EXP.

These groups start closed and remember whether you leave them open or closed. Each heading shows how many alerts are on, such as **Food (2 on)**. An alert with both notice and sound counts once. Opening a group does not turn its alerts on. For each alert, check **Show notice**, **Play sound**, or both. Leave both unchecked to turn it off. A sound alert also needs a selected sound file. **Food effect wore off** has only **Play sound**. EXP chain warnings based on the local timer are labeled as estimated.

Each sound alert has its own **Sound** and **Sound volume**. Warning times or amounts appear with the alerts that use them. Alerts other than **Food effect wore off** also have **Time between alerts** and a **Test notification** button to try your choices. Food effect wore off uses **Play** and plays once per confirmed end message. Notices briefly show a small marker and border highlight inside the existing bar. Hover the marker for the notice; your readings and progress rail stay visible. **When to mute alerts** covers paused sessions and events. Simultaneous alerts produce at most one sound per second.

All new events start off. Initial state, reloads, zoning, death, stale reports, and enabling an option do not produce inferred milestone alerts. Chain warnings use the current local countdown or a fresh server timer; changing timing sources does not trigger a warning. Dedication removal follows an authoritative effect-end message; it does not prove that duration expired naturally.

## Food notification

Open **Alerts**, expand **Food**, and check **Play sound** under **Food effect wore off**. This is off by default. Choose a sound from the list, set the volume, and use **Play** to try it. The Play button works while the alert is off. **Food effect ending soon** is a separate alert in the same group, based on the time left on your food effect.

The archive includes **FF VII Save.mp3** and **FF IX Moogle.mp3**. To use your own sound, put an `.mp3` or `.wav` file in `config/addons/momentum/sounds/` and click **Refresh**, then select it for the alert. A bundled sound takes priority over a custom file with the same name. The bundled Square Enix sound assets are not covered by the addon's GPL license.

The notification plays once after the server reports that your active food ended. Food removal with a status message can also trigger it, so it does not prove the food expired naturally. Ordinary death, loading, zoning, turning the option on, and simply losing an icon stay quiet. A missed or stale message does not produce a delayed alert.

Sound playback stays local. A file that cannot open or play leaves a message in settings; it does not stop EXP tracking. Pick a different file or press Play to retry.

## Appearance and previews

Choose Phoenix, Classic FFXI, Minimal, High contrast, Ember, Mint, Lavender, or Colorblind safe. Changing a skin preserves your readout order, labels, and placement. Fonts use the client's default face or installed Windows fonts. If a selected Windows font is unavailable, the client font is used.

Phoenix uses burgundy panels, warm white text, and red accents. Bar colors and window colors can be changed separately. The skin reads Custom after you edit its colors; choosing the skin again restores its palette. Existing untouched skin colors update automatically, while custom colors stay as you set them.

Text sizes for the bar and settings window are separate. Background opacity, colors, border, corners, shadow, fill direction, and text/fill visibility can be changed independently. **Progress style** chooses **Thin line** or **Full background**. Bar text scales down when the bar is too short to fit it. Job pictures use artifact head item pictures from your installed game client; the addon does not distribute job artwork.

The fixed preview has **Live** and **Sample** choices. Sample changes only the settings preview, with leveling, merits, capped, paused, and unknown states available. The expandable preview options include a narrow-width test. **Show sample on game bar** is a separate choice that replaces the visible game-bar numbers with a marked sample while live tracking continues in the background. Turn it off to return the game bar to your character.

## Profiles and saving

Changes save after the active edit finishes. **Undo** restores up to eight previous edits during the current addon run. Section and layout resets are available in settings.

Save a profile to keep the bar layout, tracking choices, and appearance. Profiles keep all readout positions, labels, dividers, and colors. A profile does not contain session totals, character progress, the open settings page, or preview mode.

**Job profiles** applies a saved profile when the main job changes. **Use one layout for all characters** uses a common appearance file; job profiles are inactive while sharing is enabled. Session records stay separate. Turning sharing off copies the current shared appearance to the active character's own settings.

All persistent files are under `config/addons/momentum/`:

- Ashita manages the character's settings files.
- `profiles.json` holds named profiles.
- `shared_layout.json` holds the shared layout and whether sharing is enabled.
- `sessions-<character ID>.json` holds that character's session records.
- `sounds/` holds your own sound files.

Corrupt profile or shared-layout files are left unchanged and an error is shown in chat. Session files also detect conflicting writes instead of silently replacing another client's changes. Back up the folder before editing these files by hand, and unload Momentum in every client that uses them first.

## Commands

| Command | Action |
| --- | --- |
| `/momentum` | Open or close settings. |
| `/momentum show` / `/momentum hide` | Show or hide the bar. |
| `/momentum lock` / `/momentum unlock` | Lock or unlock movement and resizing. |
| `/momentum dock top` / `/momentum dock bottom` | Attach above or below chat. Plain `dock` keeps the last selected edge. |
| `/momentum free` | Unlock movement and resizing, keep the current rectangle, and turn off anchoring and snapping. |
| `/momentum dockinfo` | Show detected chat bounds for troubleshooting. |
| `/momentum pause` / `/momentum resume` | Pause or resume session collection. |
| `/momentum reset` | Save the previous session and start a new one. |
| `/momentum undo` | Undo the last saved layout edit. |
| `/momentum preview` | Toggle sample numbers on the movable bar. |
| `/momentum mode auto` / `exp` / `lp` | Choose the progress display. |
| `/momentum divider " / "` | Set custom divider text. |
| `/momentum order rate progress remaining` | Move the listed readouts to the front in that order. |
| `/momentum profile save My Layout` | Save a named profile. |
| `/momentum profile load My Layout` | Load a named profile. |
| `/momentum profile delete My Layout` | Delete a named profile. |

Common order IDs include `job`, `progress`, `remaining`, `rate`, `eta`, `chain`, `chain_time`, `last`, `percent`, `merits`, `merit_rate`, `goal`, `buffer`, `session`, `net`, `elapsed`, `average`, `best_chain`, `dedication`, and `status`. Use the Display list to arrange every available readout without typing IDs.
