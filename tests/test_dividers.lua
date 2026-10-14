local defaults = require('ui.defaults');
local layout = require('ui.layout');
local readouts = require('ui.readouts');
local history = require('ui.history');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
MOCK.load_addon();
MOCK.fire('load');
local app = MOMENTUM_TEST;
app.settings().window.open = true;
local original_display = history.copy(app.settings().display);
local function click(label)
    if label then MOCK.clicks[label] = true; end
    MOCK.frame(0.25);
    assert(not app.state.broken, 'Divider controls stopped rendering');
end
local function enabled_count()
    local total = 0;
    for _, item in ipairs(defaults.READOUTS) do
        if app.settings().display.dividers[item.id] then total = total + 1; end
    end
    return total;
end
local function visible_marks()
    local settings = app.settings();
    local parts = layout.segments(readouts.build(settings, readouts.sample('Leveling')), settings.display);
    local placed = layout.arrange(parts, 2000, string.len, settings.display);
    local total = 0;
    for _, part in ipairs(placed) do
        if part.role == 'divider' and part.text:find('%S') then total = total + 1; end
    end
    equal(placed[1].role == 'divider', false, 'No leading divider');
    return total;
end
click();
equal(history.equal(original_display, app.settings().display), true, 'Opening settings preserves the saved display');
click('Remove all dividers');
equal(enabled_count(), 0, 'Remove all includes hidden readouts');
equal(visible_marks(), 0, 'Removed dividers leave no marks');
local before_all = history.copy(app.settings().display);
click('Add dividers to all');
equal(enabled_count(), #defaults.READOUTS, 'Add all includes hidden readouts');
equal(app.settings().display.divider, ' | ', 'Adding from spaces chooses a visible pipe');
equal(visible_marks(), 4, 'Five visible readouts have four dividers');
app.services.undo();
equal(history.equal(before_all, app.settings().display), true, 'One undo restores the complete bulk edit');
click('##divider_progress');
equal(app.settings().display.dividers.progress, true, 'Per-row checkbox enables its divider');
equal(app.settings().display.dividers.rate, false, 'Per-row checkbox leaves other readouts alone');
equal(app.settings().display.divider, ' | ', 'Per-row enable also chooses a visible style');
equal(visible_marks(), 1, 'Only the selected divider is drawn');
click('##divider_progress');
equal(visible_marks(), 0, 'Per-row checkbox removes the mark');
app.settings().display.divider = ' <> ';
click('Add dividers to all');
equal(app.settings().display.divider, ' <> ', 'Add all preserves custom text');
equal(history.equal(original_display.order, app.settings().display.order), true, 'Divider edits preserve order');
equal(history.equal(original_display.enabled, app.settings().display.enabled), true, 'Divider edits preserve visibility');
equal(app.services.save_profile('Dividers'), true, 'Divider layout saves as a profile');
click('Remove all dividers');
equal(app.services.load_profile('Dividers'), true, 'Divider profile reloads');
equal(app.settings().display.divider, ' <> ', 'Profile restores custom text');
equal(enabled_count(), #defaults.READOUTS, 'Profile restores per-readout dividers');
app.settings().display.enabled.progress = false;
equal(visible_marks(), 3, 'Hidden readout leaves no extra divider');
app.settings().display.groups_enabled = true;
app.settings().display.groups.rate = 'right';
equal(visible_marks(), 2, 'Each alignment group omits its first divider');
MOCK.fire('unload');
equal(#MOCK.commands, 0, 'Divider editing sends no game commands');
return { count = count };
