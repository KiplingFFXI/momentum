local defaults = require('ui.defaults');
local history = require('ui.history');
local tracker = require('core.tracker');
local rules = require('data.phoenix_rules');
local imgui = require('imgui');
local store = require('core.file_store');
local profiles = require('ui.profiles');
local checks = 0;
local function equal(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function snapshot(level, mode, capacity)
    return { valid = true, id = 1001, job = 1, level = level, effective_level = 20, exp = 1000,
        exp_needed = rules.tnl[level], limit_mode = mode, merit_cap = capacity };
end
equal(tracker.earning_mode(snapshot(74, true, 30)), 'exp', 'Actual level74 earns EXP despite a retained mode flag');
equal(tracker.earning_mode(snapshot(75, true, 30)), 'lp', 'Actual level75 remains eligible while synced20');
equal(tracker.earning_mode(snapshot(75, false, 30)), 'exp', 'Level75 can still earn EXP');
equal(tracker.earning_mode(snapshot(75, true, nil)), nil, 'Missing merit packet leaves mode unknown');
equal(tracker.earning_mode(snapshot(75, true, 0)), nil, 'Zeroed client capacity leaves mode unknown');
equal(tracker.earning_mode(snapshot(75, nil, 30)), nil, 'Unavailable mode flag stays unknown');
local capped = snapshot(75, false, 30);
capped.exp, capped.limit_breaker, capped.merits = capped.exp_needed - 1, false, 30;
equal(tracker.earning_mode(capped), 'lp', 'Full75 EXP buffer routes ordinary rewards to LP without an eligibility guess');
capped.exp, capped.exp_locked = 1000, true;
equal(tracker.earning_mode(capped), 'exp', 'EXP lock flag alone does not select LP');
capped.valid = false;
equal(tracker.earning_mode(capped), nil, 'Invalid player data has no earning mode');
capped.valid, capped.exp_needed = true, 900;
equal(tracker.earning_mode(capped), nil, 'Mixed level and TNL data has no earning mode');

local app, edit;
local root_copies, shared_writes, switches = 0, 0, 0;
local copy, write = history.copy, store.write;
local modes = require('ui.modes');
local automatic = modes.automatic;
history.copy = function(value)
    if app and value == app.settings() then root_copies = root_copies + 1; end
    return copy(value);
end;
store.write = function(path, value)
    if path:find('shared_layout.json', 1, true) then shared_writes = shared_writes + 1; end
    return write(path, value);
end;
modes.automatic = function(s, mode)
    local changed = automatic(s, mode);
    if app and s == app.settings() and changed then switches = switches + 1; end
    return changed;
end;
require('ui.hud').draw = function() return false; end;
require('ui.settings_window').draw = function(s)
    if edit then return edit(s); end
    return false;
end;
imgui.IsAnyItemActive = function() return MOCK.item_active == true; end;
AshitaCore:GetMemoryManager():GetPlayer().GetJobLevel = function() return MOCK.actual_level or MOCK.player.main_level; end;
local function player_mode(mode, level, job)
    MOCK.actual_level, MOCK.player.main_level = level or 75, 20;
    MOCK.player.main_job, MOCK.player.mode = job or 1, mode;
    MOCK.player.exp_needed = rules.tnl[MOCK.actual_level];
    MOCK.player.exp, MOCK.player.merit_cap = 1000, 30;
end
local function frame(seconds)
    MOCK.frame(seconds or 0.25);
    equal(app.state.broken, false, 'Automatic layout remains drawable');
end
local function command(value) MOCK.fire('command', { command = value, blocked = false }); end
local function shown()
    local values = {};
    for _, id in ipairs(app.settings().display.order) do
        if app.settings().display.enabled[id] then values[#values + 1] = id; end
    end
    return table.concat(values, ',');
end
local function ui_change(callback)
    edit = function(s) callback(s); return true; end;
    frame();
    edit = nil;
end
player_mode('exp');
MOCK.load_addon();
MOCK.fire('load');
app = MOMENTUM_TEST;
frame();
equal(app.settings().display.auto_layout, false, 'Automatic layouts default off');
app.settings().window.open = true;
ui_change(function(s)
    defaults.apply_starter(s, 'Minimal');
    s.display.enabled.food = true;
    s.display.labels.food = 'EXP food';
    s.display.dividers.food = false;
    s.display.colors.food = { 0.2, 0.4, 0.6, 1 };
    s.display.priorities.food = 90;
    s.display.pinned.food = true;
    s.display.conditions.food = 'known';
end);
local exp_layout = shown();
frame();
local saves, copies = MOCK.saved, root_copies;
player_mode('lp');
frame();
equal(shown(), exp_layout, 'Disabled switching keeps the customized layout');
equal(MOCK.saved, saves, 'Disabled switching never writes settings');
equal(root_copies, copies, 'Disabled idle path never copies settings');
ui_change(function(s) s.display.auto_layout = true; end);
frame();
equal(shown(), table.concat(defaults.STARTER_LAYOUTS.Merits, ','), 'An absent Merits layout gets its compact starter');
equal(app.settings().modes.active, 'merits', 'Automatic remembers the active layout');
ui_change(function(s)
    s.display.enabled.job = true;
    s.display.labels.lp_rate = 'My LP';
    s.display.divider = ' | ';
end);
command('/momentum order job lp_rate merits lp_remaining merit_eta');
local merit_layout = shown();
frame();
local before_switches = switches;
saves, copies = MOCK.saved, root_copies;
for _ = 1, 60 do MOCK.frame(1 / 60); end
equal(switches, before_switches, 'Idle Automatic never rebuilds its layout');
equal(MOCK.saved, saves, 'Idle Automatic never writes settings');
equal(root_copies, copies, 'Idle Automatic never recopies settings');
player_mode('exp');
frame();
equal(shown(), exp_layout, 'Returning EXP restores added readouts and their order');
equal(app.settings().display.labels.food, 'EXP food', 'Returning EXP restores labels');
equal(app.settings().display.dividers.food, false, 'Returning EXP restores individual dividers');
equal(app.settings().display.colors.food[2], 0.4, 'Returning EXP restores colors');
equal(app.settings().display.priorities.food, 90, 'Returning EXP restores priorities');
equal(app.settings().display.pinned.food, true, 'Returning EXP restores keep-visible settings');
equal(app.settings().display.conditions.food, 'known', 'Returning EXP restores conditions');
equal(app.settings().display.auto_layout, true, 'An old layout cannot disable automatic switching');
equal(app.settings().display.mode, 'auto', 'Automatic keeps its own EXP/LP preference');
equal(MOCK.saved, saves, 'Automatic mode changes do not write settings');
player_mode('lp');
frame();
equal(shown(), merit_layout, 'Returning Merits restores its added job readout and order');
equal(app.settings().display.labels.lp_rate, 'My LP', 'Returning Merits restores its label');
equal(app.settings().display.divider, ' | ', 'Returning Merits restores its formatting');
player_mode('lp', 75, 2);
frame();
equal(shown(), merit_layout, 'A job change never replaces readouts with a starter');
MOCK.player.server_id = 2002;
frame();
equal(shown(), merit_layout, 'A new identity never resets the selected layout');
MOCK.player.merit_cap, MOCK.player.mode = 0, 'exp';
frame();
equal(shown(), merit_layout, 'Unknown earning mode preserves the last layout');
MOCK.player.merit_cap = 30;
frame();
equal(shown(), exp_layout, 'Known EXP mode restores the saved EXP layout');
MOCK.player.exp = rules.tnl[75] - 1;
frame();
equal(shown(), merit_layout, 'A full EXP buffer selects the saved Merits layout');
MOCK.player.exp = 1000;
frame();
equal(shown(), exp_layout, 'An unfilled EXP buffer restores the saved EXP layout');
MOCK.zoning = true;
frame();
equal(shown(), exp_layout, 'Loading keeps the current customized layout');
MOCK.zoning = false;
frame();
player_mode('lp', 74, 2);
frame();
equal(shown(), exp_layout, 'A stale LP flag below75 keeps EXP');
player_mode('lp', 75, 2);
frame();
equal(shown(), merit_layout, 'A valid level75 LP mode selects saved Merits');

ui_change(function(s) s.display.auto_layout = false; end);
player_mode('exp', 75, 2);
frame();
equal(shown(), merit_layout, 'Turning automatic switching off holds the current bank');
ui_change(function(s) s.display.auto_layout = true; end);
frame();
equal(shown(), exp_layout, 'Re-enabling restores the saved current earning layout');
MOCK.mouse_down = true;
edit = function(s) s.display.divider = 'drag'; return true; end;
frame(); edit = nil;
player_mode('lp', 75, 2);
frame();
equal(shown(), exp_layout, 'A drag defers automatic switching');
MOCK.mouse_down, MOCK.item_active = false, true;
frame();
equal(shown(), exp_layout, 'Active text or slider input defers automatic switching');
MOCK.item_active = false;
local save = MOCK.settings.save;
MOCK.settings.save = function() error('Pending edit test failure'); end;
frame();
equal(shown(), exp_layout, 'Failed pending save defers switching');
equal(app.state.dirty, true, 'Failed user save stays dirty');
MOCK.settings.save = save;
frame(11);
equal(shown(), merit_layout, 'Switching resumes after the save retry');
equal(app.state.dirty, false, 'Successful save retry clears dirty state');
player_mode('exp', 75, 2);
frame();
equal(app.settings().display.divider, 'drag', 'The deferred edit was stored in EXP');
command('/momentum divider :');
app.services.undo(); frame();
equal(app.settings().display.divider, 'drag', 'Undo restores the edited bank without a starter reset');

MOCK.player.zone = 185;
frame();
equal(app.settings().dynamis.layout_active, true, 'Dynamis layout takes over automatically');
player_mode('lp', 75, 2);
frame();
MOCK.player.zone = 102;
frame();
equal(shown(), merit_layout, 'Dynamis exit restores the saved current earning layout');
equal(app.settings().display.labels.lp_rate, 'My LP', 'Dynamis exit preserves customization');
equal(app.services.save_profile('Auto banks'), true, 'Automatic banks can be saved in a profile');
command('/momentum mode exp');
ui_change(function(s) s.display.labels.food = 'Temporary'; end);
equal(app.services.load_profile('Auto banks'), true, 'Automatic banks can be loaded from a profile');
frame();
equal(shown(), merit_layout, 'Profile loading preserves the customized earning layout');
player_mode('exp', 75, 2); frame();
equal(app.settings().display.labels.food, 'EXP food', 'Profile loading restores the other bank');
app.services.save();
MOCK.fire('unload');
MOCK.settings_file = history.copy(MOCK.settings.last_saved);
MOCK.load_addon(); MOCK.fire('load'); app = MOMENTUM_TEST; frame();
equal(shown(), exp_layout, 'Reload preserves added readouts');
equal(app.settings().display.labels.food, 'EXP food', 'Reload preserves custom labels');
player_mode('lp', 75, 2); frame();
equal(shown(), merit_layout, 'Reload preserves the other saved bank');
equal(app.services.shared(true), true, 'Automatic banks work in shared settings');
app.settings().window.open = false; frame();
saves, before_switches = MOCK.saved, shared_writes;
for _, mode in ipairs({ 'exp', 'lp', 'exp', 'lp' }) do player_mode(mode, 75, 2); frame(2.1); end
equal(MOCK.saved, saves, 'Automatic shared transitions never write character settings');
equal(shared_writes, before_switches, 'Automatic shared transitions never rewrite shared settings');
local path = AshitaCore:GetInstallPath() .. '\\config\\addons\\momentum\\shared_layout.json';
local external = profiles.capture(app.settings());
external.display.labels.lp_rate = 'Shared LP';
equal(store.write(path, { enabled = true, layout = external }), true, 'External shared profile can be saved');
frame(2.1);
equal(shown(), merit_layout, 'External shared profile preserves custom readouts');
equal(app.settings().display.labels.lp_rate, 'Shared LP', 'External shared profile applies current edits');
equal(#MOCK.commands, 0, 'Automatic layouts never change the game earning mode');
return { count = checks };
