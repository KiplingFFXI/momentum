local defaults = require('ui.defaults');
local history = require('ui.history');
local profiles = require('ui.profiles');
local rules = require('data.phoenix_rules');
local modes = require('ui.modes');
local checks = 0;
local function equal(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function same(actual, expected, label) equal(history.equal(actual, expected), true, label); end
local function shown(settings)
    local result = {};
    for _, id in ipairs(settings.display.order) do
        if settings.display.enabled[id] then result[#result + 1] = id; end
    end
    return table.concat(result, ',');
end

local fresh = defaults.make();
equal(fresh.modes.selected, 'auto', 'Existing layouts start in automatic selection');
equal(modes.select(fresh, 'bad', 'exp'), false, 'Unknown modes are rejected');
equal(fresh.modes.selected, 'auto', 'Invalid selection keeps the current mode');
fresh.display.labels.rate = 'Original EXP';
fresh.display.divider = ' / ';
fresh.display.dividers.rate = false;
fresh.display.alignment = 'right';
local original = history.copy(fresh.display);
equal(modes.select(fresh, 'exp', 'lp'), true, 'EXP is selectable while earning LP');
equal(fresh.display.labels.rate, 'Original EXP', 'Existing EXP customization is retained');
equal(fresh.display.mode, 'exp', 'Manual EXP forces EXP readouts');
fresh.display.labels.rate = 'Edited EXP';
equal(modes.select(fresh, 'merits', 'exp'), true, 'Merits is selectable while earning EXP');
equal(shown(fresh), table.concat(defaults.STARTER_LAYOUTS.Merits, ','), 'First Merits selection uses compact readouts');
equal(fresh.display.mode, 'lp', 'Manual Merits forces LP readouts');
fresh.display.labels.lp_rate = 'Edited LP';
fresh.display.divider = ' | ';
fresh.display.dividers.merits = false;
local merit_display = history.copy(fresh.display);
equal(modes.select(fresh, 'dynamis', 'exp'), true, 'Dynamis can be selected directly');
fresh.display.labels.dyna_time = 'Left';
equal(modes.select(fresh, 'exp', 'lp'), true, 'Return to saved EXP mode');
equal(fresh.display.labels.rate, 'Edited EXP', 'EXP edits survive a three-mode round trip');
equal(fresh.display.divider, ' / ', 'EXP divider retained');
equal(fresh.display.dividers.rate, false, 'EXP individual divider retained');
equal(fresh.display.alignment, 'right', 'EXP alignment retained');
equal(modes.select(fresh, 'merits', 'exp'), true, 'Return to saved Merits mode');
same(fresh.display, merit_display, 'All Merits display options are retained');
equal(modes.select(fresh, 'dynamis', 'exp'), true, 'Return to saved Dynamis mode');
equal(fresh.display.labels.dyna_time, 'Left', 'Dynamis edits are retained');
equal(modes.select(fresh, 'auto', 'lp'), true, 'Return to automatic selection');
local automatic_merits = history.copy(merit_display);
automatic_merits.mode = original.mode;
same(fresh.display, automatic_merits, 'Automatic uses the same customized normal layout');

require('ui.hud').draw = function() return false; end;
require('ui.settings_window').draw = function() return false; end;
MOCK.player.main_level, MOCK.player.exp_needed = 75, rules.tnl[75];
MOCK.player.exp, MOCK.player.mode = 1000, 'exp';
MOCK.load_addon();
MOCK.fire('load');
local app = MOMENTUM_TEST;
local function frame(seconds)
    MOCK.frame(seconds or 0.25);
    equal(app.state.broken, false, 'Mode selection remains drawable');
end
local function select_mode(mode)
    equal(app.services.bar_mode(mode), true, 'Select ' .. mode);
    frame();
end
local function command(value) MOCK.fire('command', { command = value, blocked = false }); end
frame();
app.settings().display.labels.rate = 'Session EXP';
select_mode('exp');
app.settings().display.labels.rate = 'My EXP';
app.settings().display.enabled.food = true;
select_mode('merits');
equal(app.view(MOCK.now).mode, 'lp', 'Merits reads LP regardless of earning mode');
app.settings().display.labels.lp_rate = 'My LP';
app.settings().window.open = false;
MOCK.player.mode = 'lp';
frame();
MOCK.player.main_level, MOCK.player.exp_needed, MOCK.player.mode = 50, rules.tnl[50], 'exp';
frame();
equal(app.settings().modes.selected, 'merits', 'Manual mode stays selected across real earning mode changes');
equal(app.settings().display.labels.lp_rate, 'My LP', 'Manual layout remains customized below level75');
equal(app.view(MOCK.now).mode, 'lp', 'Manual Merits stays an LP display below level75');
select_mode('dynamis');
equal(app.settings().dynamis.layout_active, true, 'Manual Dynamis works outside Dynamis');
equal(app.settings().display.enabled.dyna_time, true, 'Manual Dynamis uses its timer readout');
equal(app.view(MOCK.now).dynamis.active, false, 'Choosing a layout does not invent a Dynamis run');
app.settings().display.labels.dyna_time = 'My time';
frame();
equal(app.settings().modes.selected, 'dynamis', 'Closing config leaves the chosen mode selected');

MOCK.player.zone = 185;
frame();
local utc = os.time();
app.dynamis.core:hourglass({ zone = 185, start_time = utc, end_time = utc + 3600 }, MOCK.now, utc);
app.dynamis.core:drop({ slot = 0, item_id = 1456, count = 1, start_time = 55, token = 'manual-mode' }, MOCK.now, utc);
app.tracker():award({ kind = 'exp', amount = 120, token = 'manual-exp' }, MOCK.now);
app.tracker():award({ kind = 'lp', amount = 90, token = 'manual-lp' }, MOCK.now);
local before = app.view(MOCK.now);
local deadline = app.dynamis.core.current.end_time;
local tracked = app.tracker();
select_mode('exp');
equal(app.settings().display.labels.rate, 'My EXP', 'EXP customization returns in Dynamis');
equal(app.settings().display.enabled.food, true, 'Optional EXP readout returns');
equal(app.settings().dynamis.layout_active, false, 'Manual EXP overrides automatic Dynamis layout');
equal(app.view(MOCK.now).mode, 'exp', 'Manual EXP reads EXP inside Dynamis');
select_mode('merits');
equal(app.settings().display.labels.lp_rate, 'My LP', 'Merits customization returns in Dynamis');
select_mode('dynamis');
equal(app.settings().display.labels.dyna_time, 'My time', 'Dynamis customization returns');
equal(app.tracker(), tracked, 'Mode changes keep the same EXP session');
equal(app.view(MOCK.now).session_exp, before.session_exp, 'Mode changes preserve earned EXP');
equal(app.view(MOCK.now).session_lp, before.session_lp, 'Mode changes preserve earned LP');
equal(app.view(MOCK.now).dynamis.currency_found, 100, 'Mode changes preserve Dynamis loot');
equal(app.dynamis.core.current.end_time, deadline, 'Mode changes preserve the hourglass deadline');

equal(app.services.save_profile('Manual Dynamis'), true, 'Manual mode can be saved in a profile');
select_mode('exp');
equal(app.services.load_profile('Manual Dynamis'), true, 'Manual mode profile can be loaded');
frame();
equal(app.settings().modes.selected, 'dynamis', 'Profile restores manual Dynamis selection');
equal(app.settings().dynamis.layout_active, true, 'Profile restores active Dynamis display');
equal(app.settings().display.labels.dyna_time, 'My time', 'Profile restores customized Dynamis display');
equal(app.services.shared(true), true, 'Manual mode works with shared settings');
frame();
equal(app.settings().modes.selected, 'dynamis', 'Shared settings preserve manual mode');
equal(app.settings().display.labels.dyna_time, 'My time', 'Shared settings preserve active readouts');
equal(app.services.shared(false), true, 'Manual mode can return to character settings');
frame();
equal(app.settings().modes.selected, 'dynamis', 'Leaving shared settings preserves manual mode');

MOCK.player.zone = 102;
frame();
equal(app.settings().modes.selected, 'dynamis', 'Leaving Dynamis keeps a manual selection');
equal(app.settings().dynamis.layout_active, true, 'Manual Dynamis stays displayed after leaving');
MOCK.fire('unload');
MOCK.settings_file = history.copy(MOCK.settings.last_saved);
MOCK.load_addon();
MOCK.fire('load');
app = MOMENTUM_TEST;
frame();
equal(app.settings().modes.selected, 'dynamis', 'Reload retains manual mode');
equal(app.settings().display.labels.dyna_time, 'My time', 'Reload retains its layout');
select_mode('exp');
equal(app.settings().display.labels.rate, 'My EXP', 'Reload retains the saved EXP layout');
select_mode('merits');
equal(app.settings().display.labels.lp_rate, 'My LP', 'Reload retains the saved Merits layout');
command('/momentum mode lp');
equal(app.settings().modes.selected, 'merits', 'Existing lp command aliases Merits');
command('/momentum mode exp');
equal(app.settings().modes.selected, 'exp', 'EXP command selects manual EXP');
command('/momentum mode merits');
equal(app.settings().modes.selected, 'merits', 'Merits command selects manual Merits');
command('/momentum mode dynamis');
equal(app.settings().modes.selected, 'dynamis', 'Dynamis command selects manual Dynamis');
command('/momentum mode invalid');
equal(app.settings().modes.selected, 'dynamis', 'Invalid command preserves the chosen mode');
select_mode('auto');
equal(app.settings().display.labels.lp_rate, 'My LP', 'Automatic uses the same saved layout after reload');
equal(app.settings().dynamis.layout_active, false, 'Automatic mode outside Dynamis restores normal display');
MOCK.player.zone = 185;
frame();
equal(app.settings().dynamis.layout_active, true, 'Automatic Dynamis switching resumes');
MOCK.player.zone = 102;
frame();
equal(app.settings().dynamis.layout_active, false, 'Automatic Dynamis exit resumes');

select_mode('exp');
select_mode('merits');
app.services.undo();
frame();
equal(app.settings().modes.selected, 'exp', 'Undo restores the previous manual mode');
equal(app.settings().display.labels.rate, 'My EXP', 'Undo restores the corresponding layout');
local copies, saves = 0, MOCK.saved;
local copy = history.copy;
history.copy = function(value)
    if value == app.settings() then copies = copies + 1; end
    return copy(value);
end;
for _ = 1, 60 do MOCK.frame(1 / 60); end
equal(copies, 0, 'Idle manual mode never recopies the settings tree');
equal(MOCK.saved, saves, 'Idle manual mode never writes settings');
history.copy = copy;

local old_profile = { display = history.copy(defaults.make().display) };
old_profile.display.labels.rate = 'Old profile EXP';
profiles.apply(app.settings(), old_profile);
defaults.tidy(app.settings());
frame();
equal(app.settings().modes.selected, 'auto', 'Legacy profiles do not retain a stale manual override');
equal(app.settings().display.labels.rate, 'Old profile EXP', 'Legacy profile layout is applied');
local incoming = defaults.make();
modes.select(incoming, 'merits', 'exp');
incoming.display.labels.lp_rate = 'Other character LP';
MOCK.settings.switch_character(incoming);
frame();
equal(app.settings().modes.selected, 'merits', 'Character settings select their own manual mode');
equal(app.settings().display.labels.lp_rate, 'Other character LP', 'Character settings use their own layout');
equal(app.services.reset_section('display'), true, 'Reset the manual Merits display');
equal(app.settings().modes.selected, 'merits', 'Merits display reset keeps the selected mode');
equal(shown(app.settings()), table.concat(defaults.STARTER_LAYOUTS.Merits, ','), 'Merits display reset uses compact Merits readouts');
equal(app.view(MOCK.now).mode, 'lp', 'Merits display reset still shows LP');
select_mode('dynamis');
equal(app.services.reset_section('display'), true, 'Reset the manual Dynamis display');
equal(app.settings().modes.selected, 'dynamis', 'Dynamis display reset keeps the selected mode');
equal(shown(app.settings()), table.concat(defaults.STARTER_LAYOUTS.Dynamis, ','), 'Dynamis display reset uses compact Dynamis readouts');
equal(app.settings().dynamis.layout_active, true, 'Dynamis display reset keeps its timer fill');

select_mode('merits');
app.settings().style.rounding = 9;
equal(app.services.save_profile('Linked Merits'), true, 'Save the job-linked Merits profile');
equal(app.services.job_link(2, 'Linked Merits'), true, 'Link the saved profile to the next job');
select_mode('exp');
app.settings().style.rounding = 3;
MOCK.player.main_job = 2;
frame();
equal(app.settings().modes.selected, 'exp', 'Automatic job profile preserves the chosen manual mode');
equal(app.view(MOCK.now).mode, 'exp', 'Automatic job profile preserves EXP readouts');
equal(app.settings().style.rounding, 9, 'Automatic job profile still applies its appearance');
MOCK.fire('unload');
MOCK.settings_file = history.copy(MOCK.settings.last_saved);
MOCK.load_addon();
MOCK.fire('load');
app = MOMENTUM_TEST;
frame();
equal(app.settings().modes.selected, 'exp', 'Initial job profile on reload keeps the saved manual mode');
equal(app.view(MOCK.now).mode, 'exp', 'Reloaded job profile retains EXP readouts');
equal(app.settings().style.rounding, 9, 'Reloaded job profile still applies its appearance');
equal(app.services.load_profile('Linked Merits'), true, 'Explicit profile loading remains available');
frame();
equal(app.settings().modes.selected, 'merits', 'Explicit profile loading may select its saved manual mode');
equal(#MOCK.commands, 0, 'Manual display modes never send gameplay commands');
return { count = checks };
