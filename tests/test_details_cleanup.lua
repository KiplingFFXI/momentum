local defaults = require('ui.defaults');
local details = require('ui.details');
local readouts = require('ui.readouts');
local history = require('ui.history');
local imgui = require('imgui');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function includes(text, needle) return text:find(needle, 1, true) ~= nil; end
local function controls(opened)
    local seen = { words = {}, help = {}, sections = {}, summaries = {}, buttons = {}, sliders = {}, combos = {}, picks = {}, choices = {}, values = {}, checks = {}, changed = 0 };
    local ui = {};
    function ui.note(text) seen.words[#seen.words + 1] = text; end
    function ui.tip(text) if text then seen.help[#seen.help + 1] = text; end end
    ui.help = ui.tip;
    function ui.heading(text, help) ui.note(text); ui.help(help); end
    function ui.section(title, help, default_open, summary)
        seen.sections[title] = default_open;
        seen.summaries[title] = summary;
        ui.help(help);
        if opened and opened[title] ~= nil then return opened[title]; end
        return default_open ~= false;
    end
    function ui.changed() seen.changed = seen.changed + 1; end
    function ui.checkbox(value, key, title, help)
        seen.checks[value] = seen.checks[value] or {};
        seen.checks[value][key] = { title = title, value = value[key], set = function(next_value)
            if value[key] ~= next_value then value[key] = next_value; ui.changed(); end
        end };
        ui.help(help);
    end
    function ui.slider(_, _, title) seen.sliders[title] = true; end
    function ui.combo(title, value, choices, callback)
        seen.combos[title], seen.choices[title], seen.values[title] = callback, choices, value;
    end
    function ui.pick(_, _, title, _, help) seen.picks[title] = true; ui.help(help); end
    function ui.buttons(buttons)
        for _, button in ipairs(buttons) do seen.buttons[button[1]] = button[2]; ui.help(button[3]); end
    end
    return ui, seen;
end

local settings = defaults.make();
local view = readouts.sample('Leveling');
view.sync_active = false;
eq(details.sync_summary(view), 'Level Sync is off', 'Inactive sync uses plain state');
view.sync_active, view.sync_gap = true, 3;
eq(details.sync_summary(view), 'Level Sync is active', 'Active sync uses client status');
view.sync_active = nil;
eq(details.sync_summary(view), 'Level Sync status unknown', 'Missing sync status is not inactive');
view.sync_active, view.no_exp_reason = true, nil;
local plans = 0;
local services = { sync_plan = function() plans = plans + 1; return 30; end };
local ui, seen = controls();
details.draw(settings, view, services, ui);
local words = table.concat(seen.words, '\n');
eq(includes(words, 'Level Sync is active'), true, 'Client sync status is visible');
eq(includes(words, 'Level difference: 3'), true, 'Client level difference is visible');
eq(includes(words, 'EXP/HR already includes any Level Sync penalty.'), true, 'Rate needs no manual penalty deduction');
eq(includes(words, 'No EXP:'), false, 'No speculative no-EXP explanation');
eq(includes(words, 'Current sampled tier'), false, 'Live view omits tier jargon');
eq(includes(words, 'Server report age'), false, 'Live view omits age jargon');
eq(seen.sections['Advanced sync estimate'], false, 'Scenario planner is folded by default');
eq(seen.sections['Recent rewards'], false, 'Reward statistics are folded');
eq(seen.sections['Owned EXP rings'], false, 'Inventory details are folded');
eq(plans, 0, 'Collapsed scenario is not calculated');
eq(seen.picks['Estimated players online'], nil, 'Population selector absent from main view');
eq(includes(table.concat(seen.help, '\n'), 'planner below estimates a penalty'), true, 'Hover help describes the manual planner');
ui, seen = controls({ ['Advanced sync estimate'] = true });
details.draw(settings, view, services, ui);
words = table.concat(seen.words, '\n');
eq(plans, 1, 'Expanded scenario calculates');
eq(includes(words, 'This is an estimate for the choices below, not your current penalty.'), true, 'Scenario remains visibly separate from applied status');
eq(includes(words, 'Estimated penalty: 30%'), true, 'Scenario result is labeled estimate');
eq(seen.picks['Estimated players online'], true, 'Planner names assumption');
eq(includes(words, 'Level Sync is active'), true, 'Planning preserves observed sync status');
view.no_exp_reason = 'distance';
ui, seen = controls();
details.draw(settings, view, services, ui);
eq(includes(table.concat(seen.words, '\n'), 'No EXP: too far from the monster'), true, 'Actual server reason is shown');
view.no_exp_reason, view.food, view.dedication = nil, false, false;
ui, seen = controls();
details.draw(settings, view, services, ui);
words = table.concat(seen.words, '\n');
eq(includes(words, 'Food: None'), true, 'Inactive food stays concise');
eq(includes(words, 'Dedication: Inactive'), true, 'Inactive bonus stays concise');
eq(includes(words, 'Bonus left:'), false, 'Inactive Dedication hides unavailable pool');
eq(includes(words, 'Food time remaining: Unknown'), false, 'Inactive food does not show redundant unknown timer');
view.dedication, view.dedication_seconds = true, 90;
ui, seen = controls();
details.draw(settings, view, services, ui);
words = table.concat(seen.words, '\n');
eq(includes(words, 'Dedication: Active   |   1:30 left'), true, 'Client Dedication status and timer remain visible');
eq(includes(words, 'Bonus left:'), false, 'No live remaining-bonus value is offered');
eq(includes(words, 'server support'), false, 'No server installation is suggested');
view.dedication_seconds = nil;
ui, seen = controls();
details.draw(settings, view, services, ui);
words = table.concat(seen.words, '\n');
eq(includes(words, 'Dedication: Active'), true, 'Known buff remains visible without a duration');
eq(includes(words, 'Bonus left:'), false, 'No unsupported remaining bonus row appears');
eq(includes(table.concat(seen.help, '\n'), 'not which ring you used or how much bonus EXP is left'), true, 'Help clearly states the client limit');
local ring_demand;
services.rings_visible = function(open)
    ring_demand = open;
    return { available = true, entries = { { name = 'Fresh ring', charges = 0, max_charges = 3, recast = 0 } } };
end;
ui, seen = controls();
details.draw(settings, view, services, ui);
eq(ring_demand, false, 'Closed ring section clears its demand');
ui, seen = controls({ ['Owned EXP rings'] = true });
details.draw(settings, view, services, ui);
eq(ring_demand, true, 'Open ring section requests inventory view');
eq(includes(table.concat(seen.words, '\n'), 'Fresh ring   |   0 / 3 charges'), true, 'Opening section uses fresh snapshot in same frame');
services.rings_visible = function() return { available = true, incomplete = true, entries = { { name = 'Confirmed ring', charges = 1, max_charges = 3 } } }; end;
ui, seen = controls({ ['Owned EXP rings'] = true });
details.draw(settings, view, services, ui);
eq(includes(table.concat(seen.words, '\n'), 'Confirmed ring   |   1 / 3 charges'), true, 'Partial inventory scans keep confirmed ring data');
eq(includes(table.concat(seen.words, '\n'), 'Some items could not be read. You may have other EXP rings that are not listed.'), true, 'Partial scan warns that other rings can be absent');

local alert_groups = {
    { 'Food', { 'food_soon' } },
    { 'EXP chains', { 'chain_soon' } },
    { 'Dedication', { 'dedication_end' } },
    { 'EXP rings', { 'ring_ready' } },
    { 'Levels and merit points', { 'level', 'merit', 'cap', 'goal' } },
    { 'Missed EXP', { 'no_exp' } },
};
local saved_alerts = history.copy(settings.alerts);
ui, seen = controls();
details.alerts(settings, view, {}, ui);
for _, group in ipairs(alert_groups) do
    eq(seen.sections[group[1]], false, group[1] .. ' is folded by default');
    eq(seen.summaries[group[1]], '0 on', group[1] .. ' reports all alerts off while folded');
end
eq(seen.sections['Quiet conditions'], false, 'Quiet conditions keeps its saved section key');
eq(seen.summaries['Quiet conditions'], nil, 'Mute settings do not show an enabled-alert count');
eq(next(seen.checks), nil, 'Collapsed alert groups draw no checkboxes');
eq(next(seen.combos), nil, 'Collapsed alert groups draw no sound pickers');
eq(history.equal(settings.alerts, saved_alerts), true, 'Rendering collapsed groups preserves saved alert choices');
local counted = defaults.make();
counted.alerts.food_enabled = true;
counted.alerts.events.food_soon.visual, counted.alerts.events.food_soon.sound = true, true;
counted.alerts.events.chain_soon.sound = true;
counted.alerts.events.dedication_end.visual = true;
counted.alerts.events.ring_ready.sound = true;
counted.alerts.events.level.visual, counted.alerts.events.merit.sound = true, true;
counted.alerts.events.cap.visual, counted.alerts.events.cap.sound = true, true;
counted.alerts.events.no_exp.sound = true;
local count_scans, count_plays, count_tests = 0, 0, 0;
local count_services = {
    sound_files = function() count_scans = count_scans + 1; return {}; end,
    sound_play = function() count_plays = count_plays + 1; end,
    notification_test = function() count_tests = count_tests + 1; end,
};
local counted_before = history.copy(counted.alerts);
ui, seen = controls();
details.alerts(counted, view, count_services, ui);
for _, expected in ipairs({ { 'Food', '2 on' }, { 'EXP chains', '1 on' }, { 'Dedication', '1 on' },
    { 'EXP rings', '1 on' }, { 'Levels and merit points', '3 on' }, { 'Missed EXP', '1 on' } }) do
    eq(seen.summaries[expected[1]], expected[2], expected[1] .. ' counts enabled alerts rather than enabled outputs');
end
eq(seen.summaries['Quiet conditions'], nil, 'Muted conditions are separate from alert counts');
eq(count_scans, 0, 'Closed enabled groups calculate counts without reading sound files');
eq(count_plays, 0, 'Counting enabled sound alerts never plays sound');
eq(count_tests, 0, 'Counting enabled alerts never runs a notification test');
eq(next(seen.checks), nil, 'Enabled counts do not open their groups');
eq(history.equal(counted.alerts, counted_before), true, 'Counting preserves saved flags, files, volumes, and thresholds');
counted.alerts.food_enabled = false;
counted.alerts.events.food_soon.visual, counted.alerts.events.food_soon.sound = false, false;
ui, seen = controls();
details.alerts(counted, view, count_services, ui);
eq(seen.summaries.Food, '0 on', 'Counts refresh when both food alerts are disabled');
eq(count_scans, 0, 'Refreshing folded counts still needs no sound scan');
for _, group in ipairs(alert_groups) do
    ui, seen = controls({ [group[1]] = true });
    details.alerts(settings, view, {}, ui);
    local expected = {};
    for _, id in ipairs(group[2]) do
        expected[id] = true;
        local checks = seen.checks[settings.alerts.events[id]];
        eq(checks ~= nil, true, group[1] .. ' exposes ' .. id);
        eq(checks.visual.title, 'Show notice', id .. ' has a direct visual choice');
        eq(checks.sound.title, 'Play sound', id .. ' has a direct sound choice');
        for _, alert in ipairs(defaults.ALERTS) do
            if alert[1] == id then eq(includes(table.concat(seen.words, '\n'), alert[2]), true, id .. ' keeps its player-facing name'); end
        end
    end
    for id, event in pairs(settings.alerts.events) do
        if not expected[id] then eq(seen.checks[event], nil, group[1] .. ' excludes unrelated ' .. id); end
    end
end

ui, seen = controls({ ['Levels and merit points'] = true });
details.alerts(settings, view, { notification_problem = function() return 'A sound file is unavailable.'; end }, ui);
eq(seen.combos.Sound, nil, 'Disabled regular alerts hide sound controls');
eq(seen.sliders['Time between alerts'], nil, 'Disabled regular alerts hide timing controls');
eq(includes(table.concat(seen.words, '\n'), 'A sound file is unavailable.'), false, 'Disabled alerts hide inactive sound errors');
local level = settings.alerts.events.level;
level.file, level.volume, level.cooldown = 'Saved-level.wav', 37, 23;
seen.checks[level].visual.set(true);
eq(level.visual, true, 'Notice checkbox changes its saved key');
eq(level.sound, false, 'Notice checkbox does not enable sound');
eq(seen.changed, 1, 'Notice checkbox saves through the normal change path');
ui, seen = controls({ ['Levels and merit points'] = true });
details.alerts(settings, view, { notification_problem = function() return 'A sound file is unavailable.'; end }, ui);
eq(seen.summaries['Levels and merit points'], '1 on', 'Notice checkbox updates the group count on the next draw');
eq(seen.combos.Sound, nil, 'Notice-only alert needs no sound picker');
eq(seen.sliders['Time between alerts'], true, 'Notice-only alert keeps its cooldown');
eq(includes(table.concat(seen.words, '\n'), 'A sound file is unavailable.'), true, 'Enabled alert retains its error feedback');
seen.checks[level].sound.set(true);
eq(level.visual, true, 'Adding sound preserves the notice choice');
ui, seen = controls({ ['Levels and merit points'] = true });
details.alerts(settings, view, {}, ui);
eq(seen.summaries['Levels and merit points'], '1 on', 'Notice and sound together still count as one alert');
eq(type(seen.combos.Sound), 'function', 'Sound picker appears only when sound is enabled');
eq(seen.sliders['Sound volume'], true, 'Sound volume remains adjustable');
seen.checks[level].visual.set(false);
eq(level.sound, true, 'Sound-only alert remains enabled when notice is unchecked');
seen.checks[level].sound.set(false);
eq(level.file, 'Saved-level.wav', 'Disabling an alert preserves its saved sound file');
eq(level.volume, 37, 'Disabling an alert preserves its saved volume');
eq(level.cooldown, 23, 'Disabling an alert preserves its saved cooldown');
settings.alerts.events.dedication_end.visual = true;
ui, seen = controls({ Dedication = true });
details.alerts(settings, view, {}, ui);
eq(seen.sliders['Bonus EXP remaining'], nil, 'Dedication no longer offers an unsupported threshold');
eq(includes(table.concat(seen.help, '\n'), 'game reports that your Dedication effect wore off'), true, 'Client Dedication wear-off help remains available');

local plays, refreshes, notification_tests, clicked = 0, 0, {}, nil;
local original_button, original_push, original_pop = imgui.Button, imgui.PushID, imgui.PopID;
local ids = {};
imgui.PushID = function(id) ids[#ids + 1] = id; original_push(id); end;
imgui.PopID = function() table.remove(ids); original_pop(); end;
imgui.Button = function(label)
    if clicked and clicked.label == label and (not clicked.id or clicked.id == ids[#ids]) then clicked = nil; return true; end
    return false;
end;
local food_services = {
    sound_files = function() return { 'Custom.wav' }; end,
    sound_play = function() plays = plays + 1; return false, 'Food sound unavailable.'; end,
    sound_refresh = function() refreshes = refreshes + 1; end,
    notification_test = function(id) notification_tests[#notification_tests + 1] = id; end,
};
settings.alerts.food_sound, settings.alerts.food_volume = 'Saved.wav', 37;
ui, seen = controls({ Food = true });
details.alerts(settings, view, food_services, ui);
eq(seen.summaries.Food, '0 on', 'Unchecked legacy food checkbox keeps the group count off');
eq(plays, 0, 'Opening Food does not play sound');
eq(#notification_tests, 0, 'Opening alert groups does not run tests');
eq(seen.checks[settings.alerts].food_enabled.title, 'Play sound', 'Food-end alert has its direct sound checkbox');
eq(seen.checks[settings.alerts].food_enabled.value, false, 'Saved food disabled setting is respected');
eq(seen.values.Sound, 'Saved.wav', 'Existing food sound selection is preserved');
eq(settings.alerts.food_volume, 37, 'Existing food volume is preserved');
eq(seen.sliders['Sound volume'], true, 'Food volume remains available while off');
eq(seen.sliders['Time between alerts'], nil, 'Food-end sound does not invent a cooldown');
eq(settings.alerts.events.food_end, nil, 'Legacy food settings schema is retained');
eq(includes(table.concat(seen.help, '\n'), 'Loading, zoning, and turning this on stay quiet.'), true, 'Food-end uncertainty rules are retained');
clicked = { label = 'Play##food_sound' };
ui, seen = controls({ Food = true });
details.alerts(settings, view, food_services, ui);
eq(plays, 1, 'Explicit Play works while the food notification is off');
eq(settings.alerts.food_enabled, false, 'Testing does not enable the food notification');
eq(#notification_tests, 0, 'Food test uses the existing sound service only');
eq(includes(table.concat(seen.words, '\n'), 'Food sound unavailable.'), true, 'Food playback failure remains visible');
seen.checks[settings.alerts].food_enabled.set(true);
eq(settings.alerts.food_enabled, true, 'Food checkbox updates the legacy enable key');
eq(seen.changed, 1, 'Food enable is saved through the UI change path');
seen.combos.Sound('Custom.wav');
eq(settings.alerts.food_sound, 'Custom.wav', 'Food sound picker updates the legacy file key');
eq(plays, 1, 'Editing the enable and file choices never starts playback');
clicked = { label = 'Refresh##food_sound' };
ui, seen = controls({ Food = true });
details.alerts(settings, view, food_services, ui);
eq(seen.summaries.Food, '1 on', 'Food checkbox updates the next group count through its legacy key');
eq(refreshes, 1, 'Refresh still uses the existing sound folder service');
eq(includes(table.concat(seen.words, '\n'), 'Food sound unavailable.'), false, 'Refresh clears stale playback error');
seen.checks[settings.alerts].food_enabled.set(false);
eq(settings.alerts.food_enabled, false, 'Food checkbox disables the existing notification key');
clicked = { label = 'Test notification', id = 'dedication_end' };
ui, seen = controls({ Dedication = true });
details.alerts(settings, view, food_services, ui);
eq(seen.summaries.Food, '0 on', 'Unchecking food updates the count even when its group is closed');
eq(#notification_tests, 1, 'Explicit test invokes one selected alert');
eq(notification_tests[1], 'dedication_end', 'Repeated test-button labels keep separate event IDs');
eq(plays, 1, 'Regular alert test does not invoke the food service');
eq(#ids, 0, 'All per-alert ImGui IDs are balanced');
imgui.Button, imgui.PushID, imgui.PopID = original_button, original_push, original_pop;
local scans = 0;
local sound_services = { sound_files = function() scans = scans + 1; return { 'Saved-level.wav' }; end };
ui, seen = controls();
details.alerts(settings, view, sound_services, ui);
eq(scans, 0, 'Collapsed groups do not request sound files');
ui, seen = controls({ ['Levels and merit points'] = true });
details.alerts(settings, view, sound_services, ui);
eq(scans, 0, 'Open disabled alerts do not request sound files');
settings.alerts.events.level.sound, settings.alerts.events.merit.sound = true, true;
ui, seen = controls({ ['Levels and merit points'] = true });
details.alerts(settings, view, sound_services, ui);
eq(seen.summaries['Levels and merit points'], '2 on', 'Separate enabled alerts each contribute to the count');
eq(scans, 1, 'Multiple sound controls share one file lookup per render');

local current = { id = '1001:1', name = 'Current camp', active = true, created = 1, saved = 2 };
local archived = { id = '1001:2', name = 'Old camp', created = 1, saved = 2 };
local saved_args, renamed_id;
services = {
    session_list = function() return { current, archived }; end,
    session_current = function() return current; end,
    session_save = function(...) saved_args = select('#', ...); return true; end,
    session_rename = function(id) renamed_id = id; return true; end,
    session_problem = function() return 'The history file could not be saved.'; end,
};
ui, seen = controls();
details.sessions(settings, view, services, ui);
eq(seen.sections['Session storage'], false, 'Storage settings folded by default');
eq(includes(table.concat(seen.words, '\n'), 'The history file could not be saved.'), true, 'Storage failure stays visible');
eq(seen.buttons['Start new session'], nil, 'History does not duplicate main reset control');
eq(#seen.choices['Session record'], 1, 'Active checkpoint is excluded from saved history');
eq(seen.choices['Session record'][1].value, archived.id, 'Completed session selected without duplicate current row');
eq(seen.buttons['Save current session'], nil, 'Checkpoint action moved to Current session');
seen.combos['Session record'](archived.id);
ui, seen = controls();
details.sessions(settings, view, services, ui);
seen.buttons['Rename selected']();
eq(renamed_id, archived.id, 'Rename targets chosen record');
ui, seen = controls();
details.current_session(settings, view, services, ui);
eq(#seen.words, 0, 'Current session controls do not repeat totals');
seen.buttons['Save current session']();
eq(saved_args, 0, 'Saving current does not rename it with archived record name');
seen.buttons['Rename current session']();
eq(renamed_id, current.id, 'Current rename targets current session independently');
ui, seen = controls({ ['Saved sessions'] = false });
details.current_session(settings, view, services, ui);
eq(includes(table.concat(seen.words, '\n'), 'Current session renamed.'), true, 'Current action feedback stays in Current session with history collapsed');
current.active = false;
ui, seen = controls();
details.sessions(settings, view, services, ui);
eq(#seen.choices['Session record'], 1, 'Current identity is excluded even if active flag is stale');
services.session_list = function() return { current }; end;
ui, seen = controls();
details.sessions(settings, view, services, ui);
eq(seen.combos['Session record'], nil, 'Only-current history omits empty record picker');
eq(includes(table.concat(seen.words, '\n'), 'No other sessions saved yet.'), true, 'Only-current history gives concise empty state');
ui, seen = controls();
details.current_session(settings, view, services, ui);
eq(type(seen.buttons['Rename current session']), 'function', 'Current rename still available with empty history');
eq(type(seen.buttons['Save current session']), 'function', 'Current checkpoint still available with empty history');
ui, seen = controls({ ['Saved sessions'] = false });
details.sessions(settings, view, services, ui);
eq(includes(table.concat(seen.words, '\n'), 'The history file could not be saved.'), true, 'Folded history still displays storage failure');
return { count = count };
