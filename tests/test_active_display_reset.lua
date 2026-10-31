local defaults = require('ui.defaults');
local history = require('ui.history');
local modes = require('ui.modes');
local checks = 0;
local function equal(actual, expected, message)
    checks = checks + 1;
    assert(actual == expected, message .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
MOCK.load_addon();
local app = MOMENTUM_TEST;
for _, case in ipairs({
    { mode = 'exp', preset = 'Leveling' },
    { mode = 'merits', preset = 'Merits' },
    { mode = 'farming', preset = 'Farming' },
    { mode = 'merits', automatic = true, preset = 'Merits' },
    { mode = 'farming', automatic = true, preset = 'Farming' },
    { mode = 'dynamis', preset = 'Dynamis' },
    { mode = 'assault', preset = 'Assault' },
    { mode = 'limbus', preset = 'Limbus' },
    { mode = 'bcnm', preset = 'BCNM' },
    { mode = 'ksnm', preset = 'KSNM' },
    { mode = 'enm', preset = 'ENM' },
}) do
    equal(app.services.bar_mode(case.mode), true, 'Select ' .. case.mode);
    if case.automatic then
        app.settings().farming.auto_layout = case.mode == 'farming';
        equal(app.services.bar_mode('auto'), true, 'Select Automatic');
        modes.automatic(app.settings(), case.mode == 'merits' and 'lp' or 'exp');
    end
    local selected, active = app.settings().modes.selected, app.settings().modes.active;
    local bar = history.copy(app.settings().bar);
    app.settings().display.labels.gil = 'Changed label';
    equal(app.services.reset_section('display'), true, 'Reset Display for ' .. case.mode);
    local settings = app.settings();
    equal(settings.display.preset, case.preset, 'Reset matches the effective selected layout');
    equal(settings.modes.selected, selected, 'Reset preserves selected mode');
    equal(settings.modes.active, active, 'Reset preserves the normal layout bank');
    equal(history.equal(settings.bar, bar), true, 'Reset leaves placement alone');
    equal(settings.display.labels.gil, defaults.make().display.labels.gil, 'Reset restores display labels');
    if case.mode == 'farming' then
        equal(settings.display.enabled.farm_items, true, 'Farming item readout is restored');
        equal(settings.display.enabled.progress, false, 'Farming does not silently become EXP');
    elseif case.mode == 'merits' then
        equal(settings.display.enabled.lp_rate, true, 'Merits restores LP/HR');
    end
end
return { count = checks };
