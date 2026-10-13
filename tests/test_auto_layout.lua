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
local applications, root_copies, shared_writes = 0, 0, 0;
local apply_starter, copy, write = defaults.apply_starter, history.copy, store.write;
defaults.apply_starter = function(s, name)
    if app and s == app.settings() then applications = applications + 1; end
    return apply_starter(s, name);
end;
history.copy = function(value)
    if app and value == app.settings() then root_copies = root_copies + 1; end
    return copy(value);
end;
store.write = function(path, value)
    if path:find('shared_layout.json', 1, true) then shared_writes = shared_writes + 1; end
    return write(path, value);
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
    equal(app.state.broken, false, 'Automatic layout path remains drawable');
end
local function command(value) MOCK.fire('command', { command = value, blocked = false }); end
local function shown()
    local values = {};
    for _, id in ipairs(app.settings().display.order) do
        if app.settings().display.enabled[id] then values[#values + 1] = id; end
    end
    return table.concat(values, ',');
end
local leveling = table.concat(defaults.STARTER_LAYOUTS.Leveling, ',');
local merits = table.concat(defaults.STARTER_LAYOUTS.Merits, ',');
local function ui_change(callback)
    edit = function(s) callback(s); return true; end;
    frame();
    edit = nil;
end
player_mode('exp');
dofile(ADDON_DIR .. '/momentum.lua');
MOCK.fire('load');
app = MOMENTUM_TEST;
frame();
equal(app.settings().display.auto_layout, false, 'Automatic layouts default off');
apply_starter(app.settings(), 'Minimal');
app.settings().window.open = true;
frame();
local manual, saves, copies = shown(), MOCK.saved, root_copies;
player_mode('lp');
frame();
equal(shown(), manual, 'Disabled option preserves manual selection across mode changes');
equal(MOCK.saved, saves, 'Disabled option does not save settings');
equal(root_copies, copies, 'Disabled idle path does not recopy settings');
equal(applications, 0, 'Disabled option does not build a preset');

ui_change(function(s) s.display.auto_layout = true; end);
saves = MOCK.saved;
frame();
equal(shown(), merits, 'Enabling selects the current real Merits layout');
equal(MOCK.saved, saves, 'Automatic selection adds no settings write');
equal(applications, 1, 'Enabling applies one active preset');
local before_copies, before_apps = root_copies, applications;
for _ = 1, 60 do MOCK.frame(1 / 60); end
equal(root_copies, before_copies, 'Stable auto mode does not copy the settings tree');
equal(applications, before_apps, 'Stable auto mode does not rebuild its layout');
equal(MOCK.saved, saves, 'Stable auto mode does not save settings');
app.services.undo();
equal(app.settings().display.auto_layout, false, 'One undo reverses enabling the option');
equal(shown(), manual, 'Automatic selection did not insert its own undo step');
equal(app.services.can_undo(), false, 'Only the user option change entered history');
frame();

ui_change(function(s) s.display.auto_layout = true; end);
frame();
ui_change(function(s) s.display.mode = 'exp'; end);
frame();
equal(shown(), merits, 'Forced EXP display does not change the real LP layout');
local stable_apps = applications;
command('/momentum preview');
app.settings().preview.scenario = 'Leveling';
frame();
equal(shown(), merits, 'Sample EXP preview does not change the real LP layout');
equal(applications, stable_apps, 'Presentation overrides do not trigger automatic application');
command('/momentum preview');
ui_change(function(s) s.display.mode = 'auto'; end);
frame();
player_mode('exp');
saves, before_copies = MOCK.saved, root_copies;
frame();
equal(shown(), leveling, 'Actual EXP mode selects Leveling');
equal(MOCK.saved, saves, 'Actual mode transition does not write settings');
equal(root_copies, before_copies, 'Idle editor is rebased without a full settings copy');
MOCK.player.exp = rules.tnl[75] - 1;
frame();
equal(shown(), merits, 'Full75 EXP buffer selects Merits without explicit mode');
MOCK.player.merits, MOCK.player.limit_points = 30, 9999;
frame();
equal(shown(), merits, 'Full merit storage does not change LP earning mode');

command('/momentum order job lp_rate merits lp_remaining merit_eta');
ui_change(function(s) s.display.enabled.job = true; end);
manual = shown();
frame();
equal(shown(), manual, 'Manual readout changes remain until a real mode transition');
command('/momentum divider :');
app.services.undo();
frame();
equal(shown(), manual, 'Undo replacing the display table does not reapply the preset');
MOCK.player.merit_cap, MOCK.player.mode, MOCK.player.exp = 0, 'exp', 1000;
frame();
equal(shown(), manual, 'Unavailable merit packet holds the current selection');
MOCK.player.merit_cap = 30;
frame();
equal(shown(), leveling, 'Valid EXP data completes the deferred mode transition');
ui_change(function(s) s.display.enabled.food = true; end);
manual = shown();
MOCK.zoning = true;
frame();
equal(shown(), manual, 'Loading keeps the prior selection');
MOCK.zoning = false;
frame();
equal(shown(), manual, 'Returning to the same mode and identity preserves manual choices');
player_mode('exp', 74);
frame();
equal(shown(), manual, 'A level change within EXP mode does not reset manual choices');
player_mode('lp', 74);
frame();
equal(shown(), manual, 'Stale LP flag below75 does not trigger a layout change');
player_mode('lp', 75);
frame();
equal(shown(), merits, 'Recovering75 with a valid LP flag selects Merits');
ui_change(function(s) s.display.enabled.food = true; end);
player_mode('lp', 75, 2);
frame();
equal(shown(), merits, 'New actual job selects its current automatic preset');
ui_change(function(s) s.display.enabled.food = true; end);
MOCK.player.server_id = 2002;
frame();
equal(shown(), merits, 'New character identity selects its current automatic preset');

ui_change(function(s) s.display.auto_layout = false; end);
manual = shown();
player_mode('exp', 75, 2);
frame();
equal(shown(), manual, 'Turning off keeps the displayed arrangement');
ui_change(function(s) s.display.auto_layout = true; end);
frame();
equal(shown(), leveling, 'Re-enabling uses the current EXP mode');

MOCK.mouse_down = true;
edit = function(s) s.display.divider = 'drag'; return true; end;
frame();
edit = nil;
player_mode('lp', 75, 2);
frame();
equal(shown(), leveling, 'Mouse drag defers automatic layout replacement');
equal(app.state.dirty, true, 'Pending user edit remains dirty');
MOCK.mouse_down, MOCK.item_active = false, true;
frame();
equal(shown(), leveling, 'Active text or slider input also defers replacement');
MOCK.item_active = false;
local saved = MOCK.settings.save;
MOCK.settings.save = function() error('Pending edit test failure'); end;
frame();
equal(shown(), leveling, 'Failed pending save defers automatic replacement');
equal(app.state.dirty, true, 'Failed user save is not discarded');
MOCK.settings.save = saved;
frame(11);
equal(shown(), merits, 'Pending switch runs after the user save retry succeeds');
equal(app.state.dirty, false, 'Successful user retry clears only its own dirty state');
equal(app.settings().display.divider, 'drag', 'Automatic layouts preserve manual formatting');
app.services.undo();
frame();
equal(app.settings().display.divider, ' ', 'Undo retains the genuine edit preceding the automatic switch');
equal(shown(), leveling, 'Undo is treated as a manual arrangement until the next transition');

ui_change(function(s) apply_starter(s, 'Minimal'); end);
equal(app.services.save_profile('Auto test'), true, 'Automatic configuration can be saved in a profile');
equal(app.services.load_profile('Auto test'), true, 'Automatic profile can be loaded');
frame();
equal(shown(), merits, 'Explicit profile load reselects the current earning layout');
equal(app.services.shared(true), true, 'Automatic setting can be shared');
app.settings().window.open = false;
frame();
saves, before_apps = MOCK.saved, shared_writes;
for _, mode in ipairs({ 'exp', 'lp', 'exp', 'lp' }) do player_mode(mode, 75, 2); frame(2.1); end
equal(MOCK.saved, saves, 'Automatic shared mode changes never write character settings');
equal(shared_writes, before_apps, 'Automatic shared mode changes never write shared layout');
local shared_path = AshitaCore:GetInstallPath() .. '\\config\\addons\\momentum\\shared_layout.json';
local external = profiles.capture(app.settings());
apply_starter(external, 'Minimal');
external.style.rounding = external.style.rounding + 1;
equal(store.write(shared_path, { enabled = true, layout = external }), true, 'External shared settings fixture saved');
before_apps = shared_writes;
frame(2.1);
equal(shown(), merits, 'Shared root replacement selects this character current mode');
equal(shared_writes, before_apps, 'Applying a shared replacement does not write it back');
equal(MOCK.saved, saves, 'Shared replacement does not cause an automatic settings save');
equal(app.services.can_undo(), false, 'Shared replacement has no automatic undo step');
local incoming = defaults.make();
incoming.display.auto_layout = true;
apply_starter(incoming, 'Minimal');
MOCK.settings.switch_character(incoming);
frame();
equal(shown(), merits, 'Character settings replacement selects its actual mode');
equal(#MOCK.commands, 0, 'Automatic layouts never change the game earning mode');
return { count = checks };
