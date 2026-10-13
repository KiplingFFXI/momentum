local imgui = require('imgui');
local begin_child = imgui.BeginChild;
imgui.BeginChild = function(name, ...)
    if name == '##readout_order' and not PREVIEW.readout_list_scrolled then
        imgui.SetScrollHereY(0);
        PREVIEW.readout_list_scrolled = true;
    end
    return begin_child(name, ...);
end;
local selectable = imgui.Selectable;
imgui.Selectable = function(label, ...)
    local chosen = selectable(label, ...);
    if label:find('^%d%d  ') then
        local x, y = imgui.GetItemRectMin();
        local right, bottom = imgui.GetItemRectMax();
        PREVIEW.readout_rows = PREVIEW.readout_rows or {};
        PREVIEW.readout_rows[label] = { x = x, y = y, right = right, bottom = bottom };
    end
    return chosen;
end;
