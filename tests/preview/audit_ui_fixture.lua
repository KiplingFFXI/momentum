local imgui = require('imgui');
local begin = imgui.Begin;
imgui.Begin = function(name, ...)
    if name == 'Momentum##settings' then PREVIEW.audit_widgets = {}; end
    return begin(name, ...);
end;
for _, name in ipairs({ 'Button', 'Checkbox', 'Selectable' }) do
    local original = imgui[name];
    imgui[name] = function(label, ...)
        if PREVIEW.audit_widgets then PREVIEW.audit_widgets[label] = true; end
        return original(label, ...);
    end;
end

function PREVIEW.progress_fills(expected)
    local color = require('ui.theme').u32(PREVIEW.settings.style.colors.fill) % 4294967296;
    local count, width = 0, 0;
    for _, rect in ipairs(PREVIEW_PY.hud_rects()) do
        if rect.color == color then count, width = count + 1, width + rect.width; end
    end
    assert(count == expected, 'The displayed progress fill does not match the known timer: expected ' .. expected .. ', found ' .. count);
    return width;
end
