local defaults = require('ui.defaults');
local theme = require('ui.theme');
local imgui = require('imgui');
local count = 0;
local function check(value, label) count = count + 1; assert(value, label); end
local function luminance(c)
    local result = 0;
    for i, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
        local v = c[i];
        result = result + weight * (v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4);
    end
    return result;
end
local function ratio(a, b)
    local x, y = luminance(a), luminance(b);
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
end
local function blend(front, back)
    local a = front[4];
    return { front[1] * a + back[1] * (1 - a), front[2] * a + back[2] * (1 - a), front[3] * a + back[3] * (1 - a) };
end
local colors;
imgui.PushStyleColor = function(id, value) colors[id] = value; end;
local function push(settings)
    colors = {};
    local pushed = theme.push(settings);
    local actual = 0;
    for _ in pairs(colors) do actual = actual + 1; end
    check(pushed == actual, 'Style push count stays balanced');
    return colors;
end
local states = { ImGuiCol_Header, ImGuiCol_HeaderHovered, ImGuiCol_HeaderActive };
for _, name in ipairs(theme.names) do
    local settings = defaults.make();
    theme.apply(settings, name);
    local first = push(settings);
    for _, state in ipairs(states) do
        local background = blend(first[state], settings.style.window_colors.background);
        for _, text in ipairs({ 'text', 'heading' }) do
            check(ratio(blend(settings.style.window_colors[text], background), background) >= 4.4999,
                name .. ' ' .. text .. ' remains readable in section state ' .. state);
        end
    end
    check(theme.current(settings) == name, name .. ' saved palette is unchanged');
    local next_frame = push(settings);
    check(next_frame[ImGuiCol_HeaderHovered] == first[ImGuiCol_HeaderHovered], name .. ' reuses its derived colors');
    settings.style.window_colors.heading[1] = 0.7;
    local edited = push(settings);
    check(edited[ImGuiCol_HeaderHovered] ~= first[ImGuiCol_HeaderHovered], name .. ' reacts to an in-place color edit');
end
local settings = defaults.make();
settings.style.window_colors.background = { 1, 1, 1, 1 };
settings.style.window_colors.heading = { 0, 0, 0, 1 };
settings.style.window_colors.text = { 0, 0, 0, 1 };
settings.style.window_colors.accent = { 0, 0, 0, 1 };
local light = push(settings);
for _, state in ipairs(states) do
    check(ratio(settings.style.window_colors.text, blend(light[state], settings.style.window_colors.background)) >= 4.4999,
        'Dark custom text on a light background remains readable');
end
settings.style.window_colors.background = { 0.1, 0.1, 0.1, 1 };
settings.style.window_colors.heading = { 0.2, 0.2, 0.2, 0.7 };
settings.style.window_colors.text = { 0.3, 0.3, 0.3, 0.8 };
settings.style.window_colors.accent = { 1, 1, 1, 1 };
local low = push(settings);
for _, state in ipairs(states) do
    local background = blend(low[state], settings.style.window_colors.background);
    local base = ratio(blend(settings.style.window_colors.heading, settings.style.window_colors.background), settings.style.window_colors.background);
    check(ratio(blend(settings.style.window_colors.heading, background), background) >= math.min(4.5, base) - 0.0001,
        'Low-contrast custom heading is not made less readable');
end
settings = defaults.make();
local old = push(settings);
local replacement = defaults.make();
push(replacement);
settings.style.window_colors.text[1] = 0;
local current = push(replacement);
check(current[ImGuiCol_Text][1] == replacement.style.window_colors.text[1], 'Cached colors do not retain mutable old settings arrays');
local before = current[ImGuiCol_HeaderHovered];
replacement.style.preset = 'Minimal';
local preset = push(replacement);
check(preset[ImGuiCol_HeaderHovered] ~= before, 'Preset-specific style behavior invalidates the cache');
return { count = count };
