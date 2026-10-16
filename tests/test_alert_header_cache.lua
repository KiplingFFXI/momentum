local imgui = require('imgui');
local defaults = require('ui.defaults');
local window = require('ui.settings_window');
local readouts = require('ui.readouts');
local count, measured, markers, labels = 0, 0, 0, {};
local width, font, size, next_open = 380, 'Font A', 28, false;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local settings = defaults.make();
settings.window.open, settings.window.tab = true, 'Alerts';
imgui.GetContentRegionAvail = function() return width, 600; end;
imgui.GetFont = function() return font; end;
imgui.GetFontSize = function() return size; end;
imgui.GetFrameHeight = function() return size + 4; end;
imgui.CalcTextSize = function(text)
    if text:find(' on)', 1, true) then measured = measured + 1; end
    if text == '(?)' then markers = markers + 1; end
    return #text * size / 2, size;
end;
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function(label)
    local key = label:match('##section_Alerts/(.*)');
    if key then labels[key] = label; end
    return next_open;
end;
local function draw() window.draw(settings, readouts.sample(), {}); end
draw();
local initial = measured;
eq(markers, 1, 'All help markers share one text measurement');
eq(initial > 6, true, 'Narrow alert headings are measured and shortened initially');
eq(labels['Levels and merit points']:find('...', 1, true) ~= nil, true, 'Long heading is shortened');
eq(labels['Levels and merit points']:find('(0 on)', 1, true) ~= nil, true, 'Shortened heading keeps its count');
for _ = 1, 120 do draw(); end
eq(measured, initial, 'Stable headings do not repeat text measurement');
eq(markers, 1, 'Stable settings do not remeasure help markers');
settings.alerts.food_enabled = true;
draw();
eq(labels.Food, 'Food (1 on) (?)###section_Alerts/Food', 'Count changes immediately without changing the section ID');
eq(measured, initial + 1, 'Changing one count measures only that heading');
local before = measured;
width = 900;
draw();
eq(measured, before + 7, 'Wider available space recalculates all counted headings once');
eq(markers, 1, 'Window width does not change the help marker width');
eq(labels['Levels and merit points'], 'Levels and merit points (0 on) (?)###section_Alerts/Levels and merit points', 'Wider space restores the full title');
before, font = measured, 'Font B';
draw();
eq(measured, before + 7, 'Font identity changes invalidate all seven headings');
eq(markers, 2, 'Changing fonts remeasures the help marker');
before, size = measured, 18;
draw();
eq(measured, before + 7, 'Font size changes invalidate all seven headings');
eq(markers, 3, 'Changing font size remeasures the help marker');
before = measured;
for _ = 1, 120 do draw(); end
eq(measured, before, 'Updated headings also become reusable');
eq(markers, 3, 'Updated help marker measurement stays reusable');
settings.window.sections['Alerts/Food'] = true;
draw();
eq(labels.Food, 'Food (1 on) (?)###section_Alerts/Food', 'Opening the group preserves its count and ID');
eq(measured, before, 'Group fold state does not invalidate title measurements');
return { count = count };
