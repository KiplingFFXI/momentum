local defaults = require('ui.defaults');
local history = require('ui.history');
local profiles = require('ui.profiles');
local readouts = require('ui.readouts');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end

local function old_display()
    local display = defaults.make().display;
    display.order = { 'gil', 'dedication_budget', 'rate', 'dedication', 'food' };
    for id in pairs(display.enabled) do display.enabled[id] = false; end
    display.enabled.gil, display.enabled.dedication_budget, display.enabled.rate = true, true, true;
    display.labels.gil, display.labels.dedication_budget, display.labels.rate = 'Wallet', 'Bonus left', 'Pace';
    display.dividers.dedication_budget, display.groups.dedication_budget = false, 'right';
    display.colors.dedication_budget, display.priorities.dedication_budget = { 0.2, 0.4, 0.6, 1 }, 80;
    display.pinned.dedication_budget, display.conditions.dedication_budget = true, 'dedication';
    return display;
end

local settings = defaults.make();
settings.display = old_display();
settings.modes.exp, settings.modes.merits = old_display(), old_display();
settings.modes.previous_display, settings.modes.legacy_auto_display = old_display(), old_display();
settings.modes.layout_version = 1;
settings.dynamis.layout, settings.dynamis.previous_display = old_display(), old_display();
settings.alerts.events.dedication_low, settings.alerts.events.sync_change = { visual = true }, { sound = true };
settings.alerts.dedication_low_points = 100;
settings.alerts.events.dedication_end.sound = true;
settings.window.sections['Alerts/Level Sync and missed EXP'] = true;
defaults.tidy(settings);
for _, display in ipairs({ settings.display, settings.modes.exp, settings.modes.merits, settings.modes.previous_display,
    settings.modes.legacy_auto_display, settings.dynamis.layout, settings.dynamis.previous_display }) do
    eq(display.enabled.dedication, true, 'Old bonus selection becomes the client Dedication readout');
    eq(table.concat({ display.order[1], display.order[2], display.order[3], display.order[4] }, ','), 'gil,dedication,rate,food', 'Other readout order stays in place');
    eq(display.labels.dedication, '', 'The obsolete amount label does not describe a buff');
    eq(display.labels.gil, 'Wallet', 'Other custom labels remain');
    eq(display.labels.rate, 'Pace', 'Rate labels remain');
    eq(display.dividers.dedication, false, 'Migrated readout retains its divider');
    eq(display.groups.dedication, 'right', 'Migrated readout retains its alignment group');
    eq(display.colors.dedication[3], 0.6, 'Migrated readout retains its color');
    eq(display.priorities.dedication, 80, 'Migrated readout retains its priority');
    eq(display.pinned.dedication, true, 'Migrated readout retains its pin');
    eq(display.conditions.dedication, 'dedication', 'Migrated readout retains its visibility condition');
    for _, key in ipairs({ 'enabled', 'labels', 'dividers', 'colors', 'groups', 'priorities', 'pinned', 'conditions' }) do
        eq(display[key].dedication_budget, nil, 'Retired keys are removed from ' .. key);
    end
    local seen = 0;
    for _, id in ipairs(display.order) do if id == 'dedication' then seen = seen + 1; end; eq(id == 'dedication_budget', false, 'Retired ID is absent from order'); end
    eq(seen, 1, 'Dedication appears once');
end
eq(settings.alerts.events.dedication_low, nil, 'Low bonus alert is removed');
eq(settings.alerts.events.sync_change, nil, 'Current penalty alert is removed');
eq(settings.alerts.dedication_low_points, nil, 'Obsolete bonus threshold is removed');
eq(settings.alerts.events.dedication_end.sound, true, 'Wear-off sound choice remains');
eq(settings.window.sections['Alerts/Missed EXP'], true, 'Missed EXP retains its saved expanded state');
eq(settings.window.sections['Alerts/Level Sync and missed EXP'], nil, 'Obsolete section key is removed');
eq(readouts.definition('dedication_budget'), nil, 'Obsolete readout cannot be selected');
local once = history.copy(settings);
defaults.tidy(settings);
eq(history.equal(settings, once), true, 'Cleanup is stable across reloads');
local profile = profiles.capture(settings);
eq(profile.alerts.events.dedication_low, nil, 'Saved profiles omit the obsolete bonus alert');
eq(profile.display.enabled.dedication_budget, nil, 'Saved profiles omit the obsolete readout');

settings = defaults.make();
settings.display = old_display();
settings.display.enabled.dedication = true;
settings.display.labels.dedication, settings.display.groups.dedication = 'Buff', 'center';
defaults.tidy(settings);
eq(table.concat({ settings.display.order[1], settings.display.order[2], settings.display.order[3] }, ','), 'gil,rate,dedication', 'An existing enabled Dedication keeps its place');
eq(settings.display.labels.dedication, 'Buff', 'An existing Dedication label is preserved');
eq(settings.display.groups.dedication, 'center', 'An existing Dedication group is preserved');
settings = defaults.make();
for id in pairs(settings.display.enabled) do settings.display.enabled[id] = false; end
settings.display.enabled.dedication_budget = true;
settings.display.order = { 'dedication_budget' };
defaults.tidy(settings);
eq(#readouts.build(settings, readouts.sample()), 1, 'A bar containing only the obsolete readout remains usable');
eq(readouts.build(settings, readouts.sample())[1].id, 'dedication', 'The one-readout bar now shows the client buff');
return { count = count };
