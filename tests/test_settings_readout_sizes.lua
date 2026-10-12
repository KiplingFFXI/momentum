local defaults = require('ui.defaults');
local window = require('ui.settings_window');
local readouts = require('ui.readouts');
local imgui = require('imgui');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local settings = defaults.make();
settings.window.open, settings.window.tab = true, 'Display';
local open, measures, wrapped, width, font, font_size = false, 0, 0, 500, 'Font A', 18;
local measure = imgui.CalcTextSize;
imgui.SetNextItemOpen = function(value) open = value; end;
imgui.CollapsingHeader = function() return open; end;
imgui.GetContentRegionAvail = function() return width, 500; end;
imgui.GetFont = function() return font; end;
imgui.GetFontSize = function() return font_size; end;
imgui.CalcTextSize = function(text, hidden, wrap)
    if text:find('^%d%d  ') then
        measures = measures + 1;
        if wrap then wrapped = wrapped + 1; return wrap, font_size * 2; end
    end
    return measure(text, hidden, wrap);
end;
local function draw() window.draw(settings, readouts.sample('Leveling'), {}); end
draw();
local initial = measures;
eq(initial > 0, true, 'Visible readout labels are measured initially');
eq(wrapped, 0, 'Fitting labels do not request wrapped measurement');
for _ = 1, 120 do draw(); end
eq(measures, initial, 'Idle settings reuse readout measurements');
width = 80;
draw();
eq(measures > initial, true, 'Narrowing the window recalculates row sizes');
eq(wrapped > 0, true, 'Long labels request wrapped height at narrow widths');
local narrow = measures;
draw();
eq(measures, narrow, 'Stable narrow rows also reuse measurements');
font_size = 28;
draw();
eq(measures > narrow, true, 'Actual font size changes invalidate row height');
local large = measures;
font = 'Font B';
draw();
eq(measures > large, true, 'Actual font identity changes invalidate row width');
local before = measures;
settings.display.order[1], settings.display.order[2] = settings.display.order[2], settings.display.order[1];
draw();
eq(measures, before + 4, 'Reordering recalculates only the two changed numbered labels');
local stable = measures;
draw();
eq(measures, stable, 'New row order becomes reusable');
return { count = count };
