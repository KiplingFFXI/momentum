local palette = {};
local names = { 'background', 'card', 'control', 'hover', 'border', 'text', 'heading', 'muted', 'accent', 'accent_hover', 'success' };
local values = {
    ['Phoenix'] = { '180e0e', '291c1c', '321f1f', '3a2525', 'd2abab', 'fff8f8', 'd2abab', '8a6b6b', 'c55151', 'ff8d79', '63ba8a', 0.96, 0.20 },
    ['Classic FFXI'] = { '0b1a3d', '13275a', '1b3470', '27468c', '8ea3d6', 'ffffff', 'f2e6c4', '9fb0d8', 'e8c86a', 'ffe08a', '7ee08a', 0.94, 0.55 },
    ['Minimal'] = { '1e1e1e', '2a2a2a', '333333', '404040', 'ffffff', 'f2f2f2', 'cfcfcf', '8c8c8c', 'd0d0d0', 'ffffff', '9be3b5', 0.96, 0.15 },
    ['High contrast'] = { '000000', '141414', '262626', '3d3d3d', 'ffffff', 'ffffff', 'ffe066', 'c8c8c8', 'ffd000', 'ffe866', '39ff14', 1, 0.70 },
    ['Ember'] = { '1a120c', '2a1d12', '3a2716', '4a321c', 'ffb070', 'fff4e8', 'ffc38a', 'a07c5c', 'e8742a', 'ffa04d', '8fcf6a', 0.96, 0.25 },
    ['Mint'] = { '101f1b', '192f29', '233d34', '2e5446', '8fe3ba', 'edf9f1', 'b1ebd0', '9bbbad', '74d9ad', 'a4edcc', '8fe3b7', 0.96, 0.35 },
    ['Lavender'] = { '191523', '262033', '342b45', '463858', 'cdb1f4', 'f3ecff', 'deccf7', 'b5a5c9', 'c3a0ed', 'e4ccff', 'a8d9c0', 0.96, 0.35 },
    ['Colorblind safe'] = { '101418', '1b2129', '252d37', '313b47', '56b4e9', 'f2f2f2', '9fd3f5', '8f9aa6', '56b4e9', '9fd3f5', '56b4e9', 0.96, 0.30 },
};

local function rgba(hex, alpha)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255, alpha or 1 };
end

local function same(actual, expected, message)
    assert(type(actual) == 'table', message .. ' is missing');
    for channel = 1, 4 do
        assert(type(actual[channel]) == 'number' and math.abs(actual[channel] - expected[channel]) < 0.00001, message .. ' differs');
    end
end

local function packed(value, opacity)
    return math.floor(value[1] * 255 + 0.5) + math.floor(value[2] * 255 + 0.5) * 256
        + math.floor(value[3] * 255 + 0.5) * 65536 + math.floor(value[4] * (opacity or 1) * 255 + 0.5) * 16777216;
end

function palette.prepare(settings)
    local name = PREVIEW.palette_name or 'Phoenix';
    local source, window = assert(values[name], 'Unknown palette fixture'), {};
    for index, key in ipairs(names) do window[key] = rgba(source[index]); end
    window.background[4], window.border[4] = source[12], source[13];
    local hud = { background = window.card, fill = window.accent, lp_fill = window.success,
        text = window.text, label = window.heading, divider = window.muted, border = window.border,
        chain = window.accent_hover, warning = window.accent_hover };
    if name == 'Phoenix' then
        hud.lp_fill, hud.divider, hud.chain = rgba('9fe0bc'), rgba('a88a8a'), rgba('f5c850');
    elseif name == 'High contrast' then
        hud.background, hud.lp_fill, hud.chain, hud.warning = rgba('000000'), rgba('ffffff'), rgba('ffffff'), rgba('00a8ff');
    elseif name == 'Colorblind safe' then
        hud.lp_fill, hud.chain, hud.warning = rgba('f0e442'), rgba('9fd3f5'), rgba('e69f00');
    elseif name == 'Mint' or name == 'Lavender' then
        hud.warning = rgba('ff8d79');
    end
    PREVIEW.palette_expected = { hud = hud, window = window, order = table.concat(settings.display.order, ',') };
    assert(require('ui.theme').apply(settings, name), 'Theme could not be selected');
    local imgui, begin = require('imgui'), require('imgui').Begin;
    local roles = {
        { 'background', ImGuiCol_WindowBg }, { 'card', ImGuiCol_TitleBgActive }, { 'card', ImGuiCol_PopupBg },
        { 'control', ImGuiCol_FrameBg }, { 'hover', ImGuiCol_FrameBgHovered }, { 'text', ImGuiCol_Text },
        { 'border', ImGuiCol_Border }, { 'accent', ImGuiCol_CheckMark }, { 'muted', ImGuiCol_TextDisabled },
    };
    imgui.Begin = function(title, ...)
        if title == 'Momentum##settings' then
            PREVIEW.palette_window_seen = true;
            for _, role in ipairs(roles) do
                same({ imgui.GetStyleColorVec4(role[2]) }, window[role[1]], 'Rendered window ' .. role[1]);
            end
        end
        return begin(title, ...);
    end;
end

function palette.check(settings)
    local expected, p = PREVIEW.palette_expected, PREVIEW_PY;
    for key, value in pairs(expected.hud) do same(settings.style.colors[key], value, 'HUD ' .. key); end
    for key, value in pairs(expected.window) do same(settings.style.window_colors[key], value, 'Window ' .. key); end
    assert(PREVIEW.palette_window_seen, 'Palette was never applied to an actual settings window');
    assert(require('ui.theme').current(settings) == (PREVIEW.palette_name or 'Phoenix'), 'Selected palette is marked custom');
    assert(table.concat(settings.display.order, ',') == expected.order, 'Theme changed readout order');
    local background, progress, value, label = false, false, false, false;
    local x, y, width, height = p.window_x('##momentum_bar'), p.window_y('##momentum_bar'),
        p.window_width('##momentum_bar'), p.window_height('##momentum_bar');
    local progress_color = packed(PREVIEW.view.mode == 'lp' and expected.hud.lp_fill or expected.hud.fill);
    for _, rect in ipairs(p.hud_rects()) do
        if rect.x == x and rect.y == y and rect.width == width and rect.height == height then
            assert(rect.color == packed(expected.hud.background, settings.style.opacity), 'Drawn background differs from the palette');
            background = true;
        end
        if rect.height == 2 and rect.width > 0 and rect.color == progress_color then progress = true; end
    end
    for _, run in ipairs(p.hud_runs()) do
        if run.kind == 'text' and run.color == packed(expected.hud.text) then value = true; end
        if run.kind == 'text' and run.color == packed(expected.hud.label) then label = true; end
    end
    assert(background and progress and value and label, 'Expected palette colors were not sent to the HUD draw list');
end

return palette;
