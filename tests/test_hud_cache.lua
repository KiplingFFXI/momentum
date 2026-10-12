local imgui = require('imgui');
local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local theme = require('ui.theme');
local texture = 42;
package.loaded['ui.job_icons'] = { texture = function() return texture; end };
local hud = require('ui.hud');
local checks, builds, measures, arrangements = 0, 0, 0, 0;
local layout = require('ui.layout');
local original_arrange = layout.arrange;
layout.arrange = function(...) arrangements = arrangements + 1; return original_arrange(...); end;
local original_build, original_measure = readouts.build, imgui.CalcTextSize;
readouts.build = function(...) builds = builds + 1; return original_build(...); end;
imgui.CalcTextSize = function(...) measures = measures + 1; return original_measure(...); end;
local function check(value, message) checks = checks + 1; assert(value, message); end
local settings, view = defaults.make(), readouts.sample();
settings.bar.docked, settings.bar.auto_width = false, false;
settings.bar.width, settings.bar.height, settings.bar.x, settings.bar.y = 1200, 24, 20, 100;
local function draw(context)
    MOCK.imgui_calls = {};
    hud.draw(settings, view, context or {});
    local text = {};
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddText' then text[#text + 1] = call[6]; end end
    return table.concat(text, '|');
end
local function text_call(value)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddText' and call[6] == value then return call; end end
end
for _ = 1, 100 do draw(); end
check(builds == 1, 'An unchanged HUD formats its readouts once.');
check(measures < 30, 'An unchanged HUD retains its text measurements.');
local last_arrangement = arrangements;
local last_build = builds;
view.rate = 8500.1;
check(draw():find('8,500', 1, true), 'A fractional rate still shows its rounded value.');
view.rate = 8500.4;
draw();
check(arrangements == last_arrangement, 'Changing raw rates do not rearrange identical displayed text.');
check(builds == last_build, 'Changing only undisplayed rate precision does not reformat the entire bar.');
view.rate = 8500.6;
check(draw():find('8,501', 1, true) and arrangements == last_arrangement + 1, 'A changed displayed rate refreshes its layout immediately.');
view.rate = 8500;
draw();
local previous = builds;
view.rings = setmetatable({}, { __index = function() error('A disabled ring readout was evaluated.'); end });
draw();
check(builds == previous, 'A disabled readout does not invalidate or evaluate the visible line.');
view.rings = { available = true, entries = { { name = 'Band', charges = 3, recast = 120 } } };
view.current = 12500;
check(draw():find('12,500 / 20,000', 1, true), 'Current progress changes appear immediately.');
settings.display.labels.rate = 'Pace';
check(draw():find('Pace EXP/HR ', 1, true), 'Changing a label invalidates the formatted line.');
settings.display.short = true;
check(draw():find('12.5k / 20.0k', 1, true), 'Short-number formatting invalidates the line.');
settings.display.short = false;
settings.display.label_position = 'after';
check(draw():find(' Pace EXP/HR', 1, true), 'Label position invalidates segments without a data change.');
settings.display.label_position = 'before';
settings.display.divider = ' / ';
check(draw():find(' / ', 1, true), 'Divider style invalidates segments.');
settings.display.dividers.rate = false;
draw();
local parts = require('ui.layout').segments(readouts.cached(settings, view), settings.display);
local rate_divider;
for _, part in ipairs(parts) do if part.id == 'rate' and part.role == 'divider' then rate_divider = part.text; end end
check(rate_divider == '', 'An individual divider edit is retained.');
texture = 99;
draw();
local icon;
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddImage' then icon = call[2]; end end
check(icon == 99, 'A replacement job texture is drawn.');
texture = nil;
check(draw():find('WAR 61', 1, true), 'A missing texture restores the text-only job reading.');
settings.style.font = 'Arial'; previous = measures; draw();
check(measures > previous, 'Changing the selected font measures the text again.');
settings.style.font_size = 16; previous = measures; draw();
check(measures > previous, 'Changing text size measures the text again.');
settings.display.colors.rate = { 0.1, 0.8, 0.3, 1 };
draw();
local expected_color, found_color = theme.u32(settings.display.colors.rate), false;
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddText' and call[6] == '8,500' and call[5] == expected_color then found_color = true; end end
check(found_color, 'Value color changes stay live with cached text.');

settings.display.order = { 'goal', 'average3', 'ring' };
for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true; end
view.goal = { available = true, remaining = 100, unit = 'EXP', eta = 120 };
check(draw():find('100 EXP left (~2:00)', 1, true), 'A nested goal is formatted.');
view.goal.remaining, view.recent3.average, view.rings.entries[1].charges = 150, 222, 2;
local text = draw();
check(text:find('150 EXP left', 1, true) and text:find('222', 1, true) and text:find('Band 2 charges', 1, true), 'In-place goal, sample and ring changes invalidate their text.');

settings.display.order = { 'chain_time', 'chain' };
settings.display.enabled.chain_time = true;
view.chain_source, view.chain_active, view.chain_left = 'local', nil, 10.1;
draw(); previous = builds;
view.chain_left = 9.9;
check(draw():find('~0:10', 1, true), 'The local countdown retains its displayed second.');
check(builds == previous, 'Sub-second timer changes do not rebuild unchanged text.');
found_color = false;
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddText' and call[6] == '~0:10' and call[5] == theme.u32(settings.style.colors.chain_ending) then found_color = true; end end
check(found_color, 'The urgent color changes at ten seconds even when the text stays cached.');
view.chain_left = 9.4;
check(draw():find('~0:09', 1, true), 'The countdown advances at its next displayed second.');
view.notice = { text = 'Food wears off soon.' };
settings.bar.height = 12;
text = draw();
check(text:find('~0:09', 1, true) and text_call('!'), 'A short bar keeps the countdown while showing an alert badge.');
local badge = text_call('!');
check(badge[4][1] >= settings.bar.x and badge[4][1] < settings.bar.x + 9, 'The badge uses existing padding rather than readout space.');
view.notice = nil;

settings.bar.height, settings.bar.docked = 24, true;
local chat = { x = 12, y = 500, width = 900, height = 344 };
draw({ chat = chat });
local info = hud.draw_inline(settings, view, 200);
check(info.bar_width == 900 and info.preview_width == 200 and info.preview_clipped, 'The inline preview uses actual dock width and distinguishes its own clipping.');
check(not info.overflow and info.hidden_count == 0, 'Settings-window clipping is not reported as actual bar overflow.');
info = hud.draw_inline(settings, view, 200, nil, { preview = true, width = 120 });
check(info.bar_width == 120 and info.simulated_width and info.overflow, 'An explicit narrow sample simulates a narrower bar instead of cropping the live layout.');
info = hud.draw_inline(settings, view, 200, nil, { preview = false, width = 120 });
check(info.bar_width == 900 and info.simulated_width == false, 'A live preview never treats a sample width as an applied simulation.');
info = hud.draw_inline(settings, view, 200, nil, { preview = true, width = -1 });
check(info.bar_width == 900 and info.simulated_width == false, 'An invalid sample width does not report an applied simulation.');
info = hud.draw_inline(settings, view, 200, nil, { chat_checked = true });
check(info.unavailable, 'Explicit missing native chat does not reuse stale bounds.');
settings.bar.docked, settings.bar.width = false, 200;
settings.display.order = { 'job', 'progress', 'remaining', 'rate', 'chain_time' };
settings.display.priority_overflow, settings.display.pinned = true, { chain_time = true };
draw();
info = hud.draw_inline(settings, view, 400);
check(info.overflow and info.hidden_count > 0 and not info.preview_clipped, 'Actual narrow-bar overflow is distinct from preview clipping.');
local hidden = {}; for _, item in ipairs(info.hidden_readouts) do hidden[item.id] = true; end
check(not hidden.chain_time and hidden.progress, 'Overflow metadata contains only readings not fully visible.');
settings.bar.width = 1200;
info = hud.draw_inline(settings, view, 1300);
check(not info.overflow and info.hidden_count == 0, 'Widening the bar invalidates its overflow decision.');
settings.display.order = { 'dedication', 'sync', 'food', 'chain_time' };
for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true; end
view.chain_source, view.chain_left = 'server', 15;
for _, field in ipairs({ 'dedication', 'sync_active', 'food', 'chain_active' }) do view[field] = false; end
text = draw();
check(text:find('No Dedication', 1, true) and text:find('Off', 1, true) and text:find('None', 1, true) and not text:find('0:15', 1, true), 'Explicit inactive states have their own readings.');
for _, field in ipairs({ 'dedication', 'sync_active', 'food', 'chain_active' }) do view[field] = nil; end
text = draw();
check(text:find('Dedication --', 1, true) and not text:find('Off', 1, true) and not text:find('None', 1, true) and text:find('0:15', 1, true), 'False-to-unknown transitions invalidate every distinct reading.');
for _, field in ipairs({ 'dedication', 'sync_active', 'food', 'chain_active' }) do view[field] = false; end
text = draw();
check(text:find('No Dedication', 1, true) and text:find('Off', 1, true) and text:find('None', 1, true) and not text:find('0:15', 1, true), 'Unknown-to-false transitions invalidate every distinct reading.');
for _, pair in ipairs({ { 'dedication', 'dedication' }, { 'sync', 'sync_active' }, { 'food', 'food' }, { 'chain_time', 'chain_active' } }) do
    settings.display.order = { pair[1] };
    view[pair[2]] = false;
    local inactive = readouts.cached(settings, view)[1].value;
    view[pair[2]] = nil;
    check(readouts.cached(settings, view)[1].value ~= inactive, 'Only this false-to-nil input changes its cached value: ' .. pair[2]);
    view[pair[2]] = false;
    check(readouts.cached(settings, view)[1].value == inactive, 'Only this nil-to-false input restores its cached value: ' .. pair[2]);
end
settings.display.order = { 'rate', 'status' };
settings.display.enabled.rate, settings.display.enabled.status = true, true;
settings.display.conditions.status, view.mode, view.paused = 'lp', 'exp', true;
check(draw():find('PAUSED  ', 1, true), 'A conditionally hidden status cannot hide the pause indicator.');
view.mode = 'lp';
text = draw();
check(text:find('Paused', 1, true) and not text:find('PAUSED  ', 1, true), 'The visible status replaces the fallback pause indicator.');
settings.display.order = { 'rate' };
check(draw():find('PAUSED  ', 1, true), 'An enabled status absent from the reading order cannot hide the pause indicator.');
return { count = checks };
