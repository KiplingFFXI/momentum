local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local rules = require('data.phoenix_rules');
local count = 0;
local function eq(actual, expected, title)
    count = count + 1;
    assert(actual == expected, title .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end

local stats = AshitaCore:GetMemoryManager():GetPlayer();
local subjob_reads, sublevel_reads = 0, 0;
local get_subjob, get_sublevel = stats.GetSubJob, stats.GetSubJobLevel;
stats.GetSubJob = function(...) subjob_reads = subjob_reads + 1; return get_subjob(...); end;
stats.GetSubJobLevel = function(...) sublevel_reads = sublevel_reads + 1; return get_sublevel(...); end;
stats.GetJobLevel = function() return MOCK.actual_level; end;
MOCK.actual_level, MOCK.player.main_level, MOCK.player.sub_level = 75, 75, 37;
MOCK.player.exp, MOCK.player.exp_needed = 1000, rules.tnl[75];
require('ui.hud').draw = function() return false; end;
require('ui.settings_window').draw = function() return false; end;
MOCK.load_addon();
local app = MOMENTUM_TEST;
local function frame()
    MOCK.frame(0.25);
    eq(app.state.broken, false, 'The entry point stays healthy');
end
local function value()
    return readouts.job_text(app.view(MOCK.now), app.settings().display);
end
local function choose(mode)
    eq(app.services.bar_mode(mode), true, 'Select ' .. mode);
    frame();
end
local function subjob(on)
    local display = app.settings().display;
    display.enabled.job, display.show_subjob = true, on;
    app.services.save();
    frame();
end

frame();
eq(subjob_reads, 0, 'Default frames never query the optional support job');
eq(sublevel_reads, 0, 'Default frames never query the optional support level');
choose('exp');
subjob(true);
eq(value(), 'WAR 75 / NIN 37', 'The enabled entry point supplies the support text');
local previous_jobs, previous_levels = subjob_reads, sublevel_reads;
app.settings().display.enabled.job = false;
frame();
eq(subjob_reads, previous_jobs, 'Hiding the job readout stops support job reads');
eq(sublevel_reads, previous_levels, 'Hiding the job readout stops support level reads');
subjob(true);
MOCK.player.main_level, MOCK.player.sub_level = 30, 15;
frame();
eq(value(), 'WAR 75 (sync 30) / NIN 15', 'Level Sync retains actual main level and uses current support level');
MOCK.player.sub_level = 12;
frame();
eq(value(), 'WAR 75 (sync 30) / NIN 12', 'A lower unlocked support level is not replaced by half the sync level');
MOCK.player.main_level, MOCK.player.sub_level = 75, 37;
frame();
eq(value(), 'WAR 75 / NIN 37', 'Ending Level Sync restores the current normal levels');
MOCK.player.sub_job, MOCK.player.sub_level = 0, 0;
previous_levels = sublevel_reads;
frame();
eq(value(), 'WAR 75', 'A restricted support job removes the previous suffix');
eq(sublevel_reads, previous_levels, 'A restricted support job does not query a nonexistent level');
MOCK.player.sub_job, MOCK.player.sub_level = 13, 37;
frame();
eq(value(), 'WAR 75 / NIN 37', 'Support information returns after the restriction ends');

choose('merits');
subjob(false);
choose('exp');
eq(value(), 'WAR 75 / NIN 37', 'EXP restores its enabled support choice');
choose('auto');
app.settings().display.auto_layout = true;
app.services.save();
frame();
MOCK.player.mode = 'lp';
frame();
eq(app.settings().modes.active, 'merits', 'Automatic follows the client merit mode');
eq(app.settings().display.show_subjob, false, 'Automatic restores the saved Merits support choice');
MOCK.player.mode = 'exp';
frame();
frame();
eq(app.settings().modes.active, 'exp', 'Automatic returns to EXP');
eq(value(), 'WAR 75 / NIN 37', 'The next regular sample supplies support data for the returning layout');

local choices = { exp = true, merits = false, dynamis = true, assault = false,
    limbus = true, bcnm = false, ksnm = true, enm = false };
local order = { 'exp', 'merits', 'dynamis', 'assault', 'limbus', 'bcnm', 'ksnm', 'enm' };
for _, mode in ipairs(order) do choose(mode); subjob(choices[mode]); end
eq(app.services.save_profile('Support layouts'), true, 'A profile saves every support choice');
for _, mode in ipairs(order) do
    choose(mode);
    eq(app.settings().display.show_subjob, choices[mode], mode .. ' restores its separate support choice');
end
choose('exp');
subjob(false);
eq(app.services.load_profile('Support layouts'), true, 'The support profile loads');
frame();
for _, mode in ipairs(order) do
    choose(mode);
    eq(app.settings().display.show_subjob, choices[mode], mode .. ' keeps its choice through profile loading');
end

choose('exp');
subjob(true);
local main_settings = defaults.copy(app.settings());
local alt_settings = defaults.make();
alt_settings.appearance_version, alt_settings.style.palette_version = 2, 1;
alt_settings.display.show_subjob = false;
MOCK.player.name, MOCK.player.server_id = 'Second', 1002;
MOCK.player.sub_job, MOCK.player.sub_level = 6, 24;
MOCK.settings.switch_character(alt_settings);
eq(app.view(MOCK.now).valid, false, 'A character callback clears the old character snapshot immediately');
eq(app.view(MOCK.now).subjob_name, nil, 'A character callback clears the previous support job immediately');
frame();
eq(app.settings().display.show_subjob, false, 'The alt keeps its own disabled support option');
eq(value(), 'WAR 75', 'An alt with the option off does not inherit the main suffix');
subjob(true);
eq(value(), 'WAR 75 / THF 24', 'Enabling the alt option reads the alt current support job');
MOCK.player.name, MOCK.player.server_id = 'Tester', 1001;
MOCK.player.sub_job, MOCK.player.sub_level = 13, 37;
MOCK.settings.switch_character(main_settings);
eq(app.view(MOCK.now).subjob_name, nil, 'Returning to the main clears the alt support snapshot first');
frame();
eq(app.settings().display.show_subjob, true, 'Returning to the main restores its saved toggle');
eq(value(), 'WAR 75 / NIN 37', 'Returning to the main uses fresh support data');
app.services.session_pause(true);
eq(app.tracker().paused, true, 'Pause is active');
MOCK.player.sub_job, MOCK.player.sub_level = 6, 20;
frame();
eq(value(), 'WAR 75 / THF 20', 'Current support job still changes while the session is paused');
eq(app.services.session_reset(), true, 'Reset is available');
eq(value(), 'WAR 75 / THF 20', 'Reset preserves current support information');
eq(app.services.shared(true), true, 'The support layout can be shared');
MOCK.player.name, MOCK.player.server_id = 'Second', 1002;
MOCK.player.sub_job, MOCK.player.sub_level = 13, 18;
MOCK.settings.switch_character(alt_settings);
frame();
eq(app.settings().display.show_subjob, true, 'A shared appearance keeps its support toggle on the alt');
eq(value(), 'WAR 75 / NIN 18', 'A shared appearance still reads the current character support level');
return { count = count };
