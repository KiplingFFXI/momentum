local imgui = require('imgui');
local bit = require('bit');
local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
package.loaded['ui.job_icons'] = { texture = function () return 42; end };
local hud = require('ui.hud');
local count = 0;
local function check(value, message) assert(value, message); count = count + 1; end
local settings, view = defaults.make(), readouts.sample();
settings.bar.docked, settings.bar.auto_width = false, false;
settings.bar.x, settings.bar.y, settings.bar.width, settings.bar.height = 20, 100, 1300, 28;
MOCK.screen = { 1600, 900 };
local now = 0;
imgui.IsAnyMouseDown = function () return MOCK.mouse_down == true; end;
local function frame(x, y, context)
    MOCK.imgui_calls, MOCK.mouse_x, MOCK.mouse_y = {}, x or -1, y or -1;
    now = now + 0.3;
    context = context or {};
    context.now = now;
    hud.draw(settings, view, context);
    local words, opened = {}, false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'BeginTooltip' then opened = true;
        elseif call[1] == 'EndTooltip' then opened = false;
        elseif opened and call[1] == 'TextUnformatted' then words[#words + 1] = call[2];
        elseif opened and call[1] == 'TextColored' then words[#words + 1] = call[3]; end
    end
    return table.concat(words, '\n');
end
local function find_text(text)
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddText' and call[6] == text then return call[4][1], call[4][2]; end
    end
    error('Missing drawn text: ' .. text);
end
local function dwell(x, y, context)
    frame();
    check(frame(x, y, context) == '', 'A new readout waits before showing help.');
    return frame(x, y, context);
end

frame();
local rate_x, rate_y = find_text('EXP/HR ');
local words = dwell(rate_x + 1, rate_y + 2);
check(words:find('EXP/HR', 1, true) and words:find('8,500', 1, true), 'The exact hovered rate has its own title and current value.');
check(words:find('EXP/LP received counts', 1, true) and words:find('Level Sync penalty is already included', 1, true), 'Earned pace explains received rewards and applied penalties.');
check(not words:find('Momentum session', 1, true) and not words:find('Other EXP changes:', 1, true), 'A rate hover does not dump unrelated session fields.');
hud.cancel_layout_gesture();
check(frame(rate_x + 1, rate_y + 2) == '', 'Returning after the bar is hidden starts a new hover delay.');
check(frame(rate_x + 1, rate_y + 2):find('EXP/HR', 1, true), 'Help returns after dwelling on the visible bar again.');
local definition_calls, original_definition = 0, readouts.definition;
readouts.definition = function (id) definition_calls = definition_calls + 1; return original_definition(id); end;
now = now - 0.28;
frame(rate_x + 1, rate_y + 2);
check(definition_calls == 0, 'Help text is retained between refreshes rather than rebuilt each frame.');
readouts.definition = original_definition;
settings.tracking.rate_basis = 'net';
words = frame(rate_x + 1, rate_y + 2);
check(words:find('EXP/LP kept counts', 1, true) and not words:find('EXP/LP received counts', 1, true), 'Net pace explains the selected basis.');
settings.tracking.rate_basis = 'earned';

frame();
local remaining_x, remaining_y = find_text('TNL ');
check(frame(rate_x + 1, rate_y + 2) == '', 'Leaving the bar resets hover delay.');
frame(rate_x + 1, rate_y + 2);
check(frame(remaining_x + 1, remaining_y + 2) == '', 'Moving directly to another reading restarts the delay.');
check(frame(remaining_x + 1, remaining_y + 2):find('EXP to next level (TNL)', 1, true), 'The adjacent TNL reading gets its own help.');

frame();
local icon_x, icon_y;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'draw:AddImage' then icon_x, icon_y = call[3][1], call[3][2]; end
end
check(icon_x ~= nil, 'A job picture was drawn.');
check(dwell(icon_x + 1, icon_y + 1):find('Job and level', 1, true), 'The job picture shares the job reading tooltip.');

for _, context in ipairs({ { shift = true }, { typing = true } }) do
    check(dwell(rate_x + 1, rate_y + 2, context) == '', 'Shift and typing suppress help.');
end
settings.bar.locked = true;
check(dwell(rate_x + 1, rate_y + 2, { shift = true }) == '', 'Holding Shift also suppresses help when position is locked.');
settings.bar.locked = false;
MOCK.mouse_down = true;
check(dwell(rate_x + 1, rate_y + 2) == '', 'Mouse gestures suppress help.');
MOCK.mouse_down = false;
MOCK.hovered = true;
check(dwell(rate_x + 1, rate_y + 2) == '', 'Another hovered window suppresses help.');
MOCK.hovered = false;
settings.display.hover = false;
check(dwell(rate_x + 1, rate_y + 2) == '', 'The hover preference suppresses help.');
settings.display.hover = true;
frame();
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'Begin' and call[2] == '##momentum_bar' then
        check(bit.band(call[4], ImGuiWindowFlags_NoInputs) == ImGuiWindowFlags_NoInputs, 'Readout help preserves the click-through bar.');
    end
end

for _, alignment in ipairs({ 'left', 'right' }) do
    for _, label_position in ipairs({ 'before', 'after' }) do
        settings.display.alignment, settings.display.label_position = alignment, label_position;
        frame();
        local text = label_position == 'after' and ' EXP/HR' or 'EXP/HR ';
        local x, y = find_text(text);
        check(dwell(x + 2, y + 2):find('EXP/HR', 1, true), 'Rate labels hit correctly with both alignment and label positions.');
        frame();
        local vx, vy = find_text('8,500');
        check(dwell(vx + 2, vy + 2):find('EXP/HR', 1, true), 'Rate values hit the same reading with either label position.');
    end
end
settings.display.label_position, settings.display.alignment = 'before', 'left';
settings.display.divider = '|';
frame();
local divider_x, divider_y = find_text('|');
check(dwell(divider_x + 1, divider_y + 2) == '', 'Dividers never borrow an adjacent reading tooltip.');
check(dwell(divider_x - 2, divider_y + 2) == '', 'Spacing before a divider has no unrelated tooltip.');
settings.display.groups_enabled = true;
settings.display.groups.job, settings.display.groups.progress = 'left', 'center';
settings.display.groups.remaining, settings.display.groups.rate, settings.display.groups.chain = 'right', 'right', 'right';
frame();
local x, y = find_text('EXP/HR ');
check(dwell(x + 2, y + 2):find('EXP/HR', 1, true), 'Grouped readings use their actual drawn offsets.');
settings.bar.width, settings.display.priority_overflow = 240, true;
settings.display.pinned.rate = true;
frame();
x, y = find_text('...');
words = dwell(x + 2, y + 2);
check(words:find('More readings', 1, true) and words:find('TNL', 1, true), 'Overflow help lists the hidden readouts.');
check(not words:find('EXP/HR', 1, true), 'Overflow help does not repeat the pinned rate that is already visible.');

settings.display.enabled.sync = true;
view.sync_active, view.sync_level, view.effective_level, view.sync_gap = true, 50, 50, 11;
local title, value, help = hud._tooltip(settings, view, 'sync');
check(help:find('Your normal job level is 61', 1, true) and help:find('Your synced level is 50', 1, true), 'Sync help names each level.');
check(help:find('level difference is 11 levels', 1, true) and help:find('penalty estimate', 1, true), 'Sync help explains the client gap and manual planner.');
view.sync_active = false;
title, value, help = hud._tooltip(settings, view, 'sync');
check(help:find('Level Sync is off', 1, true), 'Unsynced help explains the current state.');
view.level, view.mode = 75, 'exp';
title, value, help = hud._tooltip(settings, view, 'remaining');
check(title == 'EXP buffer remaining' and help:find('does not lead to another level', 1, true), 'Level 75 TNL describes buffer space.');
view.mode = 'lp';
title, value, help = hud._tooltip(settings, view, 'remaining');
check(title == 'LP to next merit point', 'LP TNL targets the next merit.');
title, value, help = hud._tooltip(settings, view, 'chain_time');
check(help:find('This timer uses Phoenix EXP chain rules', 1, true) and help:find('connection delay', 1, true), 'Fresh chain timing explains the local estimate and normal delay.');
view.chain_source = 'unknown';
title, value, help = hud._tooltip(settings, view, 'chain_time');
check(help:find('waiting for an EXP chain reward', 1, true) and not help:find('companion', 1, true), 'Unavailable timing explains the required observation without a server install.');
view.chain_source, view.chain_estimated = 'local', true;
title, value, help = hud._tooltip(settings, view, 'chain_time');
check(title == 'EXP chain timer (estimated)', 'The local countdown title marks its estimate.');
check(help:find('This timer uses Phoenix EXP chain rules', 1, true) and help:find('shortest possible time', 1, true), 'Local timing explains its conservative Phoenix-table window.');
check(help:find('next kill must qualify', 1, true) and help:find('when the reward arrives', 1, true), 'Local help explains eligibility and receipt anchoring.');
view.chain_left = nil;
title, value, help = hud._tooltip(settings, view, 'chain_time');
check(title == 'Estimated EXP chain timer ended', 'An expired local estimate has a distinct title.');
check(help:find('EXP chain may still be active', 1, true) and not help:find('No EXP chain is active', 1, true), 'Local estimate expiry never claims that the actual chain ended.');
view.chain_left = 38;
view.valid = false;
title, value, help = hud._tooltip(settings, view, 'rate');
check(value == '--' and help:find('Waiting for your character information', 1, true), 'Unavailable player data does not reuse a prior value.');
view.events.currencies = { beastmen_seals = { value = 123 }, kindred_seals = { value = 37 }, ancient_beastcoins = { value = 18 } };
view.events.inventory_available, view.events.inventory = true, { [1126] = 4, [1127] = 2, [1875] = 6 };
for id, expected in pairs({ beastmen_seals = '123', kindred_seals = '37', beastcoins_stored = '18', beastmen_carried = '4', kindred_carried = '2', beastcoins_carried = '6' }) do
    settings.display.enabled[id] = true;
    title, value, help = hud._tooltip(settings, view, id);
    check(value == expected and not help:find('Waiting for your character information', 1, true), 'Known seal and coin balances keep their own help before EXP data is available.');
    settings.display.enabled[id] = false;
end
settings.display.enabled.beastmen_seals = true;
view.events.currencies.beastmen_seals = nil;
title, value, help = hud._tooltip(settings, view, 'beastmen_seals');
check(value == '--' and help:find('Shami', 1, true), 'An unknown stored balance explains Shami instead of waiting for EXP data.');
settings.display.enabled.beastmen_seals = false;
view.valid = true;
settings.display.show_text, settings.display.enabled.progress = false, false;
words = dwell(settings.bar.x + 30, settings.bar.y + 8);
check(words:find('12,450 / 20,000', 1, true), 'A fill-only bar still explains its actual current progress.');
local original_event = view.events;
view.events, view.valid = readouts.sample('Limbus').events, false;
settings.events.active_kind, settings.display.enabled.event_time = 'limbus', false;
title, value, help = hud._tooltip(settings, view, 'progress');
check(title == 'Assault or battlefield time left' and value == '~18:44', 'A fill-only Limbus bar explains its estimated time even when that readout is disabled.');
check(help:find('Session pause and reset leave this running', 1, true), 'Event fill help preserves timer behavior without EXP data.');
view.events.remaining = nil;
title, value = hud._tooltip(settings, view, 'progress');
check(value == '--', 'A fill-only event bar never substitutes EXP progress for an unknown deadline.');
view.events.remaining, view.events.time_estimated = 900, false;
settings.events.active_kind = 'bcnm';
title, value = hud._tooltip(settings, view, 'progress');
check(value == '15:00', 'A fill-only native battlefield countdown remains exact.');
settings.events.active_kind, settings.dynamis.layout_active = nil, true;
view.dynamis = readouts.sample('Dynamis').dynamis;
title, value = hud._tooltip(settings, view, 'progress');
check(title == 'Dynamis time left' and value == '1:03:52', 'A fill-only Dynamis bar explains the timer it displays.');
settings.dynamis.layout_active, view.dynamis = false, nil;
view.events, view.valid = original_event, true;
view.notice = { text = 'Food is ending soon.' };
words = dwell(settings.bar.x + 30, settings.bar.y + 8);
check(words:find('12,450 / 20,000', 1, true), 'An alert preserves progress help on a fill-only bar away from the alert badge.');
words = dwell(settings.bar.x + 3, settings.bar.y + 8);
check(words:find(view.notice.text, 1, true), 'The fill-only alert badge still has its own notification help.');
settings.display.show_text = true;
view.notice = { text = 'Food is ending soon. Open Alerts to adjust the warning.' };
frame();
x, y = find_text('!');
check(find_text('8,500') ~= nil, 'An alert keeps the pinned rate visible.');
words = dwell(x + 2, y + 2);
check(words:find(view.notice.text, 1, true), 'The alert badge reveals its full text.');

view.notice = nil;
settings.display.order, settings.bar.width = { 'chain' }, 400;
local function strip_count()
    frame();
    local strips = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddRectFilled' and call[2][2] == settings.bar.y + 1 and call[3][2] == settings.bar.y + 2 then
            strips = strips + 1;
        end
    end
    return strips;
end
view.chain_source, view.chain_left, view.chain_window = 'local', 38, 60;
check(strip_count() == 1, 'A current local countdown draws the chain strip.');
view.chain_source, view.chain_estimated = 'unknown', true;
check(strip_count() == 0, 'Unknown timing never draws the chain strip.');
view.chain_source = 'local';
check(strip_count() == 1, 'A valid local Phoenix estimate draws the chain strip.');
view.chain_left = nil;
check(strip_count() == 0, 'An expired local estimate hides the chain strip.');
view.chain_left = 0 / 0;
check(strip_count() == 0, 'Invalid timing never reaches strip geometry.');
view.valid, view.chain_left = false, 38;
check(strip_count() == 0, 'Unavailable player data never reuses a prior chain strip.');

return { count = count };
