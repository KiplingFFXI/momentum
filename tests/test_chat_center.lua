local defaults = require('ui.defaults');
local layout = require('ui.layout');
local history = require('ui.history');
local profiles = require('ui.profiles');
local readouts = require('ui.readouts');
package.loaded['ui.job_icons'] = { texture = function() return nil; end };
local hud = require('ui.hud');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function check(value, label) equal(not not value, true, label); end
local function same_rect(actual, expected, label)
    for _, key in ipairs({ 'x', 'y', 'width', 'height' }) do equal(actual[key], expected[key], label .. ': ' .. key); end
end
local function centered(rect, x, width, label)
    check(not rect.hidden, label .. ': visible');
    check(rect.x >= x and rect.x + rect.width <= x + width, label .. ': contained within chat');
    check(math.abs(rect.x + rect.width / 2 - x - width / 2) <= 0.5, label .. ': centered within one pixel');
end

equal(defaults.make().bar.chat_alignment, 'left', 'Existing left docking remains the default');
for _, value in ipairs({ 'right', '', 3, false, {} }) do
    local settings = defaults.make();
    settings.bar.chat_alignment = value;
    settings.bar.start, settings.bar.locked = 143, true;
    defaults.tidy(settings);
    equal(settings.bar.chat_alignment, 'left', 'Invalid chat alignment falls back to Left');
    equal(settings.bar.start, 143, 'Alignment validation preserves the starting point');
    equal(settings.bar.locked, true, 'Alignment validation preserves the movement lock');
end
local migrated = defaults.make();
migrated.bar.chat_alignment = nil;
defaults.tidy(migrated);
equal(migrated.bar.chat_alignment, 'left', 'An older saved bar keeps Left docking');
migrated.bar.chat_alignment = 'center';
defaults.tidy(migrated);
equal(migrated.bar.chat_alignment, 'center', 'An explicit Center choice survives validation');

local bar = defaults.make().bar;
local chat = { x = 12, y = 520, width = 900, height = 344, windows = {} };
bar.chat_alignment, bar.start = 'center', 200;
local saved = history.copy(bar);
local rect = layout.rect(bar, 1600, 900, chat, 384.2);
centered(rect, 12, 900, 'Automatic compact dock');
equal(rect.width, 385, 'Measured content rounds up without clipping');
equal(rect.y, 866, 'Centered bottom dock clears the native border');
equal(rect.anchor, 'bottom', 'Centered dock retains its bottom anchor');
check(history.equal(bar, saved), 'Rendering the centered dock does not change saved placement');
equal(layout.rect(bar, 1600, 900, chat, 1300).width, 640, 'Long readouts stop at the saved maximum width');
equal(layout.rect(bar, 1600, 900, chat, 1).width, 1, 'Short automatic content does not gain an unrelated minimum width');
rect = layout.dock(bar, 1600, 900, chat, 'top', 384.2);
centered(rect, 12, 900, 'Explicit top dock with measured content');
equal(rect.y, 500, 'Centered top dock clears the native border');
equal(rect.anchor, 'top', 'An explicit top anchor remains top');

bar.auto_width, bar.width = false, 500;
rect = layout.rect(bar, 1600, 900, chat, 1);
centered(rect, 12, 900, 'Fixed compact dock');
equal(rect.width, 500, 'Fixed centered width ignores shorter readouts');
bar.width = 1500;
rect = layout.rect(bar, 1600, 900, chat);
centered(rect, 12, 900, 'Centered dock wider than chat');
equal(rect.width, 900, 'A wide centered bar stops at the chat edges');
bar.width = 500;
rect = layout.rect(bar, 800, 600, { x = -20, y = 400, width = 900, height = 170 });
centered(rect, 0, 800, 'Partly offscreen chat');
equal(rect.y, 572, 'Clipped primary chat retains its bottom clearance');
rect = layout.rect(bar, 1600, 900, { x = 12.2, y = 520.3, width = 900.6, height = 343.9 });
centered(rect, 13, 899, 'Fractional chat bounds');
rect = layout.rect(bar, 1600, 900, { x = 12, y = 520, width = 90, height = 344 });
centered(rect, 12, 90, 'Chat narrower than the normal width control');
equal(rect.width, 90, 'A narrow chat remains the centered width limit');

bar.auto_width, bar.width = true, 640;
local split = { x = 12, y = 520, width = 900, height = 344,
    windows = { { x = 12, y = 0, width = 300, height = 900 } } };
rect = layout.rect(bar, 1600, 900, split, 300);
centered(rect, 12, 900, 'Second chat ending at the centered left edge');
equal(rect.y, 866, 'A nonoverlapping second chat does not obstruct a compact dock');
split.windows[1].width = 301;
equal(layout.rect(bar, 1600, 900, split, 300).hidden, true, 'One pixel of second-chat overlap is protected');
split.windows[1].width = 300;
bar.anchor = 'top';
equal(layout.rect(bar, 1600, 900, split, 300).y, 500, 'Top clearance uses the actual centered span too');
split.windows[1].width = 301;
equal(layout.rect(bar, 1600, 900, split, 300).hidden, true, 'Top docking cannot overlap a second chat');
bar.anchor = 'bottom';
equal(layout.rect(bar, 800, 600, { x = 13, y = 200, width = 700, height = 387 }, 300).hidden, true,
    'Centering does not move an obstructed bottom dock into chat');
bar.anchor = 'top';
equal(layout.rect(bar, 800, 600, { x = 13, y = 13, width = 700, height = 300 }, 300).hidden, true,
    'Centering does not move an obstructed top dock into chat');
bar.anchor, bar.chat_alignment = 'bottom', 'left';
rect = layout.rect(bar, 1600, 900, chat, 300);
equal(rect.x, 212, 'Returning Left restores the saved starting point');
equal(rect.width, 700, 'Returning Left restores the original full remaining chat width');

bar.chat_alignment, bar.start, bar.width, bar.auto_width = 'center', 0, 640, true;
bar.docked, bar.snap = false, true;
layout.move(bar, 312, 866, 1600, 900, true, 300, split);
equal(bar.docked, false, 'A centered snap with a real second-chat overlap stays free');
split.windows[1].width = 300;
layout.move(bar, 312, 866, 1600, 900, true, 300, split);
equal(bar.docked, true, 'Compact centered snapping ignores a second chat outside its rendered span');
equal(bar.chat_alignment, 'center', 'Snapping preserves the chosen chat alignment');

local settings, view = defaults.make(), readouts.sample();
settings.bar.chat_alignment, settings.bar.width, settings.bar.auto_width = 'center', 600, true;
settings.bar.start, settings.bar.locked = 197, true;
settings.display.order = { 'rate' };
settings.display.enabled.rate = true;
settings.display.alignment = 'right';
local context = { chat = chat, chat_visible = true, chat_checked = true, shift = true };
local measured = hud.bounds(settings, view, context);
centered(measured, 12, 900, 'HUD compact measurement');
check(measured.width < settings.bar.width, 'The centered HUD uses measured readouts instead of the width cap');
settings.bar.docked = false;
local free = hud.bounds(settings, view, {});
equal(measured.width, free.width, 'Compact dock and free placement measure the same readouts');
settings.bar.docked = true;
local saved_settings = history.copy(settings);
MOCK.imgui_calls = {};
hud.draw(settings, view, context);
check(history.equal(settings, saved_settings), 'Holding Shift never bypasses a saved movement lock');
local drag_controls = 0;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'InvisibleButton' and call[2] == '##momentum_drag' then drag_controls = drag_controls + 1; end
end
equal(drag_controls, 0, 'A locked centered bar does not accept Shift drag input');
equal(settings.display.alignment, 'right', 'Centering the bar preserves readout alignment');

for _, mode in ipairs({ 'keep', 'always' }) do
    for _, anchor in ipairs({ 'top', 'bottom' }) do
        settings.visibility.mode, settings.bar.anchor = mode, anchor;
        hud.reset_chat_anchor();
        hud.draw(settings, view, context);
        local live = hud.bounds(settings, view, context);
        settings.display.labels.rate = 'A much longer EXP/HR label';
        local closed = { chat_visible = false, chat_checked = true };
        same_rect(hud.bounds(settings, view, closed), live, mode .. ' freezes the compact ' .. anchor .. ' rectangle when chat closes');
        hud.draw(settings, view, closed);
        local moved_chat = { x = 200, y = 450, width = 1000, height = 360, windows = {} };
        same_rect(hud.bounds(settings, view, { chat = moved_chat, chat_visible = false, chat_checked = true }), live,
            mode .. ' ignores changed retained chat bounds');
        local reopened = hud.bounds(settings, view, { chat = moved_chat, chat_visible = true, chat_checked = true });
        centered(reopened, 200, 1000, mode .. ' recenters when live chat reopens');
        equal(reopened.y, anchor == 'top' and 430 or 812, mode .. ' keeps the new live ' .. anchor .. ' edge');
        settings.display.labels.rate = nil;
    end
end

settings.visibility.mode, settings.bar.auto_width, settings.bar.width = 'keep', false, 500;
hud.reset_chat_anchor();
hud.draw(settings, view, context);
MOCK.screen = { 350, 600 };
local reduced = hud.bounds(settings, view, { chat_visible = false, chat_checked = true });
equal(reduced.width, 350, 'A held centered bar shrinks only enough to fit a smaller client');
equal(reduced.x, 0, 'A held centered bar stays within the resized client horizontally');
equal(reduced.y + reduced.height, 600, 'A held centered bar stays within the resized client vertically');
MOCK.screen = nil;

local captured = profiles.capture(settings);
local restored = defaults.make();
profiles.apply(restored, captured);
defaults.tidy(restored);
equal(restored.bar.chat_alignment, 'center', 'Profiles preserve Center docking');
equal(restored.bar.start, 197, 'Profiles preserve the saved Left starting point');
equal(restored.bar.locked, true, 'Profiles preserve the movement lock');
equal(restored.display.alignment, 'right', 'Profiles keep readout alignment separate from chat alignment');
local undo = history.new();
local before = history.copy(restored);
restored.bar.chat_alignment, restored.bar.start = 'left', 25;
undo:push(before);
check(undo:undo(restored), 'The alignment change can be undone');
equal(restored.bar.chat_alignment, 'center', 'Undo restores Center docking');
equal(restored.bar.start, 197, 'Undo restores the saved starting point');
profiles.apply(restored, { bar = { docked = true, anchor = 'bottom', start = 88 } });
defaults.tidy(restored);
equal(restored.bar.chat_alignment, 'left', 'An old profile keeps its original Left docking');
equal(restored.bar.start, 88, 'Loading an old profile preserves its starting point');

return { count = count };
