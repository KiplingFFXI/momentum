local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local imgui = require('imgui');
local hud = require('ui.hud');
local window = require('ui.settings_window');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local settings = defaults.make();
settings.window.open = true;
MOCK.window_size = { 920, 660 };
local next_open, popup, input;
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function(label)
    if MOCK.clicks[label] then MOCK.clicks[label] = nil; return not next_open; end
    return next_open;
end;
imgui.BeginCombo = function(label, current)
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'BeginCombo', label, current };
    return true;
end;
imgui.OpenPopup = function(id) popup = id; end;
imgui.BeginPopup = function(id) return popup == id; end;
imgui.CloseCurrentPopup = function() popup = nil; end;
imgui.InputTextWithHint = function(label, _, value)
    if input and input[1] == label then value[1] = input[2]; input = nil; return true; end
    return false;
end;
local previews;
hud.draw_inline = function(_, _, _, _, context)
    previews[#previews + 1] = context;
    return { overflow = false, preview_clipped = false };
end;
local function draw(click)
    MOCK.imgui_calls, previews = {}, {};
    if click then MOCK.clicks[click] = true; end
    window.draw(settings, readouts.sample('Leveling'), {});
end
local function call(name, label)
    for _, item in ipairs(MOCK.imgui_calls) do if item[1] == name and item[2] == label then return item; end end
end
draw();
eq(call('BeginCombo', '##Readout list')[3], 'Shown only', 'Chosen readouts are the default list');
eq(call('Selectable', '05  Time to next level or merit'), nil, 'Unchosen readouts stay out of the initial list');
eq(call('BeginCombo', '##Starter layout')[3], 'Leveling', 'Fresh default is recognized as Leveling');
eq(call('Button', 'Preview##page'), nil, 'Preview is no longer a separate tab');

local order = table.concat(settings.display.order, ',');
settings.display.labels.chain_time = 'My chain';
draw('Add readout');
for _, category in ipairs({ 'Progress', 'Merit points and LP', 'Session', 'Buffs', 'Detailed statistics' }) do
    eq(call('TextDisabled', category) ~= nil, true, 'Catalog includes ' .. category);
end
local entries = 0;
for _, item in ipairs(MOCK.imgui_calls) do if item[1] == 'Selectable' and item[2]:find('##add_', 1, true) then entries = entries + 1; end end
eq(entries, #defaults.READOUTS, 'Catalog includes every readout exactly once');
for _, item in ipairs(defaults.READOUTS) do eq(call('Selectable', item.name .. '##add_' .. item.id) ~= nil, true, 'Catalog exposes ' .. item.id); end
draw('EXP chain timer##add_chain_time');
eq(settings.display.enabled.chain_time, true, 'Catalog selection enables the chosen readout');
eq(settings.display.labels.chain_time, 'My chain', 'Adding retains its saved custom label');
eq(table.concat(settings.display.order, ','), order, 'Adding does not reorder the bar');
eq(popup, nil, 'Adding closes the catalog');
eq(call('BeginCombo', '##Starter layout')[3], 'Custom', 'Custom selection is not mislabeled as a starter');
eq(call('Checkbox', 'Keep visible first'), nil, 'Advanced pin control is initially folded');
eq(call('Checkbox', 'Divider before this readout') ~= nil, true, 'Divider remains in the basic editor');
eq(call('ColorEdit4', 'Below 10 seconds') ~= nil, true, 'Chain warning color remains in the basic editor');
draw('More options (?)##section_Display/More options');
eq(call('Checkbox', 'Keep visible first') ~= nil, true, 'More options exposes pinning');
eq(call('SliderFloat', '##Display priority') ~= nil, true, 'More options exposes numeric priority');
draw('Keep visible first');
eq(settings.display.pinned.chain_time, true, 'Pinning retains the existing saved setting');

draw('Sample');
eq(previews[1].preview, true, 'Local sample selector changes the settings preview');
eq(settings.preview.show, false, 'Local sample selector leaves the game bar live');
draw('Merits');
eq(settings.preview.scenario, 'Merits', 'Sample scenario is selectable');
eq(settings.preview.show, false, 'Changing the sample does not enable it on the game bar');
draw('Preview options');
draw('Show sample on game bar');
eq(settings.preview.show, true, 'Explicit option enables the game sample');
draw('Narrow width test##narrow_preview');
eq(#previews, 2, 'Expanded narrow test adds one preview');
eq(previews[2].preview, true, 'Narrow test uses explicit sample mode');
eq(previews[2].width, 280, 'Narrow test simulates a fixed width');
eq(settings.bar.width, 640, 'Narrow test does not resize the game bar');
popup = nil;
draw('Live');
eq(previews[1].preview, false, 'Local Live returns to actual character data');
eq(settings.preview.show, true, 'Local preview does not silently alter the explicit game sample toggle');

settings.preview.show = false;
settings.window.tab = 'Preview';
draw();
eq(settings.window.tab, 'Display', 'Legacy saved Preview tab opens Display');
eq(previews[1].preview, true, 'Legacy Preview opens sample tools');
eq(popup, '##preview_options', 'Legacy Preview keeps sample options reachable');
eq(settings.preview.show, false, 'Legacy Preview migration does not replace game readings');
popup = nil;
input = { '##Find settings', 'priority' };
draw('Display: More options##find');
eq(call('Checkbox', 'Keep visible first') ~= nil, true, 'Search opens the nested advanced controls');
return { count = count };
