Momentum real UI preview
========================

This runs the addon's own Lua with Dear ImGui 1.92.3 in a hidden OpenGL window. It uses
Ashita's imgui.lua over a bridge, including the client's constants and font. The
bridge rejects unsupported calls and argument shapes; unbalanced stacks fail.
It is an offline render, not a screenshot of the running game.

Use Python 3.12 and install tests/requirements.txt from the project folder. The
preview reads Ashita's libraries and Ashita.dll from the installation selected by
ASHITA_LIBS (default C:/Games/PhoenixXI/addons/libs). It does not need the game open.

Run all cases:

  python tests/preview/verify_preview.py

Run selected registered cases by name:

  python tests/preview/verify_preview.py escape-config-combat settings-auto-layout

Run individual cases:

  python tests/preview/preview.py --hud --out tests/out/bar.png
  python tests/preview/preview.py --tab Display --out tests/out/display.png
  python tests/preview/preview.py --scene Merits --hud --out tests/out/merits.png
  python tests/preview/preview.py --full --out tests/out/entry.png
  python tests/preview/preview.py --set bar.docked=false --set bar.auto_width=false --set bar.width=240 --hud --out tests/out/narrow.png

--size W H sets the simulated client size. --window-size W H resizes settings.
MOCK.chat supplies an already projected native-chat rectangle. The default fixture
is x=12, y=520, width=900, height=344. Both direct and --full rendering use it; --full
runs the entry callbacks with a mocked core.chat reader. The native adapter has
separate tests. No process memory is read by the renderer.
--set key.path=value changes a setting. --exec LUA executes setup code with settings
in scope. --window NAME chooses a window to crop. --no-crop saves the whole client.
--font PATH selects a font. --font-size PX sets the client default font size.
--icon-fixture substitutes a grey crossed test texture for the job picture, testing
the real image draw call, level placement, and text fit. It is not game artwork.
--chat-fixture draws labeled simulated chat rectangles. Use --no-crop to include them.
--exec 'MOCK.chat=nil' checks missing native bounds; it does not disable docking.

--input-script FILE replays a JSON list of input events. Each entry selects a frame
and can set mouse:[x,y], delta:[dx,dy], down:true/false, shift:true/false, escape:true/false, target:"widget label", or
lua:"assert(...)". Target uses rectangles recorded from the actual rendered controls;
it never forces the widget's return value. A target can add point:[x,y] with fractions
from 0 to 1 to choose an edge instead of its center. Assertions run before the selected frame.
order_input.json and drag_input.json cover movement and docking interactions.
alignment_input.json compares actual HUD text/image draw-list rectangles before and
after right alignment. Fixed, docked, picture, and narrow-overflow cases check group
translation, unchanged readout order, and nine-pixel padding. alignment_control_input.json
selects Right through the real Readout alignment dropdown. These checks exclude inline
settings previews so they cannot mask HUD geometry errors.
palette_input.json checks all eight skins against fixed role-color fixtures. It checks
the actual settings-window ImGui colors plus HUD draw-list backgrounds, EXP/LP fills,
values and labels, and confirms that choosing a skin keeps the readout order.
fit_input.json checks the text actually sent to the draw list at the default width.
startup_input.json checks immediate native-chat docking without settings or setup prompts.
native_chat_input.json checks rendered starting-point/right-edge alignment, border
separation, secondary-window avoidance, and short-strip height on the chosen side.
Both top and bottom placements are checked. A blocked side stays hidden even when
the opposite side has space. Large starting points leave at least 120 pixels.
chat_resize_input.json changes native bounds between frames and checks all three edges.
diagnostic_chat_input.json loads the actual core/chat.lua projection directly, bypassing
the mocked reader. It supplies the user-reported native endpoints (16,821)-(1086,1044)
at 1920x1080, checks the resulting 1070x223 rectangle, then verifies both top and bottom
bar positions. The pictured chat is labeled as reported bounds rendered in simulation;
it is not a live capture and does not perform native memory reads.
free_input.json checks that missing chat bounds do not change free placement.
placement_input.json clicks the real Placement dropdown to choose Above chat and Below chat.
start_input.json clicks the Starting point slider and checks the actual drawn edges.
height_control_input.json clicks Bar height in free, top, and bottom placement. It
checks the rendered height, fixed chat-facing edge, and available screen space.
free_placement_input.json chooses Free placement, checks that the visible rectangle
is preserved, then drags and resizes both edges. Dropping near chat stays free while
snapping is off. Widget clicks use recorded rectangles, including combo and slider
controls; no widget return values are forced.
Repeated controls inside PushID scopes also have scoped targets, such as
level/Show notice and food_end/Play sound. Existing unscoped targets still work.
Section headers also have stable targets such as ##section_Alerts/Food, so changing
the enabled count or shortening the visible title does not change the replay target.
alerts_fixture.lua and the alert, food, and alert-search input scripts check independent
notice/sound checkboxes, saved folds, search restoration, and explicit test clicks.
The count cases check mixed enabled groups, and checkbox replays verify that notice
and sound for one alert count once, including sound-only food wear-off.
The notification and food Play services are recorded mocks; these replays play no audio.
escape_config_fixture.lua and escape_config_input.json run the whole addon in a
simulated combat state. They close settings with a real Escape input while a combo,
text field, or readout catalog is active, then reopen to check saved edits and
cleared popup focus. They do not change the game's combat state or inject gameplay
commands. Separate Lua suites cover hidden-state gates and pending confirmations.
width_input.json checks width resizing from free and attached positions.
The constrained-width case starts with a saved height of 24 and a visible height of 14;
horizontal resizing must keep the visible height. width_return_input.json moves the
right edge away and back to the exact mouse origin, checking that its size is restored.
resize_input.json and top_resize_input.json check the outer height edge on each side of chat while the
chat-facing edge and width stay fixed. top_snap_input.json checks that a body drag
preserves the drawn width and can snap to the top edge. overflow_input.json checks the visible
overflow marker at a deliberately narrow custom width.

Each invocation uses its own temporary settings and ImGui ini folder. It reads the
addon but does not modify it. The Agave font is extracted from the installed Ashita.dll
into the ignored fonts/ folder. No font assets ship in the addon archive.

Limitations: OpenGL rasterization can differ slightly from the game's Direct3D path.
Client state is simulated. The live resource manager's job pictures are unavailable,
so ordinary renders show the job abbreviation fallback. These previews do not prove
live input, Direct3D texture loading, or packet behavior.
