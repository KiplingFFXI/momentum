local defaults = require('ui.defaults');
local modes = require('ui.modes');
local history = require('ui.history');
local profiles = require('ui.profiles');
local checks = 0;
local function eq(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function same(actual, expected, label) eq(history.equal(actual, expected), true, label); end

local settings = defaults.make();
settings.events, settings.account = nil, nil;
settings.display.labels.rate, settings.display.divider, settings.display.alignment = 'My rate', ' / ', 'right';
settings.display.enabled.food, settings.display.dividers.rate = true, false;
defaults.tidy(settings);
eq(settings.display.labels.rate, 'My rate', 'Old labels survive new settings');
eq(settings.display.enabled.food, true, 'Old added readouts stay shown');
eq(settings.display.enabled.zone_time, false, 'New readings are opt-in');
eq(settings.events.layouts.assault.enabled.event_time, true, 'Assault gets its own compact starter');
eq(settings.events.layouts.limbus.enabled.event_coins, true, 'Limbus starter has coins');
eq(settings.events.layouts.enm.enabled.rate, false, 'ENM starter avoids unrelated EXP rate');
eq(settings.events.layouts.enm ~= settings.events.layouts.bcnm, true, 'Event modes have independent tables');
local original = history.copy(settings.display);

for _, kind in ipairs({ 'assault', 'limbus', 'bcnm', 'ksnm', 'enm' }) do
    eq(modes.select(settings, kind), true, 'Manual ' .. kind .. ' selection works outside the zone');
    eq(settings.events.active_kind, kind, 'Correct saved layout is active');
    eq(settings.dynamis.layout_active, false, 'Only one temporary event layout is active');
    settings.display.labels.event_time = kind .. ' left';
    settings.display.enabled.gil = true;
    settings.display.alignment = 'right';
    settings.display.dividers.event_time = false;
    eq(modes.select(settings, 'exp'), true, 'Return from ' .. kind);
    eq(settings.display.labels.rate, original.labels.rate, 'EXP label stays intact');
    eq(settings.display.enabled.gil, false, 'Event additions do not leak into EXP');
    eq(modes.select(settings, kind), true, 'Reopen ' .. kind);
    eq(settings.display.labels.event_time, kind .. ' left', 'Event label stays saved');
    eq(settings.display.enabled.gil, true, 'Event extra readout stays saved');
    eq(settings.display.alignment, 'right', 'Event alignment stays saved');
    eq(settings.display.dividers.event_time, false, 'Event divider stays saved');
end

settings.account.group = 'Account A';
local captured = profiles.capture(settings);
eq(captured.events.active_kind, nil, 'Profile does not capture a temporary active marker');
eq(captured.events.previous_display, nil, 'Profile does not keep stale previous displays');
eq(captured.events.layouts.enm.labels.event_time, 'enm left', 'Profile captures the active edited event bank');
eq(captured.account, nil, 'Profile does not copy account grouping');
local target = defaults.make();
target.account.group = 'Account B';
profiles.apply(target, captured);
defaults.tidy(target);
eq(target.account.group, 'Account B', 'Profile loading preserves the current character account preference');
eq(target.modes.selected, 'enm', 'Profile preserves manual event selection');
modes.event(target, nil);
eq(target.display.labels.event_time, 'enm left', 'Manual saved layout is restored after profile load');

modes.select(settings, 'auto');
settings.display.auto_layout = true;
local baseline = history.copy(settings.display);
eq(modes.event(settings, 'assault'), true, 'Automatic follows observed Assault entry');
settings.display.labels.event_status = 'State';
eq(modes.automatic(settings, 'lp'), false, 'Earning mode does not replace active event edits');
eq(modes.event(settings, nil), true, 'Leaving restores the normal bank');
same(settings.display, baseline, 'Automatic exit restores all normal display settings');
eq(settings.events.layouts.assault.labels.event_status, 'State', 'Automatic edits are stored in the matching bank');
settings.events.auto_layout = false;
eq(modes.event(settings, 'limbus'), false, 'Automatic event switching can be disabled');
same(settings.display, baseline, 'Disabled switching leaves normal layout intact');
settings.events.auto_layout = true;
modes.select(settings, 'dynamis');
modes.select(settings, 'auto');
require('ui.dynamis_layout').switch(settings, true);
eq(modes.event(settings, 'limbus'), true, 'Entering Limbus can leave a previous Dynamis display');
eq(settings.dynamis.layout_active, false, 'Dynamis and event layouts do not stack');
modes.event(settings, nil);
eq(settings.display.enabled.dyna_time, false, 'Leaving Limbus restores normal display, not stale Dynamis');

settings.events.layouts.enm.order = { 'event_time', 'deleted', 'event_time', 'gil' };
settings.events.layouts.enm.labels.event_time = 'Saved';
settings.events.layouts.enm.enabled.gil = true;
settings.events.wanted = { ['1875'] = true, ['-4'] = true, bad = true };
settings.events.history_limit, settings.events.warning_minutes = math.huge, -1;
settings.account.group = '  Account\n A  ';
defaults.tidy(settings);
eq(settings.events.layouts.enm.order[1], 'event_time', 'Saved event order is preserved');
eq(settings.events.layouts.enm.order[2], 'gil', 'Invalid and duplicate event readings are removed');
eq(settings.events.layouts.enm.labels.event_time, 'Saved', 'Saved event labels survive sanitation');
eq(settings.events.layouts.enm.enabled.gil, true, 'Event additions survive sanitation');
eq(settings.events.wanted['1875'], true, 'Wanted item survives');
eq(settings.events.wanted.bad, nil, 'Invalid wanted item removed');
eq(settings.events.history_limit, 30, 'Invalid history limit repaired');
eq(settings.events.warning_minutes, 1, 'Warning time stays in range');
eq(settings.account.group, 'Account A', 'Account nickname uses plain trimmed text');
for _, id in ipairs({ 'event_time', 'event_extension', 'event_objective', 'event_clear', 'event_failure', 'event_drop', 'event_ready' }) do
    eq(settings.alerts.events[id].visual, false, 'New notices start off');
    eq(settings.alerts.events[id].sound, false, 'New sounds start off');
end
return { count = checks };
