local defaults = require('ui.defaults');
local history = require('ui.history');
local checks = 0;
local function eq(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function shown(settings)
    local ids = {};
    for _, id in ipairs(settings.display.order) do
        if settings.display.enabled[id] then ids[#ids + 1] = id; end
    end
    return table.concat(ids, ',');
end
MOCK.load_addon();
MOCK.fire('load');
local app = MOMENTUM_TEST;
app.services.bar_mode('exp');
app.settings().display.labels.rate = 'My EXP rate';
app.settings().display.enabled.food = true;
local original = history.copy(app.settings().display);
for _, name in ipairs({ 'Assault', 'Limbus', 'BCNM', 'KSNM', 'ENM' }) do
    local kind = name:lower();
    eq(app.services.bar_mode(kind), true, name .. ' can be selected');
    app.settings().display.labels.event_time = 'My event timer';
    eq(app.services.reset_section('display'), true, name .. ' display reset succeeds');
    eq(shown(app.settings()), table.concat(defaults.STARTER_LAYOUTS[name], ','), name .. ' reset keeps its starter readouts');
    eq(app.settings().events.active_kind, kind, name .. ' display reset keeps its mode');
    eq(app.services.reset_section('events'), true, name .. ' event settings reset succeeds');
    eq(app.services.bar_mode('exp'), true, 'EXP can be restored after ' .. name .. ' settings reset');
    eq(history.equal(app.settings().display, original), true, name .. ' event settings reset preserves the normal layout');
end
MOCK.fire('unload');
eq(#MOCK.commands, 0, 'Display resets send no gameplay commands');
return { count = checks };
