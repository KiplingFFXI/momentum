local defaults = require('ui.defaults');
local migrate = require('ui.migrate');
local readouts = require('ui.readouts');
local imgui = require('imgui');
local window = require('ui.settings_window');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function same(left, right)
    if type(left) ~= type(right) then return false; end
    if type(left) ~= 'table' then return left == right; end
    for key, value in pairs(left) do if not same(value, right[key]) then return false; end end
    for key in pairs(right) do if left[key] == nil then return false; end end
    return true;
end
local settings = defaults.make();
eq(settings.display.auto_layout, false, 'Automatic layouts are opt-in for new settings');
eq(defaults.tidy({ display = { auto_layout = true } }).display.auto_layout, true, 'Saved enabled choice survives sanitation');
eq(defaults.tidy({ display = { auto_layout = false } }).display.auto_layout, false, 'Saved disabled choice survives sanitation');
eq(defaults.tidy({ display = { auto_layout = 'true' } }).display.auto_layout, false, 'Malformed choice does not opt in');
local legacy = defaults.make();
legacy.display.auto_layout = nil;
legacy.display.order = { 'rate', 'food', 'merits' };
legacy.display.enabled.food = true;
migrate.apply(legacy, defaults.make());
local migrated = defaults.tidy(legacy);
eq(migrated.display.auto_layout, false, 'Old settings migrate with switching off');
eq(migrated.display.order[1], 'rate', 'Migration preserves the first saved readout');
eq(migrated.display.order[2], 'food', 'Migration preserves the second saved readout');
eq(migrated.display.enabled.food, true, 'Migration preserves existing chosen readouts');

settings.display.auto_layout = true;
settings.display.mode, settings.display.alignment = 'exp', 'right';
settings.display.labels.lp_rate = 'My LP';
settings.display.divider, settings.display.dividers.lp_remaining = ' | ', false;
settings.display.colors.merits = { 0.1, 0.2, 0.3, 0.4 };
settings.display.groups_enabled, settings.display.groups.merits = true, 'right';
settings.display.conditions.merit_eta, settings.display.pinned.merits = 'known', true;
settings.display.priorities.merits = 91;
settings.bar.docked, settings.bar.width, settings.bar.x, settings.bar.y = false, 420, 31, 287;
settings.style.preset = 'Ocean';
local before = defaults.copy(settings);
eq(defaults.apply_starter(settings, 'Unknown'), false, 'Unknown starter is rejected');
eq(same(settings, before), true, 'Unknown starter leaves settings unchanged');
for _, name in ipairs({ 'Merits', 'Leveling', 'Minimal' }) do
    local expected = name == 'Merits' and 'lp_rate,merits,lp_remaining,merit_eta'
        or name == 'Leveling' and 'job,progress,remaining,rate,chain' or 'progress,remaining,rate';
    eq(defaults.apply_starter(settings, name), true, 'Apply known starter ' .. name);
    local chosen, seen = {}, {};
    for _, id in ipairs(settings.display.order) do
        eq(seen[id], nil, 'Starter does not duplicate ' .. id);
        seen[id] = true;
        if settings.display.enabled[id] then chosen[#chosen + 1] = id; end
    end
    eq(table.concat(chosen, ','), expected, name .. ' enables only its readouts in the intended order');
    eq(#settings.display.order, #defaults.READOUTS, name .. ' retains every readout in the full order');
    eq(settings.display.preset, name, name .. ' records its name');
    local preserved = defaults.copy(settings);
    preserved.display.order, preserved.display.enabled, preserved.display.preset = before.display.order, before.display.enabled, before.display.preset;
    eq(same(preserved, before), true, name .. ' preserves all settings outside selection, order, and starter name');
end

settings = defaults.make();
settings.window.open = true;
MOCK.window_size = { 920, 660 };
local next_open;
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function() return next_open; end;
imgui.BeginCombo = function(label) return label == '##Starter layout'; end;
local calls, original = 0, defaults.apply_starter;
defaults.apply_starter = function(...)
    calls = calls + 1;
    return original(...);
end;
local function draw(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end
    return window.draw(settings, readouts.sample('Leveling'), {});
end
local order = table.concat(settings.display.order, ',');
draw('Switch saved EXP / Merits layouts');
eq(settings.display.auto_layout, true, 'UI checkbox enables the saved option');
eq(table.concat(settings.display.order, ','), order, 'Checkbox delegates actual switching to the entry point');
eq(calls, 0, 'Checkbox does not guess the character earning mode');
draw('Merits');
eq(calls, 1, 'Manual starter selection uses the shared helper');
eq(settings.display.order[1], 'lp_rate', 'Manual Merits preset uses the fixed LP rate');
eq(settings.display.order[4], 'merit_eta', 'Manual Merits preset includes its timer');
order = table.concat(settings.display.order, ',');
draw('Switch saved EXP / Merits layouts');
eq(settings.display.auto_layout, false, 'UI checkbox can disable automatic switching');
eq(table.concat(settings.display.order, ','), order, 'Turning switching off keeps the current arrangement');
defaults.apply_starter = original;
return { count = count };
