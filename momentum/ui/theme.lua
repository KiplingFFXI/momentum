local theme = {};

local function color(hex, alpha)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, alpha or 1 };
end

local function alpha(value, amount)
    return { value[1], value[2], value[3], amount };
end

theme.names = { 'Phoenix', 'Classic FFXI', 'Minimal', 'High contrast', 'Ember', 'Mint', 'Lavender', 'Colorblind safe' };
theme.WINDOW_COLORS = {
    { 'background', 'Window background' }, { 'card', 'Title and popup background' }, { 'control', 'Buttons and sliders' }, { 'hover', 'Buttons and sliders on hover' },
    { 'border', 'Window border' }, { 'text', 'Window text' }, { 'heading', 'Headings' }, { 'muted', 'Unavailable option text' },
    { 'accent', 'Highlight' }, { 'accent_hover', 'Bright highlight' }, { 'success', 'Success' },
};

local palettes = {
    ['Phoenix'] = { '180e0e', '291c1c', '321f1f', '3a2525', 'd2abab', 'fff8f8', 'd2abab', '8a6b6b', 'c55151', 'ff8d79', '63ba8a', 0.96, 0.20 },
    ['Classic FFXI'] = { '0b1a3d', '13275a', '1b3470', '27468c', '8ea3d6', 'ffffff', 'f2e6c4', '9fb0d8', 'e8c86a', 'ffe08a', '7ee08a', 0.94, 0.55 },
    ['Minimal'] = { '1e1e1e', '2a2a2a', '333333', '404040', 'ffffff', 'f2f2f2', 'cfcfcf', '8c8c8c', 'd0d0d0', 'ffffff', '9be3b5', 0.96, 0.15 },
    ['High contrast'] = { '000000', '141414', '262626', '3d3d3d', 'ffffff', 'ffffff', 'ffe066', 'c8c8c8', 'ffd000', 'ffe866', '39ff14', 1, 0.70 },
    ['Ember'] = { '1a120c', '2a1d12', '3a2716', '4a321c', 'ffb070', 'fff4e8', 'ffc38a', 'a07c5c', 'e8742a', 'ffa04d', '8fcf6a', 0.96, 0.25 },
    ['Mint'] = { '101f1b', '192f29', '233d34', '2e5446', '8fe3ba', 'edf9f1', 'b1ebd0', '9bbbad', '74d9ad', 'a4edcc', '8fe3b7', 0.96, 0.35 },
    ['Lavender'] = { '191523', '262033', '342b45', '463858', 'cdb1f4', 'f3ecff', 'deccf7', 'b5a5c9', 'c3a0ed', 'e4ccff', 'a8d9c0', 0.96, 0.35 },
    ['Colorblind safe'] = { '101418', '1b2129', '252d37', '313b47', '56b4e9', 'f2f2f2', '9fd3f5', '8f9aa6', '56b4e9', '9fd3f5', '56b4e9', 0.96, 0.30 },
};

function theme.window_colors(name)
    local palette = palettes[name] or palettes.Phoenix;
    local result = {};
    for i, entry in ipairs(theme.WINDOW_COLORS) do result[entry[1]] = color(palette[i]); end
    result.background[4], result.border[4] = palette[12], palette[13];
    return result;
end

function theme.colors(name)
    if not palettes[name] then name = 'Phoenix'; end
    local c = theme.window_colors(name);
    local result = { background = c.card, fill = c.accent, lp_fill = c.success, text = c.text, label = c.heading,
        divider = c.muted, border = c.border, chain = c.accent_hover, chain_ending = color('ff5252'), warning = alpha(c.accent_hover, 1) };
    if name == 'Phoenix' then
        result.lp_fill, result.divider, result.chain = color('9fe0bc'), color('a88a8a'), color('f5c850');
    elseif name == 'High contrast' then
        result.background, result.lp_fill, result.chain, result.warning = color('000000'), color('ffffff'), color('ffffff'), color('00a8ff');
    elseif name == 'Colorblind safe' then
        result.lp_fill, result.chain, result.warning = color('f0e442'), color('9fd3f5'), color('e69f00');
    elseif name == 'Mint' or name == 'Lavender' then
        result.warning = color('ff8d79');
    end
    return result;
end

function theme.apply(settings, name)
    if not palettes[name] then return false; end
    settings.style.colors = theme.colors(name);
    settings.style.window_colors = theme.window_colors(name);
    settings.style.preset, settings.style.palette_version = name, 1;
    return true;
end

function theme.current(settings)
    local name = settings.style.preset;
    if not palettes[name] then return nil; end
    for section, expected in pairs({ colors = theme.colors(name), window_colors = theme.window_colors(name) }) do
        local saved = settings.style[section] or {};
        for key, value in pairs(expected) do
            if type(saved[key]) ~= 'table' then return nil; end
            for i = 1, 4 do
                if type(saved[key][i]) ~= 'number' or math.abs(saved[key][i] - value[i]) > 0.002 then return nil; end
            end
        end
    end
    return name;
end

function theme.u32(value, opacity)
    local imgui = require('imgui');
    return imgui.col32(math.floor(value[4] * (opacity or 1) * 255 + 0.5), math.floor(value[1] * 255 + 0.5),
        math.floor(value[2] * 255 + 0.5), math.floor(value[3] * 255 + 0.5));
end

local weights = { 0.2126, 0.7152, 0.0722 };
local function luminance(value)
    local result = 0;
    for i, weight in ipairs(weights) do
        local channel = value[i];
        result = result + weight * (channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4);
    end
    return result;
end

local function ratio(first, second)
    local a, b = luminance(first), luminance(second);
    return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
end

local function blend(front, back, opacity)
    return { front[1] * opacity + back[1] * (1 - opacity), front[2] * opacity + back[2] * (1 - opacity),
        front[3] * opacity + back[3] * (1 - opacity) };
end

local function readable_accent(c, amount)
    local function contrast(opacity)
        local background = blend(c.accent, c.background, opacity);
        return math.min(ratio(blend(c.text, background, c.text[4]), background),
            ratio(blend(c.heading, background, c.heading[4]), background));
    end
    local minimum = math.min(4.5, contrast(0));
    if contrast(amount) >= minimum then return alpha(c.accent, amount); end
    local low, high = 0, amount;
    for _ = 1, 12 do
        local middle = (low + high) / 2;
        if contrast(middle) >= minimum then low = middle; else high = middle; end
    end
    return alpha(c.accent, low);
end

local style_cache;
local function style_entries(settings)
    local c = settings.style.window_colors;
    local same = style_cache and style_cache.preset == settings.style.preset;
    if same then
        for _, entry in ipairs(theme.WINDOW_COLORS) do
            local value, saved = c[entry[1]], style_cache.colors[entry[1]];
            for i = 1, 4 do if value[i] ~= saved[i] then same = false; break; end end
            if not same then break; end
        end
    end
    if same then return style_cache.entries; end
    local phoenix = settings.style.preset == 'Phoenix';
    local grab = ratio(c.text, c.accent) >= 3 and c.accent or alpha(c.accent, 0.5);
    local pressed = readable_accent(c, phoenix and 1 or 0.40);
    local picked = readable_accent(c, phoenix and 0.45 or 0.15);
    local hovered = readable_accent(c, phoenix and math.min(0.70, pressed[4] * 0.85) or 0.40);
    local entries = {
        { ImGuiCol_WindowBg, c.background }, { ImGuiCol_ChildBg, { 0, 0, 0, 0 } }, { ImGuiCol_PopupBg, c.card },
        { ImGuiCol_Text, c.text }, { ImGuiCol_TextDisabled, c.muted }, { ImGuiCol_Border, c.border },
        { ImGuiCol_FrameBg, c.control }, { ImGuiCol_FrameBgHovered, c.hover }, { ImGuiCol_FrameBgActive, alpha(c.accent, 0.30) },
        { ImGuiCol_Button, c.control }, { ImGuiCol_ButtonHovered, c.hover }, { ImGuiCol_ButtonActive, pressed },
        { ImGuiCol_Header, picked }, { ImGuiCol_HeaderHovered, hovered }, { ImGuiCol_HeaderActive, pressed },
        { ImGuiCol_CheckMark, c.accent }, { ImGuiCol_SliderGrab, grab },
        { ImGuiCol_SliderGrabActive, phoenix and color('d45e5e') or grab },
        { ImGuiCol_TitleBg, c.card }, { ImGuiCol_TitleBgActive, c.card }, { ImGuiCol_TitleBgCollapsed, c.card },
        { ImGuiCol_Separator, phoenix and alpha(c.heading, 0.12) or c.border },
        { ImGuiCol_SeparatorHovered, c.accent_hover }, { ImGuiCol_SeparatorActive, c.accent },
        { ImGuiCol_ResizeGrip, c.hover }, { ImGuiCol_ResizeGripHovered, alpha(c.accent, 0.30) }, { ImGuiCol_ResizeGripActive, c.accent },
        { ImGuiCol_ScrollbarBg, phoenix and alpha(c.background, 1) or c.background }, { ImGuiCol_ScrollbarGrab, c.control },
        { ImGuiCol_ScrollbarGrabHovered, c.hover }, { ImGuiCol_ScrollbarGrabActive, c.accent },
        { ImGuiCol_TextSelectedBg, alpha(c.accent, 0.35) }, { ImGuiCol_DragDropTarget, c.accent },
        { ImGuiCol_NavCursor, c.accent },
    };
    local saved = {};
    for _, entry in ipairs(theme.WINDOW_COLORS) do
        local value = c[entry[1]];
        saved[entry[1]] = { value[1], value[2], value[3], value[4] };
    end
    for _, entry in ipairs(entries) do
        local value = entry[2];
        entry[2] = { value[1], value[2], value[3], value[4] };
    end
    style_cache = { preset = settings.style.preset, colors = saved, entries = entries };
    return entries;
end

function theme.push(settings)
    local imgui = require('imgui');
    local count = 0;
    for _, entry in ipairs(style_entries(settings)) do
        if entry[1] then imgui.PushStyleColor(entry[1], entry[2]); count = count + 1; end
    end
    return count;
end

return theme;
