# Native chat attachment

When drawing the bar or settings, the dock reads the two native chat-window pointers and uses the main chat window's rectangle. The second active window remains an exclusion area when it overlaps the bar horizontally. `bar.anchor` selects top or bottom; `bar.start` moves the left end in pixels while the right end remains aligned. At least 120 pixels of width remain where possible. The selected edge leaves a minimum two-pixel gap and reduces height to fit if at least twelve pixels remain. It never switches sides automatically. Missing bounds or insufficient space hide the dock; free placement remains available.

Choosing Free placement preserves the visible rectangle, disables automatic width and snapping, releases the anchor, and unlocks movement and resizing. Shift dragging an attached bar also preserves its rectangle but keeps the snap preference. Snapping tests both chat edges and selects the nearest valid dock within eighteen pixels.

The reader never writes game memory or changes chat settings. Reads use current-process ReadProcessMemory copies so an unavailable address returns a failed read. No rectangle is retained after a failed snapshot. The signature is scanned at load; the table and window pointers are read again for each snapshot.

## Sources and limits

- [Window structure](https://github.com/Windower/packages/blob/fa326785d1fd58488e1507d9949b4baac82ffa91/libraries/memory/types.lua#L333-L349): unsigned 16-bit fields at offsets 0x40, 0x42, 0x44 and 0x46; active byte at 0x4D. Its width/height names for the last two fields are misleading for this client; read them as right/bottom endpoints.
- [Pointer table](https://github.com/Windower/packages/blob/fa326785d1fd58488e1507d9949b4baac82ffa91/libraries/memory/types.lua#L476-L479): signature 85C0753B8B15 and two window pointers.
- [Signature resolution](https://github.com/Windower/Fenestra/blob/e5bfb6442f49bdb4d31859bff6218bbeb1bea620/core/src/scanner.cpp#L123-L125): the default signature action resolves the address operand after the matched bytes.
- [Native UI scaling](https://github.com/AshitaXI/Ashita-v4beta/blob/4171c74c8ddb2ca2a31654f199e6c1cee40d7256/addons/libs/scaling.lua#L49-L72): CYmdb exposes render/window and menu resolutions; native menu coordinates scale by their ratio.

## Fixture provenance

The native-reader regression includes user-supplied client diagnostics with left 16, top 821, right 1086, and bottom 1044 at a menu, window, and display size of 1920 by 1080. These endpoints describe a 1070 by 223 rectangle. Treating the last two fields as dimensions would produce invalid bounds. The values are test inputs, never placement constants.

Mapping native edges through menu resolution into ImGui DisplaySize follows the scaling convention above. Offline tests check that projection, both anchors, border separation, second-window exclusion, resizing, and missing bounds. A cropped chat screenshot cannot establish the full client size or chat width, so no screenshot-derived offsets are used.

The supplied diagnostics establish that the pointer chain reached readable chat data on that client. Offline fixtures do not establish live on-screen alignment. Unequal menu/display scaling and the active flag's visibility behavior still need live-client confirmation. `/momentum dockinfo` reports left, top, right, bottom, and resolution values for that check.
