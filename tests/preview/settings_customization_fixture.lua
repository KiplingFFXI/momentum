local imgui = require('imgui');
local hud = require('ui.hud');
local begin = imgui.Begin;
imgui.Begin = function(name, ...)
    if name == 'Momentum##settings' then PREVIEW.rows, PREVIEW.sections, PREVIEW.colors, PREVIEW.inline_calls = {}, {}, {}, {}; end
    return begin(name, ...);
end;
local selectable = imgui.Selectable;
imgui.Selectable = function(label, ...)
    if PREVIEW.rows then PREVIEW.rows[label] = true; end
    return selectable(label, ...);
end;
local header = imgui.CollapsingHeader;
imgui.CollapsingHeader = function(label, ...)
    local open = header(label, ...);
    local key = label:match('##section_(.*)');
    if key then PREVIEW.sections[key] = open; end
    if PREVIEW.inspect and key == 'Display/Selected readout' then imgui.SetScrollHereY(0); end
    return open;
end;
local edit_color = imgui.ColorEdit4;
imgui.ColorEdit4 = function(label, ...)
    PREVIEW.colors[label] = true;
    return edit_color(label, ...);
end;
local inline = hud.draw_inline;
hud.draw_inline = function(...)
    local _, y = imgui.GetCursorScreenPos();
    PREVIEW.preview_y = y;
    local info = inline(...);
    PREVIEW.fit = info;
    local context = select(5, ...);
    PREVIEW.inline_calls[#PREVIEW.inline_calls + 1] = { info = info, preview = context and context.preview };
    return info;
end;
