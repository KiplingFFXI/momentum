local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local dynamis = require('ui.dynamis');
local details = require('ui.details');
local imgui = require('imgui');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function controls(opened)
    local seen = { text = {}, help = {}, buttons = {}, sections = {}, checks = {}, combos = {}, changed = 0 };
    local ui = {};
    function ui.note(text) seen.text[#seen.text + 1] = text; end
    function ui.tip() end
    function ui.help(text) seen.help[#seen.help + 1] = text; end
    function ui.section(title, _, default, summary)
        seen.sections[title] = summary;
        if opened[title] ~= nil then return opened[title]; end
        return default == true;
    end
    function ui.checkbox(value, key, label) seen.checks[label] = { value = value, key = key }; end
    function ui.slider() end
    function ui.combo(title, current, choices, select)
        seen.combos[title] = { current = current, choices = choices, select = select };
    end
    function ui.changed() seen.changed = seen.changed + 1; end
    function ui.buttons(buttons) for _, button in ipairs(buttons) do seen.buttons[button[1]] = button[2]; end end
    return ui, seen;
end

local settings = defaults.make();
eq(settings.display.order[1], 'job', 'Existing default EXP layout stays intact');
eq(settings.display.enabled.dyna_time, false, 'Dynamis fields do not appear in the EXP layout');
eq(settings.dynamis.layout.order[1], 'dyna_zone', 'Dynamis keeps a separate starter');
eq(settings.dynamis.layout.enabled.dyna_time, true, 'Dynamis starter includes timer');
eq(settings.dynamis.layout.enabled.rate, false, 'Compact Dynamis starter omits EXP rate');
settings.dynamis.layout.labels.dyna_time = 'Left';
eq(settings.display.labels.dyna_time, 'Time', 'Separate layout does not share nested label tables');
settings.dynamis.warning_minutes = {};
settings.dynamis.layout.order = { 'dyna_time', 'removed', 'dyna_time', 'dyna_currency' };
settings.dynamis.layout.spacing = math.huge;
settings.dynamis.wanted_jobs = { WAR = true, ABC = true, MNK = 'true' };
settings.dynamis.wanted_items = { [123] = true, ['456'] = true, bad = true, ['-1'] = true };
defaults.tidy(settings);
eq(#settings.dynamis.warning_minutes, 0, 'Turning all timer warnings off survives sanitation');
eq(settings.dynamis.layout.order[1], 'dyna_time', 'Saved Dynamis order is preserved');
eq(settings.dynamis.layout.order[2], 'dyna_currency', 'Invalid and duplicate readouts are removed');
eq(settings.dynamis.layout.labels.dyna_time, 'Left', 'Saved Dynamis label is preserved');
eq(settings.dynamis.layout.spacing, 8, 'Invalid spacing repaired');
eq(settings.dynamis.wanted_jobs.WAR, true, 'Wanted job survives');
eq(settings.dynamis.wanted_jobs.ABC, nil, 'Unknown job removed');
eq(settings.dynamis.wanted_jobs.MNK, nil, 'Malformed checkbox does not enable a job');
eq(settings.dynamis.wanted_items['123'], true, 'Item keys normalized to strings');
eq(settings.dynamis.wanted_items.bad, nil, 'Invalid item key removed');
settings.window.tab, settings.preview.scenario = 'Dynamis', 'Dynamis';
defaults.tidy(settings);
eq(settings.window.tab, 'Dynamis', 'Dynamis tab survives reload');
eq(settings.preview.scenario, 'Dynamis', 'Dynamis preview survives reload');

settings = defaults.make();
defaults.apply_starter(settings, 'Dynamis');
local view = readouts.sample('Dynamis');
local values = {};
for _, item in ipairs(readouts.build(settings, view)) do values[item.id] = item.value; end
eq(values.dyna_time, '1:03:52', 'Hour countdown retains seconds');
eq(values.dyna_extensions, '+55m', 'Extension total is compact');
eq(values.dyna_currency, '247', 'Currency total uses single-piece value');
eq(values.dyna_af2, '4', 'Armor total shown');
view.dynamis.clock_estimated = true;
eq(readouts.cached(settings, view)[2].value, '~1:03:52', 'Computer clock estimate marked');
view.dynamis.clock_estimated = false;
eq(readouts.cached(settings, view)[2].value, '1:03:52', 'Server clock refresh removes estimate marker');
view.valid = false;
eq(readouts.build(settings, view)[2].value, '1:03:52', 'Known hourglass does not wait for EXP state');
view.dynamis.remaining = nil;
eq(readouts.build(settings, view)[2].value, '--', 'Missing deadline is unknown');
view.dynamis.remaining = 0;
eq(readouts.build(settings, view)[2].value, '0:00', 'Expired deadline does not go negative');
view.dynamis.remaining = 9.8;
local before = readouts.cached(settings, view);
view.dynamis.remaining = 9.1;
eq(readouts.cached(settings, view), before, 'Countdown reuses cached line inside displayed second');
view.dynamis.remaining = 9;
local after = readouts.cached(settings, view);
eq(after ~= before, true, 'Countdown changes at displayed second boundary');
eq(after[2].value, '0:09', 'Countdown does not round early');
view.dynamis.active = false;
eq(readouts.build(settings, view)[2].value, '--', 'Inactive run hides old timer');
eq(readouts.countdown(math.huge), '--', 'Invalid countdown stays unknown');

view = readouts.sample('Dynamis');
settings = defaults.make();
local copied, cleared, layout_mode;
local services = {
    copy = function(value) copied = value; end,
    dynamis_clear = function() cleared = (cleared or 0) + 1; return true; end,
    bar_mode = function(mode) layout_mode = mode; end,
};
local ui, seen = controls({ ['Dynamis options'] = true });
dynamis.draw(settings, view, services, ui);
local next_entry_shown = false;
for _, text in ipairs(seen.text) do if text:find('Next Dynamis entry:', 1, true) then next_entry_shown = true; end end
eq(next_entry_shown, true, 'Observed account lockout is available during an active run');
eq(table.concat(seen.help, '\n'):find('grouped characters on this computer', 1, true) ~= nil, true, 'Entry help explains locally observed account sharing');
seen.buttons['Copy run summary']();
eq(copied:find('Currency found: 247', 1, true) ~= nil, true, 'Run summary includes found currency');
eq(copied:find('Received: 12', 1, true) ~= nil, true, 'Run summary separates personal currency');
seen.buttons['Use Dynamis bar']();
eq(layout_mode, 'dynamis', 'Edit button requests separate Dynamis layout');
eq(settings.window.tab, 'Display', 'Edit button opens familiar Display controls');
MOCK.clicks['Clear run totals...'] = true;
ui, seen = controls({}); dynamis.draw(settings, view, services, ui);
eq(cleared, nil, 'First clear click does not erase totals');
eq(type(seen.buttons['Clear run totals now']), 'function', 'Clear needs a short confirmation');
seen.buttons['Clear run totals now']();
eq(cleared, 1, 'Confirmed clear calls service once');
eq(view.dynamis.remaining, 3832, 'UI clear does not modify deadline');
eq(view.dynamis.extension_minutes, 55, 'UI clear leaves extension total alone');
MOCK.clicks['Clear run totals...'] = true;
ui, seen = controls({}); dynamis.draw(settings, view, services, ui);
view.dynamis.start_time = view.dynamis.start_time + 1;
ui, seen = controls({}); dynamis.draw(settings, view, services, ui);
eq(seen.buttons['Clear run totals now'], nil, 'A new run cancels an old clear confirmation');
MOCK.clicks['Clear run totals...'] = true;
ui, seen = controls({}); dynamis.draw(settings, view, services, ui);
dynamis.cancel_pending();
ui, seen = controls({}); dynamis.draw(settings, view, services, ui);
eq(seen.buttons['Clear run totals now'], nil, 'Closing settings cancels clear confirmation');

settings.alerts.events.dyna_time.visual = true;
settings.alerts.events.dyna_wanted.sound = true;
ui, seen = controls({ Dynamis = false });
details.alerts(settings, view, services, ui);
eq(seen.sections.Dynamis, '2 on', 'Collapsed Dynamis alerts show enabled count');
eq(settings.alerts.events.dyna_pool.visual, false, 'Other Dynamis alerts remain off');
ui, seen = controls({ ['Wanted drops'] = true, ['Objectives and time extensions'] = true, ['Currency and drops'] = true, ['Treasure pool'] = true });
dynamis.draw(settings, view, services, ui);
eq(type(seen.checks.WAR), 'table', 'Wanted jobs are easy checkboxes');
eq(seen.checks.WAR.value, settings.dynamis.wanted_jobs, 'Wanted job uses saved job map');
local words = table.concat(seen.text, '\n');
eq(words:find('Overlord\'s Tombstone: Unknown', 1, true) ~= nil, true, 'Unknown objective is not presented as remaining');
eq(words:find('No drops recorded yet.', 1, true), nil, 'Recorded drop list is present');
local runs = {
    { name = 'Dynamis - Bastok', start_time = 1000, currency_found = 10 },
    { name = 'Dynamis - San d\'Oria', start_time = 2000, currency_found = 20 },
};
services.dynamis_history = function() return runs; end;
ui, seen = controls({ ['Dynamis run history'] = true });
dynamis.draw(settings, view, services, ui);
eq(seen.combos['Saved run'].current:find('Dynamis - San d\'Oria', 1, true) ~= nil, true, 'Latest saved run has its own label');
local choices = seen.combos['Saved run'].choices;
dynamis.draw(settings, view, services, ui);
eq(seen.combos['Saved run'].choices, choices, 'Unchanged history reuses its labels');
table.remove(runs, 1);
runs[#runs + 1] = { name = 'Dynamis - Windurst', start_time = 3000, currency_found = 30 };
dynamis.draw(settings, view, services, ui);
eq(seen.combos['Saved run'].current:find('Dynamis - Windurst', 1, true) ~= nil, true, 'Full history refreshes the newest run label');
eq(seen.combos['Saved run'].choices[2].name:find('Dynamis - San d\'Oria', 1, true) ~= nil, true, 'Full history refreshes older run labels after eviction');
seen.buttons['Copy saved run summary']();
eq(copied:find('Dynamis - Windurst', 1, true) ~= nil, true, 'Copied history matches the displayed run label');
view.dynamis.active, view.dynamis.next_entry_seconds = false, 0;
ui, seen = controls({}); dynamis.draw(settings, view, services, ui);
eq(table.concat(seen.text, '\n'):find('Next Dynamis entry: Lockout ended', 1, true) ~= nil, true, 'Expired observed account timer is not called guaranteed readiness');
view.dynamis.next_entry_seconds = nil;
ui, seen = controls({}); dynamis.draw(settings, view, services, ui);
eq(table.concat(seen.text, '\n'):find('Next Dynamis entry:', 1, true), nil, 'Unknown entry timer does not invent a date');
return { count = count };
