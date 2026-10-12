local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local imgui = require('imgui');
local hud = require('ui.hud');
local window = require('ui.settings_window');
local count = 0;
local function eq(actual, expected, title)
    count = count + 1;
    assert(actual == expected, title .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local settings = defaults.make();
settings.window.open = true;
local view = readouts.sample('Leveling');
local input, next_open, sections, sequence = {}, nil, {}, {};
local fit = { overflow = false, preview_clipped = false };
imgui.InputTextWithHint = function(label, _, value)
    if input[label] ~= nil then value[1], input[label] = input[label], nil; return true; end
    return false;
end;
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function(label) sections[label:match('##section_(.*)')] = next_open; return next_open; end;
imgui.BeginCombo = function() return true; end;
local begin_child = imgui.BeginChild;
imgui.BeginChild = function(label, ...)
    sequence[#sequence + 1] = label;
    return begin_child(label, ...);
end;
local context = { chat = { width = 600 }, now = 42 };
hud.draw_inline = function(_, _, _, _, actual_context)
    sequence[#sequence + 1] = 'preview';
    eq(actual_context.chat, context.chat, 'Preview receives native chat context');
    return fit;
end;
local function draw(click)
    MOCK.imgui_calls, sections, sequence = {}, {}, {};
    if click then MOCK.clicks[click] = true; end
    window.draw(settings, view, { preview_context = function() return context; end });
end
local function called(name, label)
    for _, item in ipairs(MOCK.imgui_calls) do if item[1] == name and item[2] == label then return true; end end
    return false;
end
draw();
eq(sequence[1], 'preview', 'Preview renders before the scrolling page');
eq(sequence[2], '##momentum_page', 'Only page controls live in the scrolling child');
eq(called('TextDisabled', 'Show'), true, 'Show column is labeled once');
eq(called('TextDisabled', 'Divider'), true, 'Divider column is labeled once');
eq(called('Checkbox', '##divider_progress'), true, 'Divider keeps a readout-specific ID');
eq(called('Checkbox', 'Divider##divider_progress'), false, 'Rows do not repeat the divider label');

settings.display.enabled.progress = false;
settings.display.enabled.rate = false;
draw('Shown only');
eq(called('Selectable', '02  EXP / LP progress'), false, 'Shown filter hides a disabled readout');
eq(called('Selectable', '03  TNL / LP needed'), true, 'Shown filter keeps enabled readouts');
local original = table.concat(settings.display.order, ',');
draw('Down##order');
eq(table.concat(settings.display.order, ','), original, 'Filtered-out selection cannot reorder anything');
draw('03  TNL / LP needed');
draw('Up##order');
eq(settings.display.order[1], 'remaining', 'Filtered Up moves relative to previous listed readout');
eq(settings.display.order[3], 'progress', 'Unlisted readout stays in the full order');
draw('Down##order');
eq(settings.display.order[1], 'job', 'Filtered Down moves after the next listed readout');
eq(settings.display.order[2], 'remaining', 'Filtered Down inserts immediately after that row');
eq(settings.display.order[3], 'progress', 'Moving shown rows preserves the hidden rows relative order');
input['##Filter readouts'] = 'chain';
draw('All readouts');
eq(called('Selectable', '01  Job and level'), false, 'Local text filter hides unrelated rows');
eq(called('Selectable', '07  EXP chain timer'), true, 'Local text filter finds chain countdown');
draw('07  EXP chain timer');
settings.display.colors.chain_time = { 0.1, 0.2, 0.3, 1 };
draw();
eq(called('ColorEdit4', 'Value color'), true, 'Selected countdown exposes its normal value color');
eq(called('ColorEdit4', 'Below 10 seconds'), true, 'Selected countdown exposes warning color beside normal controls');
local warning;
for _, item in ipairs(MOCK.imgui_calls) do if item[1] == 'ColorEdit4' and item[2] == 'Below 10 seconds' then warning = item[3]; end end
eq(warning, settings.style.colors.chain_ending, 'Warning picker edits the existing saved color');

settings.window.sections['Display/Readouts and order'] = false;
settings.window.sections['Display/Position and size'] = true;
input['##Find settings'] = 'order';
draw();
eq(sections['Display/Readouts and order'], true, 'Search opens a relevant section');
eq(sections['Display/Position and size'], false, 'Search does not expand unrelated sections');
eq(settings.window.sections['Display/Position and size'], true, 'Search keeps the saved expanded state');
input['##Find settings'] = 'font';
draw('Appearance: Skin and text##find');
eq(settings.window.tab, 'Appearance', 'Search result opens its destination tab');
eq(sections['Appearance/Skin and text'], true, 'Search opens the destination section');
eq(sections['Appearance/Bar colors'], false, 'Search keeps other destination sections folded');
eq(called('SetScrollHereY', 0), true, 'Choosing a search result scrolls to its header');
input['##Find settings'] = '';
settings.window.tab = 'Display';
draw();
eq(sections['Display/Readouts and order'], false, 'Clearing search restores saved collapsed section');
eq(sections['Display/Position and size'], true, 'Clearing search restores saved open section');

fit = { overflow = false, preview_clipped = true };
draw();
eq(called('TextUnformatted', 'Your bar fits. This window shows only part of the preview.'), true, 'Preview crop is not reported as bar overflow');
fit = { overflow = true, hidden_count = 2 };
draw();
eq(called('TextUnformatted', '2 readouts are hidden at the current bar width. Hover ... on the bar for their values.'), true, 'Actual overflow reports hidden readout count');
return { count = count };
