# Native chat attachment

When drawing the bar or settings, the dock reads the two native chat-window pointers and uses the main chat window's rectangle. The second active window remains an exclusion area when it overlaps the bar horizontally. `bar.anchor` selects top or bottom; `bar.start` moves the left end in pixels while the right end remains aligned. At least 120 pixels of width remain where possible. The selected edge leaves a minimum two-pixel gap and reduces height to fit if at least twelve pixels remain. It never switches sides automatically. With Hide with chat, missing bounds hide the dock. Insufficient space around readable chat hides it in every mode.

Choosing Free placement preserves the visible rectangle, disables automatic width and snapping, releases the anchor, and unlocks movement and resizing. Shift dragging an attached bar also preserves its rectangle but keeps the snap preference. Snapping tests both chat edges and selects the nearest valid dock within eighteen pixels.

The reader never writes game memory or changes chat settings. Reads use current-process ReadProcessMemory copies so an unavailable address returns a failed read. A failed snapshot clears saved native chat geometry; the renderer can still keep its last drawn bar rectangle. The signature is scanned at load; the table and window pointers are read again for each snapshot.

`visibility.mode` has three choices. `chat` hides the HUD when the main chat window is confirmed inactive, even in free placement. `keep` keeps it up when chat closes while respecting the other hide settings. `always` also bypasses typing, idle, map, event, and game-UI hiding. Manual hiding and sample previews keep their existing behavior. All policies run after tracking, alerts, and timer updates, and hiding with chat leaves settings accessible.

New and reset settings use `keep`. Missing or invalid modes also use `keep`. Only the exact legacy `placement` value becomes `chat` when the saved bar is docked, or `keep` when it is free. An explicit `chat`, `keep`, or `always` value is preserved. After migration, changing placement does not change the selected visibility mode.

The reader returns current geometry, its reason, a main-window visibility value (`true`, `false`, or unknown `nil`), and optional retained geometry. Retained geometry is built only when `read(width, height, true)` requests it for an attached `keep` or `always` bar. Calls without that request still validate and invalidate the saved native bounds, so changing the option while chat is closed can reuse a valid anchor. Retained geometry requires a confirmed inactive main window with matching native identity and menu/window dimensions. It uses the last validated main rectangle and the current second window for collision avoidance; display-size changes reproject the native bounds. Read failures, invalid or replaced native state, load, zone changes, and character settings changes clear it without adding scans. Unknown visibility never becomes a confirmed close.

For `keep` and `always`, the renderer keeps the actual last drawn on-screen bar rectangle when chat closes or native bounds become unknown. This is separate from saved native chat geometry and does not depend on a confirmed inactive flag. The bar keeps its position and size; a smaller viewport clamps only what is needed to keep it on screen. Saved free placement is used only before a drawn rectangle is available. Load, zone, and character changes clear that rectangle, so it cannot carry a stale position into another context.

A returning chat window restores the current anchor using its current bounds. The reader's fifth return value supplies validated current window bounds even when the main chat pointer is missing. A readable second window can therefore hide an overlapping held bar without moving it. Insufficient space around live chat still hides the dock rather than covering either chat window. The new visibility modes add no native reads beyond the existing chat snapshot.

Shift dragging or resizing a held rectangle detaches the bar before applying the edit. Returning chat does not discard that intentional free-placement edit. A visibility or attachment change during a held resize stops the gesture at the last valid size; the player can release and start a new drag.

## Sources and limits

- [Window structure](https://github.com/Windower/packages/blob/fa326785d1fd58488e1507d9949b4baac82ffa91/libraries/memory/types.lua#L333-L349): unsigned 16-bit fields at offsets 0x40, 0x42, 0x44 and 0x46; active byte at 0x4D. Its width/height names for the last two fields are misleading for this client; read them as right/bottom endpoints.
- [Pointer table](https://github.com/Windower/packages/blob/fa326785d1fd58488e1507d9949b4baac82ffa91/libraries/memory/types.lua#L476-L479): signature 85C0753B8B15 and two window pointers.
- [Signature resolution](https://github.com/Windower/Fenestra/blob/e5bfb6442f49bdb4d31859bff6218bbeb1bea620/core/src/scanner.cpp#L123-L125): the default signature action resolves the address operand after the matched bytes.
- [Native UI scaling](https://github.com/AshitaXI/Ashita-v4beta/blob/4171c74c8ddb2ca2a31654f199e6c1cee40d7256/addons/libs/scaling.lua#L49-L72): CYmdb exposes render/window and menu resolutions; native menu coordinates scale by their ratio.

## Fixture provenance

The native-reader regression includes user-supplied client diagnostics with left 16, top 821, right 1086, and bottom 1044 at a menu, window, and display size of 1920 by 1080. These endpoints describe a 1070 by 223 rectangle. Treating the last two fields as dimensions would produce invalid bounds. The values are test inputs, never placement constants.

Mapping native edges through menu resolution into ImGui DisplaySize follows the scaling convention above. Offline coverage must check that projection, both anchors, border separation, second-window exclusion, resizing, and missing bounds. Stay-put checks must include both confirmed inactive chat and unknown bounds after a failed read, plus reopening, smaller viewports, and zone or character resets. A cropped chat screenshot cannot establish the full client size or chat width, so no screenshot-derived offsets are used.

The supplied diagnostics establish that the pointer chain reached readable chat data on that client. Offline fixtures do not establish live on-screen alignment. Unequal menu/display scaling and the active flag's visibility behavior still need live-client confirmation. `/momentum dockinfo` reports left, top, right, bottom, and resolution values for that check.
