local migrate = require('ui.migrate');
local defaults = require('ui.defaults');
local theme = require('ui.theme');
local profiles = require('ui.profiles');
local count = 0;
local function check(value, message)
    assert(value, message);
    count = count + 1;
end
local function same(left, right)
    if type(left) ~= type(right) then return false; end
    if type(left) ~= 'table' then return left == right; end
    for key, value in pairs(left) do if not same(value, right[key]) then return false; end end
    for key in pairs(right) do if left[key] == nil then return false; end end
    return true;
end
local function rgb(red, green, blue, alpha)
    return { red / 255, green / 255, blue / 255, alpha or 1 };
end

local raw = {
    background = { 0.09, 0.05, 0.05, 1 }, fill = { 0.48, 0.17, 0.18, 1 }, lp_fill = { 0.15, 0.35, 0.29, 1 },
    text = { 1, 0.97, 0.97, 1 }, label = { 0.83, 0.68, 0.68, 1 }, divider = { 0.73, 0.59, 0.59, 1 },
    border = { 0.82, 0.67, 0.67, 0.4 }, chain = { 0.96, 0.78, 0.31, 1 }, warning = { 1, 0.55, 0.47, 1 },
};
local palette = {
    background = rgb(24, 14, 14), fill = rgb(123, 43, 46), lp_fill = rgb(38, 91, 73),
    text = rgb(255, 248, 248), label = rgb(210, 171, 171), divider = rgb(179, 147, 147),
    chain = rgb(245, 200, 80), warning = rgb(255, 141, 121), border = rgb(179, 147, 147, 0.45),
};
local compact = {
    background = rgb(16, 18, 22), fill = rgb(105, 47, 54), lp_fill = rgb(37, 72, 63),
    text = rgb(240, 242, 245), label = rgb(170, 176, 188), divider = rgb(89, 97, 110),
    chain = rgb(227, 188, 116), warning = rgb(239, 155, 129), border = rgb(59, 65, 75, 0.35),
};
local retired = { 'full_width', 'chat_width', 'chat_left', 'chat_right', 'chat_screen',
    'chat_top', 'chat_bottom', 'chat_height', 'avoid_chat', 'padding' };
local function no_retired(bar)
    for _, key in ipairs(retired) do if bar[key] ~= nil then return false; end end
    return true;
end
local function legacy(version, colors)
    local s = defaults.make();
    s.appearance_version = version;
    s.bar.auto_width, s.bar.hide_typing, s.style.fill_style = nil, nil, nil;
    s.bar.full_width, s.bar.chat_width = version ~= 1, nil;
    s.bar.width, s.bar.height, s.bar.x, s.bar.padding, s.bar.bottom = 900, 36, 100, 10, 0;
    s.style.font, s.style.font_size, s.style.rounding, s.style.opacity = 'Ashita', 16, 0, 0.9;
    s.style.border, s.style.text_shadow = true, true;
    s.display.spacing, s.display.divider, s.display.labels.remaining = 4, ' | ', 'To go';
    s.display.enabled.eta, s.display.enabled.last = true, true;
    if version == 1 then
        s.bar.width, s.bar.height, s.bar.x, s.bar.padding = 640, 24, 10, 0;
        s.bar.chat_width, s.bar.avoid_chat = true, true;
        s.bar.chat_left, s.bar.chat_right, s.bar.chat_screen = 40, 1000, 1920;
        s.bar.chat_top, s.bar.chat_bottom, s.bar.chat_height = 760, 1080, 1080;
        s.style.font, s.style.font_size, s.style.rounding, s.style.opacity = 'Segoe UI', 14, 8, 0.94;
        s.style.border, s.style.text_shadow = false, false;
        s.display.spacing, s.display.labels.remaining = 0, 'TNL';
        s.display.enabled.eta, s.display.enabled.last = false, false;
    end
    s.style.colors = defaults.copy(colors or (version == 1 and compact or raw));
    s.style.colors.chain_ending = theme.colors('Phoenix').chain_ending;
    return s;
end

local fresh = defaults.make();
local before_fresh = defaults.copy(fresh);
local current_style = defaults.copy(fresh.style);
current_style.palette_version = 1;
for _, fixture in ipairs({ { 0, raw }, { 0, palette }, { 1, compact } }) do
    local s = T(legacy(fixture[1], fixture[2]));
    local metatable, bar, display = getmetatable(s), s.bar, s.display;
    check(migrate.apply(s, fresh), 'An old appearance migrates.');
    check(s.appearance_version == 2, 'The completed migration is marked.');
    check(same(s.bar, fresh.bar), 'Old default geometry becomes the current automatic bar.');
    check(same(s.style, current_style), 'Old default styling and colors become current defaults.');
    check(s.display.spacing == fresh.display.spacing and s.display.divider == fresh.display.divider,
        'Default spacing and the separator migrate.');
    check(s.display.labels.remaining == fresh.display.labels.remaining, 'The old remaining label migrates.');
    local enabled_count = 0;
    for key, enabled in pairs(s.display.enabled) do
        check(enabled == fresh.display.enabled[key], 'Default readout visibility matches: ' .. key);
        if enabled then enabled_count = enabled_count + 1; end
    end
    check(enabled_count == 5, 'The default readout set stays compact.');
    check(s.style.colors.fill ~= fresh.style.colors.fill, 'Migrated colors do not share the defaults table.');
    check(no_retired(s.bar), 'All retired geometry keys are removed.');
    check(getmetatable(s) == metatable and s.bar == bar and s.display == display,
        'The settings wrapper and section identities stay intact.');
    local saved = defaults.copy(s);
    check(not migrate.apply(s, fresh) and same(s, saved), 'A second pass leaves settings alone.');
end
check(same(fresh, before_fresh), 'Migration never changes supplied defaults.');
local extra_enabled = legacy(0);
extra_enabled.display.enabled.food = true;
migrate.apply(extra_enabled, fresh);
check(extra_enabled.display.enabled.food and extra_enabled.display.enabled.eta and extra_enabled.display.enabled.last,
    'An extra enabled readout marks a custom selection that migration preserves.');

for _, version in ipairs({ 0, 1 }) do
    local custom = legacy(version);
    custom.bar.width, custom.bar.height, custom.bar.x, custom.bar.y, custom.bar.bottom = 1200, 30, 44, 333, 15;
    custom.bar.docked, custom.bar.auto_width = false, true;
    custom.style.font, custom.style.font_size, custom.style.opacity, custom.style.rounding = 'Verdana', 19, 0.7, 7;
    custom.style.fill_style, custom.style.colors.fill = 'full', { 0.3, 0.4, 0.5, 0.6 };
    custom.display.spacing, custom.display.labels.remaining = 7, 'Until next';
    custom.display.order[1], custom.display.order[2] = 'progress', 'job';
    custom.display.divider, custom.display.dividers.rate = ' / ', false;
    custom.display.enabled.session = true;
    custom.display.colors.job = { 1, 0.5, 0, 1 };
    custom.tracking.window, custom.alerts.food_enabled = 300, true;
    custom.job_links['1'], custom.shared = 'Mine', true;
    local saved = defaults.copy(custom);
    check(migrate.apply(custom, fresh), 'Customized old settings still migrate.');
    check(custom.bar.width == saved.bar.width and custom.bar.height == saved.bar.height
        and custom.bar.x == saved.bar.x and custom.bar.y == saved.bar.y and custom.bar.bottom == saved.bar.bottom
        and custom.bar.docked == false and custom.bar.auto_width == false,
        'A free layout keeps its geometry and fixed width despite newly merged defaults.');
    check(no_retired(custom.bar), 'Custom layouts also lose retired keys.');
    check(custom.style.font == 'Verdana' and custom.style.font_size == 19 and custom.style.opacity == 0.7
        and custom.style.rounding == 7 and custom.style.fill_style == 'full', 'Custom text and shape choices are preserved.');
    check(same(custom.style.colors.fill, saved.style.colors.fill) and same(custom.style.colors.text, fresh.style.colors.text),
        'Custom colors are preserved while untouched colors migrate individually.');
    check(custom.display.spacing == 7 and custom.display.labels.remaining == 'Until next', 'Custom spacing and labels are preserved.');
    check(same(custom.display.enabled, saved.display.enabled), 'A customized readout set is preserved.');
    check(same(custom.display.order, saved.display.order) and same(custom.display.dividers, saved.display.dividers)
        and custom.display.divider == ' / ' and same(custom.display.colors, saved.display.colors),
        'Order, divider toggles, custom separator, and per-readout colors are preserved.');
    check(same(custom.tracking, saved.tracking) and same(custom.alerts, saved.alerts)
        and same(custom.job_links, saved.job_links) and custom.shared, 'Unrelated settings stay untouched.');
end

local s = legacy(1);
s.bar.x, s.bar.bottom, s.bar.width, s.bar.auto_width = 27, 0, 1052, true;
s.bar.chat_left, s.bar.chat_right, s.bar.chat_screen = 27, 1079, 1920;
s.bar.chat_top, s.bar.chat_bottom, s.bar.chat_height = 821, 1060, 1080;
migrate.apply(s, fresh);
check(s.bar.x == fresh.bar.x and s.bar.bottom == fresh.bar.bottom and s.bar.width == fresh.bar.width
    and s.bar.auto_width and s.bar.height == fresh.bar.height and no_retired(s.bar),
    'A previously calibrated dock becomes automatic without using its saved chat rectangle.');
s = legacy(1);
s.bar.chat_width, s.bar.auto_width = false, true;
s.bar.x, s.bar.bottom, s.bar.width = 250, 60, 1180;
migrate.apply(s, fresh);
check(s.bar.x == 250 and s.bar.bottom == 60 and s.bar.width == 1180 and not s.bar.auto_width,
    'An old fixed dock keeps its chosen width and offsets.');
s = legacy(1); s.bar.auto_width = false;
migrate.apply(s, fresh);
check(s.bar.auto_width == false, 'An explicit automatic-width opt-out is preserved.');
s = legacy(0); s.bar.full_width, s.bar.width = false, 1100;
migrate.apply(s, fresh);
check(s.bar.auto_width == false and s.bar.width == 1100, 'An original fixed-width choice remains fixed.');
s = legacy(0); s.bar.full_width = false;
migrate.apply(s, fresh);
check(s.bar.auto_width == false and s.bar.width == 900, 'A fixed width equal to the former default remains fixed.');
s = legacy(1); s.bar.avoid_chat, s.bar.hide_typing = false, true;
migrate.apply(s, fresh);
check(s.bar.hide_typing == false, 'A former chat avoidance opt-out maps to typing visibility.');
s = legacy(1); s.bar.hide_typing = false;
migrate.apply(s, fresh);
check(s.bar.hide_typing == false, 'An explicit typing visibility choice remains unchanged.');
s = legacy(0); s.bar.docked = false;
migrate.apply(s, fresh);
check(s.bar.x == 100 and s.bar.width == 900 and s.bar.y == 500 and not s.bar.auto_width,
    'A free layout keeps its position and width even when they match former dock defaults.');

for _, change in ipairs({ 'disabled', 'extra', 'missing' }) do
    s = legacy(0);
    if change == 'disabled' then s.display.enabled.chain = false; end
    if change == 'extra' then s.display.enabled.custom = false; end
    if change == 'missing' then s.display.enabled.status = nil; end
    migrate.apply(s, fresh);
    check(s.display.enabled.eta and s.display.enabled.last, 'Only the exact original enabled map is replaced.');
end
s = legacy(1); s.display.enabled.eta, s.display.enabled.last = true, true;
migrate.apply(s, fresh);
check(s.display.enabled.eta and s.display.enabled.last, 'Later enabled-readout choices are preserved.');
for _, version in ipairs({ 0, 1 }) do
    s = legacy(version); s.style.preset = 'Custom'; s.display.labels.remaining = 'Left';
    local colors = defaults.copy(s.style.colors);
    migrate.apply(s, fresh);
    check(same(s.style.colors, colors), 'Other palette presets keep their colors.');
    check(s.display.labels.remaining == fresh.display.labels.remaining, 'The alternate old label migrates.');
    s = legacy(version);
    s.style.colors.fill[1] = s.style.colors.fill[1] + 0.0000005;
    s.style.colors.text[1] = s.style.colors.text[1] - 0.00001;
    local custom_text = defaults.copy(s.style.colors.text);
    migrate.apply(s, fresh);
    check(same(s.style.colors.fill, fresh.style.colors.fill), 'Small saved color rounding is accepted.');
    check(same(s.style.colors.text, custom_text), 'A color outside the tolerance is preserved.');
end
s = legacy(0); s.bar.height, s.style.rounding = 24, 8;
migrate.apply(s, fresh);
check(s.bar.height == 24 and s.style.rounding == 8, 'Original custom values do not get mistaken for later defaults.');
for _, marker in ipairs({ 2, 3, '2' }) do
    s = legacy(1); s.appearance_version = marker;
    s.style.palette_version = 1;
    local saved = defaults.copy(s);
    check(not migrate.apply(s, fresh) and same(s, saved), 'Current and future versions never reapply the migration.');
end
s = defaults.make();
check(migrate.apply(s, fresh) and s.appearance_version == 2 and same(s.bar, fresh.bar) and same(s.style, current_style),
    'A fresh merged settings table is marked without changing current defaults.');
s = legacy(nil);
check(migrate.apply(s, fresh) and s.appearance_version == 2 and same(s.bar, fresh.bar), 'Unmarked legacy settings migrate.');
check(not migrate.apply(nil, fresh) and not migrate.apply({}, nil), 'Invalid inputs are left alone.');

local saved_palettes = {
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
local function saved_skin(name)
    local value = defaults.make();
    value.appearance_version = 2;
    value.style.palette_version, value.style.window_colors, value.style.preset = nil, nil, name;
    value.style.colors = {};
    local colors = saved_palettes[name];
    for index, key in ipairs({ 'background', 'fill', 'lp_fill', 'text', 'label', 'divider', 'chain', 'warning' }) do
        value.style.colors[key] = hex_color(colors[index]);
    end
    value.style.colors.border = name == 'Phoenix' and hex_color('3a4657', 0.4)
        or hex_color(colors[6], name == 'High contrast' and 1 or 0.45);
    value.style.colors.chain_ending = theme.colors('Phoenix').chain_ending;
    return value;
end

for name in pairs(saved_palettes) do
    s = saved_skin(name);
    s.bar.anchor, s.bar.start, s.bar.x, s.bar.y, s.bar.width, s.bar.height = 'top', 87, 55, 211, 1011, 32;
    s.bar.docked, s.bar.snap, s.bar.auto_width, s.bar.bottom = false, false, false, 6;
    s.display.order[1], s.display.order[2] = s.display.order[2], s.display.order[1];
    s.display.divider, s.display.spacing, s.display.labels.remaining = ' / ', 9, 'Needed';
    s.display.alignment, s.display.dividers.rate = 'right', false;
    s.alerts.food_enabled, s.alerts.food_volume, s.tracking.window = true, 53, 300;
    local previous = defaults.copy(s);
    defaults.tidy(s);
    check(migrate.apply(s, fresh), 'Saved skin migrates: ' .. name);
    check(s.style.palette_version == 1 and s.appearance_version == 2, 'Palette has its own version marker: ' .. name);
    check(same(s.style.colors, theme.colors(name)), 'All untouched HUD roles take the canonical skin: ' .. name);
    check(same(s.style.window_colors, theme.window_colors(name)), 'Merged window defaults take the selected skin: ' .. name);
    check(same(s.bar, previous.bar), 'Skin migration preserves every geometry and placement setting: ' .. name);
    check(same(s.display, previous.display), 'Skin migration preserves readout order, alignment and dividers: ' .. name);
    check(same(s.alerts, previous.alerts) and same(s.tracking, previous.tracking), 'Skin migration preserves alerts and tracking: ' .. name);
    local reloaded = defaults.copy(s);
    defaults.tidy(reloaded);
    check(not migrate.apply(reloaded, fresh) and same(reloaded, s), 'Reload does not reapply a saved migration: ' .. name);

    local profile = profiles.capture(previous);
    local target = defaults.make();
    target.style.palette_version = 1;
    profiles.apply(target, profile);
    defaults.tidy(target);
    check(migrate.apply(target, fresh) and same(target.style.colors, theme.colors(name))
        and same(target.style.window_colors, theme.window_colors(name)), 'Older saved profile takes its own skin: ' .. name);
    local migrated_profile = profiles.capture(target);
    local second = defaults.make();
    profiles.apply(second, migrated_profile);
    defaults.tidy(second);
    check(not migrate.apply(second, fresh) and same(second.style, target.style), 'Current saved profile remains stable: ' .. name);

    s = saved_skin(name);
    s.style.colors.fill = { 0.123, 0.234, 0.345, 0.456 };
    s.style.colors.text[4] = 0.63;
    local window_role = next(theme.window_colors(name));
    s.style.window_colors = { [window_role] = { 0.321, 0.432, 0.543, 0.654 } };
    local custom = defaults.copy(s.style);
    defaults.tidy(s);
    migrate.apply(s, fresh);
    check(same(s.style.colors.fill, custom.colors.fill) and same(s.style.colors.text, custom.colors.text),
        'Custom RGB and alpha survive per-role migration: ' .. name);
    check(same(s.style.colors.background, theme.colors(name).background), 'Other untouched colors still migrate: ' .. name);
    check(same(s.style.window_colors[window_role], custom.window_colors[window_role]), 'Custom window role survives merged defaults: ' .. name);
    local canonical = theme.colors(name);
    s.style.colors.background[1] = 0.111;
    check(same(theme.colors(name).background, canonical.background), 'Migrated HUD colors do not alias the skin definition: ' .. name);
end

s = saved_skin('Phoenix');
s.style.colors.fill[1] = s.style.colors.fill[1] + 0.0000005;
migrate.apply(s, fresh);
check(same(s.style.colors.fill, theme.colors('Phoenix').fill), 'Saved palette rounding tolerates six decimal places.');
for _, marker in ipairs({ 1, 2, '1' }) do
    s = saved_skin('Ember'); s.style.palette_version = marker;
    local saved = defaults.copy(s);
    check(not migrate.apply(s, fresh) and same(s, saved), 'Current and future palette versions never downgrade.');
end
s = saved_skin('Mint'); s.appearance_version = 99;
local geometry = defaults.copy(s.bar);
check(migrate.apply(s, fresh) and s.appearance_version == 99 and same(s.bar, geometry)
    and same(s.style.colors, theme.colors('Mint')), 'Palette migration does not downgrade an independent appearance version.');
s = saved_skin('Phoenix'); s.style.preset = 'Custom';
local unknown_colors = defaults.copy(s.style.colors);
check(migrate.apply(s, fresh) and same(s.style.colors, unknown_colors)
    and same(s.style.window_colors, theme.window_colors('Phoenix')), 'Unknown presets retain custom HUD colors and get readable window defaults.');
check(same(fresh, before_fresh), 'Palette migration never changes supplied defaults.');

s = defaults.make();
check(theme.current(s) == 'Phoenix', 'Fresh colors identify the default skin.');
s.style.colors.fill = { 0.123, 0.234, 0.345, 0.456 };
check(theme.current(s) == nil, 'A custom HUD color clears the current skin match.');
check(theme.apply(s, 'Mint') and theme.current(s) == 'Mint' and s.style.palette_version == 1,
    'Applying a skin restores its colors and marks its palette version.');
s.style.window_colors.control = { 0.321, 0.432, 0.543, 0.654 };
check(theme.current(s) == nil, 'A custom window color clears the current skin match.');
s.bar.anchor, s.bar.start, s.bar.x, s.bar.width = 'top', 55, 101, 713;
s.display.alignment, s.display.divider, s.style.rounding = 'right', ' / ', 7;
s.display.order[1], s.display.order[2] = s.display.order[2], s.display.order[1];
local saved_bar, saved_display = defaults.copy(s.bar), defaults.copy(s.display);
check(theme.apply(s, 'Lavender') and theme.current(s) == 'Lavender', 'Applying another skin replaces a custom window color.');
check(same(s.bar, saved_bar) and same(s.display, saved_display) and s.style.rounding == 7,
    'Skin selection preserves geometry, order, alignment and custom rounding.');
local hud_colors, window_colors = theme.colors('Lavender'), theme.window_colors('Lavender');
hud_colors.fill[1], window_colors.control[1] = 0.123, 0.234;
check(same(s.style.colors, theme.colors('Lavender')) and same(s.style.window_colors, theme.window_colors('Lavender')),
    'Returned skin tables do not alias applied settings or canonical palettes.');
check(same(theme.colors('Unknown'), theme.colors('Phoenix'))
    and same(theme.window_colors('Unknown'), theme.window_colors('Phoenix')), 'Unknown skin names return the complete Phoenix palette.');
local before_invalid = defaults.copy(s);
check(not theme.apply(s, 'Unknown') and same(s, before_invalid), 'An invalid skin selection does not change settings.');
return { count = count };
