local imgui = require('imgui');
local checkbox = imgui.Checkbox;
imgui.Checkbox = function(label, ...)
    local changed = checkbox(label, ...);
    if label:find('Switch saved EXP / Merits layouts', 1, true) then
        PREVIEW.auto_label = label;
        if PREVIEW.auto_reveal then imgui.SetScrollHereY(0.5); end
    end
    return changed;
end;
local button = imgui.Button;
imgui.Button = function(label, ...)
    if label == 'Display: Readouts and order##find' then PREVIEW.auto_found = true; end
    return button(label, ...);
end;
