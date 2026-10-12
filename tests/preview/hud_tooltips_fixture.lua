local imgui = require('imgui');
local begin_tip, end_tip = imgui.BeginTooltip, imgui.EndTooltip;
local plain, colored = imgui.TextUnformatted, imgui.TextColored;
local drawing_tip = false;
imgui.BeginTooltip = function (...)
    drawing_tip = begin_tip(...);
    return drawing_tip;
end;
imgui.EndTooltip = function (...)
    drawing_tip = false;
    return end_tip(...);
end;
imgui.TextUnformatted = function (text, ...)
    if drawing_tip then PREVIEW.tip = PREVIEW.tip .. '\n' .. text; end
    return plain(text, ...);
end;
imgui.TextColored = function (color, text, ...)
    if drawing_tip then PREVIEW.tip = PREVIEW.tip .. '\n' .. text; end
    return colored(color, text, ...);
end;
local draw = PREVIEW.draw;
return function ()
    PREVIEW.tip = '';
    MOCK.now = MOCK.now + 1 / 60;
    if PREVIEW.hidden then require('ui.hud').cancel_layout_gesture(); else draw(); end
end;
