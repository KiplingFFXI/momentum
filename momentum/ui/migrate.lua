local migrate = {};
local theme = require('ui.theme');

local old_style = { font = 'Ashita', font_size = 16, rounding = 0, opacity = 0.9, border = true, text_shadow = true };
local compact_style = { font_size = 14, rounding = 8, opacity = 0.94 };
local retired_bar = { 'full_width', 'chat_width', 'chat_left', 'chat_right', 'chat_screen',
    'chat_top', 'chat_bottom', 'chat_height', 'avoid_chat', 'padding' };
local old_enabled = {
    job = true, progress = true, remaining = true, rate = true, eta = true, chain = true, last = true,
    chain_time = false, percent = false, merits = false, merit_rate = false, goal = false, buffer = false,
    session = false, net = false, elapsed = false, average = false, best_chain = false, dedication = false, status = false,
};
local old_colors = {
    background = { 0.09, 0.05, 0.05, 1 }, fill = { 0.48, 0.17, 0.18, 1 }, lp_fill = { 0.15, 0.35, 0.29, 1 },
    text = { 1, 0.97, 0.97, 1 }, label = { 0.83, 0.68, 0.68, 1 }, divider = { 0.73, 0.59, 0.59, 1 },
    border = { 0.82, 0.67, 0.67, 0.4 }, chain = { 0.96, 0.78, 0.31, 1 }, warning = { 1, 0.55, 0.47, 1 },
};

local function rgb(red, green, blue, alpha)
    return { red / 255, green / 255, blue / 255, alpha or 1 };
end

local old_palette = {
    background = rgb(24, 14, 14), fill = rgb(123, 43, 46), lp_fill = rgb(38, 91, 73),
    text = rgb(255, 248, 248), label = rgb(210, 171, 171), divider = rgb(179, 147, 147),
    chain = rgb(245, 200, 80), warning = rgb(255, 141, 121), border = rgb(179, 147, 147, 0.45),
};
local compact_palette = {
    background = rgb(16, 18, 22), fill = rgb(105, 47, 54), lp_fill = rgb(37, 72, 63),
    text = rgb(240, 242, 245), label = rgb(170, 176, 188), divider = rgb(89, 97, 110),
    chain = rgb(227, 188, 116), warning = rgb(239, 155, 129), border = rgb(59, 65, 75, 0.35),
};
local prior_palettes = {
    ['Phoenix'] = { '0d1219', 'e7b15e', '67cdb8', 'f4f6fa', '9da9b7', '334151', '8fd6c5', 'f1bd79' },
    ['Classic FFXI'] = { '0b1a3d', '294887', '345963', 'ffffff', 'f2e6c4', '8ea3d6', 'ffe08a', 'ffb7a3' },
    ['Minimal'] = { '171717', '3e454c', '374a45', 'f2f2f2', 'cecece', '888888', 'eeeeee', 'ffd08a' },
    ['High contrast'] = { '000000', '303030', '203820', 'ffffff', 'ffffff', 'ffffff', 'ffd000', 'ff9655' },
    ['Ember'] = { '1a120c', '70401c', '455a2c', 'fff4e8', 'ffc38a', 'b98a62', 'ffb35c', 'ff9686' },
    ['Mint'] = { '101f1b', '275342', '245866', 'edf9f1', 'b1ebd0', '83bfa5', 'a4edcc', 'ffb39b' },
    ['Lavender'] = { '191523', '514064', '354f55', 'f3ecff', 'deccf7', 'ae93c7', 'e4ccff', 'ffc08c' },
    ['Colorblind safe'] = { '101418', '254c68', '644818', 'ffffff', 'b7dbf1', '83bddd', '56b4e9', 'e69f00' },
};

local function hex_color(hex, alpha)
    return rgb(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), alpha);
end

local function prior_colors(name)
    local palette = prior_palettes[name];
    if not palette then return nil; end
    local result = {};
    for index, key in ipairs({ 'background', 'fill', 'lp_fill', 'text', 'label', 'divider', 'chain', 'warning' }) do
        result[key] = hex_color(palette[index]);
    end
    result.border = name == 'Phoenix' and hex_color('3a4657', 0.4)
        or hex_color(palette[6], name == 'High contrast' and 1 or 0.45);
    return result;
end

local function replace_defaults(target, old, fresh)
    if type(target) ~= 'table' or type(fresh) ~= 'table' then return; end
    for key, value in pairs(old) do
        if target[key] == value and fresh[key] ~= nil then target[key] = fresh[key]; end
    end
end

local function same_enabled(value, fresh)
    if type(value) ~= 'table' then return false; end
    for key, enabled in pairs(old_enabled) do
        if value[key] ~= enabled then return false; end
    end
    for key, enabled in pairs(value) do
        if old_enabled[key] == nil and (enabled ~= false or fresh[key] ~= false) then return false; end
    end
    return true;
end

local function same_color(value, old)
    if type(value) ~= 'table' or type(old) ~= 'table' then return false; end
    for index = 1, 4 do
        if type(value[index]) ~= 'number' or value[index] ~= value[index]
            or math.abs(value[index] - old[index]) > 0.000001 then return false; end
    end
    return true;
end

local function migrate_bar(bar, fresh, first_version)
    if type(bar) ~= 'table' or type(fresh) ~= 'table' then return; end
    local fixed_width = bar.docked == false or bar.chat_width == false or (first_version and bar.full_width == false);
    replace_defaults(bar, { height = first_version and 36 or 24 }, fresh);
    if bar.docked ~= false then
        if bar.chat_width == true then
            bar.x, bar.bottom, bar.width = fresh.x, fresh.bottom, fresh.width;
        else
            replace_defaults(bar, { x = first_version and 100 or 10, bottom = 0 }, fresh);
            if first_version and not fixed_width then replace_defaults(bar, { width = 900 }, fresh); end
        end
    end
    if fixed_width then
        bar.auto_width = false;
    elseif bar.auto_width == nil then
        bar.auto_width = fresh.auto_width;
    end
    if bar.avoid_chat == false then
        bar.hide_typing = false;
    elseif bar.hide_typing == nil then
        bar.hide_typing = fresh.hide_typing;
    end
    for _, key in ipairs(retired_bar) do bar[key] = nil; end
end

local function migrate_appearance(settings, fresh)
    local version = tonumber(settings.appearance_version);
    if version and version >= 2 then return false; end
    local first_version = not version or version ~= version or version < 1;

    migrate_bar(settings.bar, fresh.bar, first_version);
    replace_defaults(settings.style, first_version and old_style or compact_style, fresh.style);
    if type(settings.style) == 'table' and settings.style.fill_style == nil and type(fresh.style) == 'table' then
        settings.style.fill_style = fresh.style.fill_style;
    end

    local display = settings.display;
    if type(display) == 'table' and type(fresh.display) == 'table' then
        replace_defaults(display, { spacing = first_version and 4 or 0, divider = ' | ' }, fresh.display);
        if type(display.labels) == 'table' and type(fresh.display.labels) == 'table'
            and (display.labels.remaining == 'To go' or display.labels.remaining == 'Left') then
            display.labels.remaining = fresh.display.labels.remaining;
        end
        if first_version and same_enabled(display.enabled, fresh.display.enabled) then
            display.enabled.eta, display.enabled.last = false, false;
        end
    end

    local style = settings.style;
    if type(style) == 'table' and style.preset == 'Phoenix' and type(style.colors) == 'table'
        and type(fresh.style) == 'table' and type(fresh.style.colors) == 'table' then
        for key, old in pairs(first_version and old_colors or compact_palette) do
            local color = style.colors[key];
            local replacement = fresh.style.colors[key];
            if type(replacement) == 'table' and (same_color(color, old)
                or (first_version and same_color(color, old_palette[key]))) then
                style.colors[key] = { replacement[1], replacement[2], replacement[3], replacement[4] };
            end
        end
    end

    settings.appearance_version = 2;
    return true;
end

local function migrate_palette(settings, fresh)
    local style = settings.style;
    if type(style) ~= 'table' or type(fresh.style) ~= 'table' then return false; end
    local version = tonumber(style.palette_version);
    if version and version >= 1 then return false; end
    local old, colors = prior_colors(style.preset), theme.colors(style.preset);
    if old and type(style.colors) == 'table' then
        for key, value in pairs(old) do
            if same_color(style.colors[key], value) then style.colors[key] = colors[key]; end
        end
    end
    local windows = theme.window_colors(style.preset);
    local merged = fresh.style.window_colors or {};
    style.window_colors = type(style.window_colors) == 'table' and style.window_colors or {};
    for key, value in pairs(windows) do
        if style.window_colors[key] == nil or same_color(style.window_colors[key], merged[key]) then
            style.window_colors[key] = value;
        end
    end
    style.palette_version = 1;
    return true;
end

-- Update untouched defaults once. Keep saved custom choices.
function migrate.apply(settings, fresh)
    if type(settings) ~= 'table' or type(fresh) ~= 'table' then return false; end
    local changed = migrate_appearance(settings, fresh);
    return migrate_palette(settings, fresh) or changed;
end

return migrate;
