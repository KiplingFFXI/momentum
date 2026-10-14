local history = require('ui.history');
local checks = 0;
local function equal(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
require('ui.hud').draw = function() return false; end;
MOCK.load_addon();
MOCK.fire('load');
local app = MOMENTUM_TEST;
local function frame()
    MOCK.frame(0.25);
    equal(app.state.broken, false, 'Settings remain drawable');
end
local function toggle()
    MOCK.clicks['Switch saved EXP / Merits layouts'] = true;
    frame();
    equal(MOCK.clicks['Switch saved EXP / Merits layouts'], nil, 'Settings checkbox receives the click');
end
app.settings().window.open = true;
app.settings().window.tab = 'Display';
MOCK.player.zone = 185;
frame();
equal(app.settings().dynamis.layout_active, true, 'Automatic Dynamis layout is active');
equal(app.settings().dynamis.previous_display.auto_layout, false, 'Regular EXP/Merits switching starts off');
toggle();
equal(app.settings().dynamis.previous_display.auto_layout, true, 'Checkbox edits the regular EXP/Merits option');
equal(app.settings().display.auto_layout, false, 'Dynamis display does not receive the EXP/Merits option');
equal(MOCK.settings.last_saved.dynamis.previous_display.auto_layout, true, 'Changed option is saved');
app.services.undo();
frame();
equal(app.settings().dynamis.previous_display.auto_layout, false, 'Undo restores the prior regular option');
equal(app.settings().dynamis.layout_active, true, 'Undo keeps the active Dynamis layout');
toggle();
MOCK.player.zone = 102;
frame();
equal(app.settings().display.auto_layout, true, 'Leaving Dynamis keeps the chosen EXP/Merits option');
MOCK.player.zone = 185;
frame();
toggle();
equal(app.settings().dynamis.previous_display.auto_layout, false, 'The regular option can also be disabled in Dynamis');
MOCK.fire('unload');
MOCK.settings_file = history.copy(MOCK.settings.last_saved);
MOCK.load_addon();
MOCK.fire('load');
app = MOMENTUM_TEST;
frame();
equal(app.settings().dynamis.previous_display.auto_layout, false, 'Reload keeps the edited regular option');
MOCK.player.zone = 102;
frame();
equal(app.settings().display.auto_layout, false, 'Disabled option stays off after exit');
equal(#MOCK.commands, 0, 'Changing the option sends no gameplay commands');
return { count = checks };
