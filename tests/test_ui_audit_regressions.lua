local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local theme = require('ui.theme');
local imgui = require('imgui');
local hud = require('ui.hud');
local count = 0;
local function eq(actual, expected, title)
    count = count + 1;
    assert(actual == expected, title .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local settings, view = defaults.make(), readouts.sample('Leveling');
settings.bar.docked, settings.bar.auto_width, settings.bar.width = false, false, 600;
settings.display.show_text, view.percent = false, 0.5;
local function progress(color)
    MOCK.imgui_calls = {};
    hud.draw(settings, view, {});
    local width, fills = 0, 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddRectFilled' and call[4] == theme.u32(color) then
            width, fills = width + call[3][1] - call[2][1], fills + 1;
        end
    end
    return width, fills;
end
local exp_width, fills = progress(settings.style.colors.fill);
eq(fills, 1, 'The normal EXP layout retains its progress fill');
settings.dynamis.layout_active = true;
view.dynamis = { active = false };
local width;
width, fills = progress(settings.style.colors.fill);
eq(fills, 0, 'An inactive Dynamis layout does not show unrelated EXP progress');
view.dynamis = nil;
width, fills = progress(settings.style.colors.fill);
eq(fills, 0, 'An unavailable Dynamis run leaves the time fill unknown');
view.dynamis = { active = true, start_time = 100, end_time = 200 };
width, fills = progress(settings.style.colors.fill);
eq(fills, 0, 'An active Dynamis run with unknown remaining time has no fill');
view.dynamis.remaining = 25;
width, fills = progress(settings.style.colors.fill);
eq(fills, 1, 'A known active Dynamis timer still fills the bar');
eq(width * 2, exp_width, 'The Dynamis fill follows time remaining instead of EXP');
view.dynamis.end_time = 100;
width, fills = progress(settings.style.colors.fill);
eq(fills, 0, 'A missing usable Dynamis duration does not fall back to EXP');
settings.dynamis.layout_active, view.mode = false, 'lp';
width, fills = progress(settings.style.colors.lp_fill);
eq(fills, 1, 'Leaving Dynamis restores the normal LP fill');
eq(width, exp_width, 'The unrelated-mode progress amount is unchanged');

package.loaded['ui.settings_window'] = nil;
local window = require('ui.settings_window');
settings, view = defaults.make(), readouts.sample('Leveling');
settings.window.open = true;
local query, next_open = '', nil;
imgui.InputTextWithHint = function(label, _, value)
    if label == '##Find settings' then value[1] = query; end
    return false;
end;
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function() return next_open; end;
local function draw(click, services)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end
    window.draw(settings, view, services or {});
end
local function called(name, label)
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == name and call[2] == label then return true; end
    end
    return false;
end
query = 'subjob';
draw();
eq(called('Button', 'Display: Selected readout##find'), false, 'Subjob search omits the unrelated generic editor result');
eq(called('Button', 'Job and level##find'), true, 'Subjob search offers the Job and level readout directly');
draw('Job and level##find');
eq(called('Checkbox', 'Show subjob and level'), true, 'The readout search result opens the actual subjob checkbox');
draw('Show subjob and level');
eq(settings.display.show_subjob, true, 'The found checkbox changes the saved option');
query = '';
draw('02  EXP / LP progress');
query = 'divider';
draw('Display: Selected readout##find');
eq(called('Button', 'Display: Selected readout##find'), true, 'Generic editor search remains available for its normal controls');
eq(called('Checkbox', 'Show subjob and level'), false, 'A generic divider search keeps the selected progress editor');

query = '';
imgui.BeginCombo = function(label) return label == '##reset_actions'; end;
local resets = {};
local services = { reset_section = function(section) resets[#resets + 1] = section; end };
settings.window.tab = 'Profiles';
draw('Reset this section', services);
eq(called('Selectable', 'Reset this section'), false, 'Profiles does not offer a reset that has no effect');
eq(#resets, 0, 'Profiles cannot call the unsupported reset service');
eq(called('Selectable', 'Reset layout'), true, 'The separately confirmed full-layout reset remains available');
MOCK.clicks['Reset this section'] = nil;
for _, tab in ipairs({ { 'Display', 'display' }, { 'Tracking', 'tracking' }, { 'Dynamis', 'dynamis' },
    { 'Events', 'events' }, { 'Details', 'planner' }, { 'Alerts', 'alerts' }, { 'Appearance', 'style' }, { 'Session', 'sessions' } }) do
    settings.window.tab = tab[1];
    draw('Reset this section', services);
    eq(called('Selectable', 'Reset this section'), true, tab[1] .. ' retains its supported reset');
    eq(resets[#resets], tab[2], tab[1] .. ' resets the intended settings section');
end
return { count = count };
