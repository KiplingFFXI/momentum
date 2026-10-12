local defaults = require('ui.defaults');
local layout = require('ui.layout');
local checks = 0;
local function equal(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end

local bar = defaults.make().bar;
local chat = { x = 12, y = 520, width = 900, height = 344 };
local rect = layout.rect(bar, 1600, 900, chat, 384.2);
equal(rect.width, 900, 'Dock spans the native chat width');
equal(rect.height, 18, 'Default bar keeps its height when space permits');
equal(rect.x, 12, 'Dock starts at the native chat left edge');
equal(rect.y, 866, 'Dock clears the native bottom border by two pixels');
equal(rect.anchor, 'bottom', 'Bottom is the default anchor');
equal(rect.hidden, nil, 'Valid native geometry shows the dock');
equal(bar.width, 640, 'Dock does not overwrite the saved free width');
equal(bar.x, 0, 'Dock does not overwrite saved free position');
equal(bar.auto_width, true, 'Dock preserves automatic free sizing');
equal(layout.chat_rect, nil, 'No manual chat geometry remains');
equal(layout.rect(bar, 1600, 900, chat, 1300).width, 900, 'Long content cannot extend beyond native chat');
equal(layout.rect(bar, 1600, 900, chat, 10).width, 900, 'Short content does not shorten the dock');
bar.auto_width, bar.width = false, 500;
equal(layout.rect(bar, 1600, 900, chat).width, 900, 'Manual free width does not alter the dock');
bar = defaults.make().bar;
for _, missing in ipairs({ false, {}, { x = 1, y = 2, width = 0, height = 40 },
    { x = 1, y = 2, width = 40, height = -1 }, { x = 0 / 0, y = 2, width = 40, height = 40 },
    { x = 1, y = math.huge, width = 40, height = 40 }, { x = 1600, y = 2, width = 40, height = 40 },
    { x = 1, y = 900, width = 40, height = 40 } }) do
    equal(layout.rect(bar, 1600, 900, missing).hidden, true, 'Missing or unusable chat geometry hides the dock');
end
equal(layout.rect(bar, 1600, 900).hidden, true, 'No screen-edge fallback without native geometry');
equal(type(layout.rect(bar, 1600, 900).reason), 'string', 'Hidden dock gives an explanation');

local fractional = { x = 12.2, y = 520.3, width = 900.6, height = 343.9 };
rect = layout.rect(bar, 1600, 900, fractional);
equal(rect.x, 13, 'Fractional left edge rounds inward');
equal(rect.width, 899, 'Fractional right edge rounds inward');
equal(rect.y, 867, 'Fractional bottom edge rounds outward before adding clearance');
rect = layout.rect(bar, 800, 600, { x = -20, y = 400, width = 900, height = 170 });
equal(rect.x, 0, 'Partly offscreen chat clips at the left viewport edge');
equal(rect.width, 800, 'Partly offscreen chat clips at the right viewport edge');
equal(rect.y, 572, 'Clipping width does not shift the vertical dock');

for _, available in ipairs({ 18, 14, 12 }) do
    rect = layout.rect(bar, 800, 600, { x = 13, y = 200, width = 700, height = 398 - available });
    equal(rect.height, available, 'Dock fits the available lower strip down to twelve pixels');
    equal(rect.y + rect.height, 600, 'Reduced dock fits wholly inside the viewport');
end
rect = layout.rect(bar, 800, 600, { x = 13, y = 200, width = 700, height = 387 });
equal(rect.hidden, true, 'Eleven lower pixels hide the bottom anchor without switching sides');
equal(rect.reason:find('Above chat or Free', 1, true) ~= nil, true, 'Bottom shortage names available placement controls');
bar.anchor = 'top';
rect = layout.rect(bar, 800, 600, { x = 13, y = 200, width = 700, height = 387 });
equal(rect.y, 180, 'Top anchor clears the native top edge');
equal(rect.height, 18, 'Top anchor retains requested height when space permits');
equal(rect.anchor, 'top', 'Top anchor is reported to the renderer');
rect = layout.rect(bar, 800, 600, { x = 13, y = 20, width = 700, height = 580 });
equal(rect.y, 0, 'Exact upper fit respects the top viewport boundary');
equal(rect.height, 18, 'Exact upper fit retains height');
for _, available in ipairs({ 17, 14, 12 }) do
    rect = layout.rect(bar, 800, 600, { x = 13, y = available + 2, width = 700, height = 300 });
    equal(rect.height, available, 'Top anchor fits the available strip down to twelve pixels');
    equal(rect.y, 0, 'Reduced top anchor fits wholly inside the viewport');
end
rect = layout.rect(bar, 800, 600, { x = 13, y = 13, width = 700, height = 300 });
equal(rect.hidden, true, 'Eleven upper pixels hide the top anchor despite space below');
equal(rect.reason:find('Below chat or Free', 1, true) ~= nil, true, 'Top shortage names available placement controls');
equal(layout.rect(bar, 800, 600, { x = 13, y = 0, width = 700, height = 600 }).hidden, true,
    'Full-height chat cannot be overlaid by the dock');
bar.anchor = 'bottom';
bar.bottom = 20;
equal(layout.rect(bar, 1600, 900, chat).y, 884, 'Custom gap is measured from native chat');
equal(layout.rect(bar, 1600, 900, chat).height, 16, 'Custom gap still keeps the dock in bounds');
bar.bottom = 0;
equal(layout.rect(bar, 1600, 900, chat).y, 866, 'Saved zero gap cannot overlap the chat border');
bar.bottom = 1;

local split = { x = 12, y = 520, width = 900, height = 344,
    windows = { { x = 12, y = 870, width = 900, height = 30 } } };
rect = layout.rect(bar, 1600, 900, split);
equal(rect.hidden, true, 'Second chat below hides an obstructed bottom anchor');
bar.anchor = 'top';
rect = layout.rect(bar, 1600, 900, split);
equal(rect.y, 500, 'Top anchor stays above both overlapping windows');
equal(rect.width, 900, 'Second window does not expand primary docking width');
split.windows = { { x = 300, y = 490, width = 400, height = 410 } };
equal(layout.rect(bar, 1600, 900, split).y, 470, 'Partly overlapping second window contributes its whole vertical span');
bar.anchor = 'bottom';
split.windows = { { x = 912, y = 0, width = 688, height = 900 } };
equal(layout.rect(bar, 1600, 900, split).y, 866, 'Touching horizontal edges do not collide');
split.windows[1].x = 911;
equal(layout.rect(bar, 1600, 900, split).hidden, true, 'One pixel of horizontal overlap protects the second chat');
split.windows = { { x = 0, y = 0, width = -1, height = 900 }, { x = 1700, y = 0, width = 10, height = 900 } };
equal(layout.rect(bar, 1600, 900, split).y, 866, 'Invalid and offscreen secondary bounds are ignored');

bar.start = 200;
rect = layout.rect(bar, 1600, 900, chat);
equal(rect.x, 212, 'Starting point offsets the left edge along chat');
equal(rect.width, 700, 'Starting point retains the native right edge');
equal(rect.x + rect.width, 912, 'Offset never shifts the native right edge');
bar.start = 1000;
rect = layout.rect(bar, 1600, 900, chat);
equal(rect.x, 792, 'Large starting point clamps before the minimum width');
equal(rect.width, 120, 'Starting point keeps at least one hundred twenty pixels');
equal(bar.start, 1000, 'Clamping does not overwrite saved starting point');
rect = layout.rect(bar, 1600, 900, { x = 12, y = 520, width = 90, height = 344 });
equal(rect.x, 12, 'Chat narrower than the minimum keeps its left edge');
equal(rect.width, 90, 'Narrow chat remains fully contained');
bar.start = -50;
equal(layout.rect(bar, 1600, 900, chat).x, 12, 'Negative starting point clamps to chat left');
bar.start = 0 / 0;
equal(layout.rect(bar, 1600, 900, chat).x, 12, 'Invalid starting point falls back to chat left');
bar.start = 200;
split.windows = { { x = 12, y = 0, width = 200, height = 900 } };
equal(layout.rect(bar, 1600, 900, split).y, 866, 'Offset dock ignores secondary chat ending at its new left edge');
split.windows[1].width = 201;
equal(layout.rect(bar, 1600, 900, split).hidden, true, 'Offset dock protects a secondary window overlapping by one pixel');
bar.anchor = 'top';
split.windows[1].width = 200;
equal(layout.rect(bar, 1600, 900, split).y, 500, 'Top collision checks use the same offset span');
bar.start, bar.anchor = 0, 'bottom';

local resized_chat = { x = 6, y = 250, width = 450, height = 332 };
rect = layout.rect(bar, 800, 600, resized_chat, 385);
equal(rect.x, 6, 'New native coordinates follow client resizing');
equal(rect.width, 450, 'New native width follows client resizing');
equal(rect.y, 584, 'New native bottom follows client resizing');
equal(rect.height, 16, 'Resized client can shorten the lower dock');

layout.move(bar, 999, -50, 800, 600, false, 385);
equal(bar.docked, false, 'Dragging releases the dock');
equal(bar.x, 415, 'Drag clamps using the rendered width');
equal(bar.y, 0, 'Drag clamps top edge');
equal(bar.width, 640, 'Dragging does not overwrite the maximum width');
equal(bar.auto_width, true, 'Dragging keeps automatic sizing');
rect = layout.rect(bar, 2400, 1800, nil, 385);
equal(rect.width, 385, 'Free bar remains content-sized');
equal(rect.x, 415, 'Free bar keeps horizontal placement');
equal(rect.hidden, nil, 'Free placement stays available without native geometry');
equal(layout.rect(bar, 1920, 1080, chat, 384.2).width, 385, 'Free content width rounds up without clipping');
equal(layout.rect(bar, 1920, 1080, chat, 900).width, 640, 'Free automatic width respects maximum');
equal(layout.rect(bar, 320, 240, chat, 385).width, 320, 'Small client bounds free automatic width');
equal(layout.rect(bar, 1920, 1080).width, 640, 'Unmeasured free fallback remains compact');
equal(layout.rect(bar, 1920, 1080, nil, math.huge).width, 640, 'Infinite free measurement uses bounded fallback');
equal(layout.rect(bar, 1920, 1080, nil, 0 / 0).width, 640, 'NaN free measurement uses bounded fallback');
equal(layout.rect(bar, 1920, 1080, nil, 0).width, 1, 'Empty free content keeps positive geometry');

local snap_chat = { x = 100, y = 200, width = 400, height = 340 };
layout.move(bar, 150, 560, 800, 600, true, 385, snap_chat);
equal(bar.docked, true, 'Release eighteen pixels from native dock snaps');
equal(layout.rect(bar, 800, 600, snap_chat).x, 100, 'Snapped dock uses native left edge');
equal(layout.rect(bar, 800, 600, snap_chat).y, 542, 'Snapped dock clears native bottom edge');
equal(bar.x, 150, 'Snapping preserves the last free position');
equal(bar.anchor, 'bottom', 'Bottom snap records the selected edge');
layout.move(bar, 150, 162, 800, 600, true, 385, snap_chat);
equal(bar.docked, true, 'Release eighteen pixels from top dock snaps');
equal(bar.anchor, 'top', 'Top snap updates the anchor preference');
equal(layout.rect(bar, 800, 600, snap_chat).y, 180, 'Top snap uses the actual native edge');
layout.move(bar, 150, 161, 800, 600, true, 385, snap_chat);
equal(bar.docked, false, 'Release nineteen pixels from top dock stays free');
layout.move(bar, 150, 561, 800, 600, true, 385, snap_chat);
equal(bar.docked, false, 'Release nineteen pixels from native dock stays free');
layout.move(bar, 0, 582, 800, 600, true, 385, snap_chat);
equal(bar.docked, false, 'Client bottom is not an unrelated snap target');
bar.auto_width, bar.width = false, 200;
layout.move(bar, 500, 542, 800, 600, true, 200, snap_chat);
equal(bar.docked, false, 'Touching native horizontal edge does not snap');
layout.move(bar, 499, 542, 800, 600, true, 200, snap_chat);
equal(bar.docked, true, 'Horizontal overlap permits native snap');
layout.move(bar, 150, 542, 800, 600, false, 200, snap_chat);
equal(bar.docked, false, 'Drag motion alone does not snap');
layout.move(bar, 150, 542, 800, 600, true, 200);
equal(bar.docked, false, 'Missing native geometry never causes a snap');
bar.start = 150;
layout.move(bar, 150, 542, 800, 600, true, 200, snap_chat);
equal(bar.docked, true, 'Offset dock can still be reached from a free position');
equal(bar.start, 150, 'Snapping preserves the chosen starting point');
equal(layout.rect(bar, 800, 600, snap_chat).x, 250, 'Snapping uses the chosen starting point');
layout.move(bar, 0, 542, 800, 600, true, 200, snap_chat);
equal(bar.docked, false, 'No snap when a free bar misses the offset dock span');
bar.start = 0;

local thin_chat = { x = 100, y = 300, width = 400, height = 1 };
bar.anchor = 'top';
layout.move(bar, 150, 293, 800, 600, true, 200, thin_chat);
equal(bar.anchor, 'bottom', 'Nearest bottom candidate wins over a previous top preference');
layout.move(bar, 150, 290, 800, 600, true, 200, thin_chat);
equal(bar.anchor, 'top', 'Nearest top candidate wins over a previous bottom preference');
thin_chat.height = 2;
bar.anchor = 'bottom';
layout.move(bar, 150, 292, 800, 600, true, 200, thin_chat);
equal(bar.anchor, 'bottom', 'Equal snap distances preserve bottom preference');
bar.anchor = 'top';
layout.move(bar, 150, 292, 800, 600, true, 200, thin_chat);
equal(bar.anchor, 'top', 'Equal snap distances preserve top preference');
bar.snap = false;
layout.move(bar, 150, 542, 800, 600, true, 200, snap_chat);
equal(bar.docked, false, 'Snap toggle is respected');
bar.y = 582;
layout.resize(bar, 500, 28, 800, 600);
equal(bar.auto_width, false, 'Width resize switches to a fixed width');
equal(bar.width, 500, 'Width resize retains its requested size');
equal(layout.rect(bar, 800, 600, nil, 300).width, 500, 'Manual width ignores text measurement');
equal(bar.y, 572, 'Resize keeps a free bar on screen');
layout.resize(bar, 1600, 500, 800, 600);
equal(bar.width, 800, 'Resize clamps width to client');
equal(bar.height, 120, 'Resize caps height');
equal(bar.x, 0, 'Wide resized bar remains on screen');
bar = defaults.make().bar;
bar.docked, bar.x, bar.y = false, 900, 800;
rect = layout.rect(bar, 800, 600, nil, 385);
equal(rect.x, 415, 'Resolution shrink clamps free horizontal position');
equal(rect.y, 582, 'Resolution shrink clamps free vertical position');
rect = layout.rect(bar, 30, 8, nil, 385);
equal(rect.width, 30, 'Tiny clients bound content width');
equal(rect.height, 8, 'Tiny clients bound height');
equal(rect.x, 0, 'Tiny clients keep x on screen');
equal(rect.y, 0, 'Tiny clients keep y on screen');
bar = defaults.make().bar;
bar.docked, bar.x, bar.y = false, 123, 234;
rect = layout.rect(bar, 1920, 1080, { x = 100, y = 0, width = 1800, height = 1080 }, 385);
equal(rect.width, 385, 'Native chat cannot stretch a free bar');
equal(rect.x, 123, 'Native chat cannot move a free bar horizontally');
equal(rect.y, 234, 'Native chat cannot move a free bar vertically');
equal(rect.hidden, nil, 'Native chat cannot hide a free bar');

bar = defaults.make().bar;
bar.anchor, bar.start, bar.snap = 'top', 230, true;
rect = layout.rect(bar, 1600, 900, { x = 12, y = 16, width = 900, height = 500 });
equal(rect.height, 14, 'Detach fixture uses a shortened top dock');
equal(layout.detach(bar, rect), true, 'Visible dock detaches successfully');
equal(bar.docked, false, 'Detach releases the anchor');
equal(bar.auto_width, false, 'Detach freezes the displayed width');
equal(bar.x, 242, 'Detach retains displayed horizontal position');
equal(bar.y, 0, 'Detach retains displayed vertical position');
equal(bar.width, 670, 'Detach retains displayed offset width');
equal(bar.height, 14, 'Detach retains shortened displayed height');
equal(bar.anchor, 'top', 'Detach retains the selected anchor for a later return');
equal(bar.start, 230, 'Detach retains the selected starting point');
equal(bar.snap, true, 'Detach leaves snap choice to the caller');
local detached = layout.rect(bar, 1600, 900, nil, 300);
equal(detached.width, rect.width, 'Detached bar keeps its visible width regardless of content');
equal(detached.height, rect.height, 'Detached bar keeps its visible height');
equal(layout.detach(bar, { hidden = true }), false, 'Unavailable dock cannot overwrite free geometry');
equal(layout.detach(bar, { x = 1, y = 2, width = -3, height = 4 }), false, 'Invalid rectangle cannot overwrite free geometry');
equal(bar.width, 670, 'Failed detach preserves the saved geometry');

local order = { 'a', 'b', 'c' };
equal(layout.reorder(order, 1, 3), true, 'Move to end succeeds');
equal(table.concat(order), 'bca', 'Move to end preserves others');
equal(layout.reorder(order, 3, 1), true, 'Move to start succeeds');
equal(table.concat(order), 'abc', 'Move to start preserves others');
equal(layout.reorder(order, 1, 0), false, 'Moving beyond start is ignored');
equal(layout.reorder(order, 3, 4), false, 'Moving beyond end is ignored');
equal(layout.reorder(order, 2, 2), false, 'Moving to same place is ignored');

local segments = layout.segments({ { id = 'a', label = '', value = 'ONE' }, { id = 'b', label = '', value = 'TWO' } },
    { divider = '|', label_divider = ':', spacing = 0, dividers = {} });
equal(#segments, 3, 'One divider between visible readouts');
equal(segments[1].text, 'ONE', 'No leading divider');
equal(segments[2].text, '|', 'Divider is configurable');
local fitted, overflow = layout.fit(segments, 7, string.len);
equal(overflow, false, 'Exact fit is retained');
equal(#fitted, 3, 'Exact fit retains all segments');
fitted, overflow = layout.fit(segments, 6, string.len);
equal(overflow, true, 'Overflow is explicit');
equal(fitted[#fitted].text, '...', 'Overflow marker is shown');
equal(#fitted, 2, 'Dangling divider is removed');

local icon_segments = {
    { text = '61', role = 'text', icon = 123, icon_width = 16, icon_gap = 4 },
    { text = '|', role = 'divider', gap = 2 },
    { text = 'EXP', role = 'text' },
};
fitted, overflow = layout.fit(icon_segments, 28, string.len);
equal(overflow, false, 'Exact fit counts icon, icon gap, and divider gap');
equal(#fitted, 3, 'Exact icon fit keeps every segment');
fitted, overflow = layout.fit(icon_segments, 27, string.len);
equal(overflow, true, 'One pixel short with icon shows overflow');
equal(#fitted, 2, 'Overflow removes a trailing divider after the icon');
equal(fitted[1].icon, 123, 'A fitting job icon stays attached to its level');
equal(fitted[2].text, '...', 'Remaining readouts are represented by the marker');
fitted, overflow = layout.fit(icon_segments, 24, string.len);
equal(overflow, true, 'Overflow marker reserves its own width');
equal(#fitted, 1, 'An icon and level that cannot fit are omitted together');
equal(fitted[1].text, '...', 'Narrow icon layout still has an explicit cue');

local saved = defaults.make();
saved.display.order = { 'rate', 'rate', 'bogus', 'progress' };
saved.display.enabled.rate = false;
saved.bar.width = 0 / 0;
saved.bar.auto_width = false;
saved.bar.bottom = math.huge;
saved.style.colors.text = { -2, 4, 0 / 0, 9 };
defaults.tidy(saved);
equal(saved.display.order[1], 'rate', 'Saved ordering survives tidy');
equal(saved.display.order[2], 'progress', 'Duplicates and unknown readouts are removed');
equal(#saved.display.order, #defaults.READOUTS, 'New readouts are appended');
equal(saved.display.enabled.rate, false, 'Disabled readout stays disabled');
equal(saved.bar.width, 640, 'Invalid width falls back to compact default');
equal(saved.bar.bottom, defaults.make().bar.bottom, 'Invalid bottom gap uses default');
equal(saved.bar.auto_width, false, 'Manual sizing choice survives tidy');
equal(saved.style.colors.text[1], 0, 'Colors clamp low');
equal(saved.style.colors.text[2], 1, 'Colors clamp high');
equal(saved.style.colors.text[4], 1, 'Alpha clamps high');
equal(saved.alerts.food_enabled, false, 'Food sound starts off');
saved.alerts.food_sound = 'C:\\sounds\\bell".wav';
saved.alerts.food_volume = 140;
defaults.tidy(saved);
equal(saved.alerts.food_sound, 'bell.wav', 'Sound settings keep only a safe file name');
equal(saved.alerts.food_volume, 100, 'Sound volume clamps high');
saved.alerts.food_volume = -20;
saved.alerts.food_sound = '..';
defaults.tidy(saved);
equal(saved.alerts.food_volume, 0, 'Sound volume clamps low');
equal(saved.alerts.food_sound, '', 'Folder-only sound name is cleared');

return { count = checks };
