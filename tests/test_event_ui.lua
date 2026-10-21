local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local events = require('ui.events');
local details = require('ui.details');
local checks = 0;
local function eq(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function controls(opened)
    local seen = { text = {}, sections = {}, buttons = {}, checks = {}, combos = {}, inputs = {}, changed = 0 };
    local ui = {};
    function ui.note(text) seen.text[#seen.text + 1] = text; end
    function ui.help() end
    ui.tip = ui.help;
    function ui.section(title, _, initial, summary)
        seen.sections[title] = summary or true;
        if opened[title] ~= nil then return opened[title]; end
        return initial == true;
    end
    function ui.checkbox(value, key, title) seen.checks[title] = { value = value, key = key }; end
    function ui.slider() end
    function ui.input(value, key, title) seen.inputs[title] = { value = value, key = key }; end
    function ui.combo(title, current, choices, select) seen.combos[title] = { current = current, choices = choices, select = select }; end
    function ui.buttons(buttons) for _, button in ipairs(buttons) do seen.buttons[button[1]] = button[2]; end end
    function ui.changed() seen.changed = seen.changed + 1; end
    return ui, seen;
end
local function has(seen, part)
    for _, line in ipairs(seen.text) do if line:find(part, 1, true) then return true; end end
    return false;
end

local settings, view = defaults.make(), readouts.sample('Limbus');
view.events.assault_completed = { [1] = true, [11] = false };
view.events.assault_current = 11;
view.events.inventory_available, view.events.inventory = true, { [1126] = 4, [1875] = 2, [1904] = 1 };
view.account_cooldowns = { dynamis = { remaining = 3600 }, limbus = { remaining = 7200, reminder = true } };
local copied, selected;
local services = { copy = function(text) copied = text; end, bar_mode = function(kind) selected = kind; end };
local opened = {
    ['Event tracking options'] = true, ['Event objectives'] = true, ['Event treasure'] = true,
    ['Entry items and balances'] = true, ['Entry cooldowns'] = true, ['Account timers'] = true,
    ['Assault mission checklist'] = true, ['Wanted event drops'] = true, ['Fight reference'] = true,
};
local ui, seen = controls(opened);
events.draw(settings, view, services, ui);
eq(has(seen, 'NW Apollyon'), true, 'Current run name shown');
eq(has(seen, '~18:44'), true, 'Estimated countdown clearly marked');
eq(has(seen, 'Ancient Beastcoins: found 12'), true, 'Found and personal coin totals are visible');
eq(has(seen, 'Leujaoam Cleansing: Complete'), true, 'Observed Assault clear shown');
eq(has(seen, 'Imperial Agent Rescue: Not complete'), true, 'Observed incomplete mission is separate');
eq(has(seen, 'Excavation Duty: Not observed'), true, 'Missing mission record stays unknown');
eq(has(seen, 'Report status has not been observed'), true, 'Unknown report status does not invent a reminder');
eq(has(seen, 'Inventory: Beastmen\'s Seals 4'), true, 'Carried seals are separate from stored balance');
eq(has(seen, 'Ivory Chip: 1 in Inventory'), true, 'Carried entry chips are listed');
eq(has(seen, 'Dynamis account timer:'), true, 'Dynamis account timer is available');
eq(has(seen, 'Limbus account reminder:'), true, 'Limbus shared reminder is labeled separately');
eq(seen.inputs['Account group'].key, 'group', 'Account grouping uses editable local nickname');
eq(seen.checks['Share Limbus reminder'].key, 'share_limbus', 'Shared Limbus reminder can be disabled');
eq(seen.combos['ENM wait on bar'].current, 'Current ENM', 'ENM wait follows current group by default');
seen.combos['ENM wait on bar'].select(1);
eq(settings.events.enm_group, 1, 'A particular ENM group can be chosen');
seen.buttons['Edit KSNM bar']();
eq(selected, 'ksnm', 'Edit action chooses correct saved bar');
eq(settings.window.tab, 'Display', 'Edit action opens familiar controls');
seen.buttons['Copy event summary']();
eq(copied:find('Drops found: 12 | Received: 0', 1, true) ~= nil, true, 'Copy preserves found versus received distinction');
eq(view.events.remaining, 1124, 'UI actions do not change timer');
eq(view.events.coins_found, 12, 'UI actions do not clear run totals');
local wanted = 0;
for title in pairs(seen.checks) do if title:find('##event_wanted_', 1, true) then wanted = wanted + 1; end end
eq(wanted <= 20 and wanted > 0, true, 'Large drop catalog renders one bounded page');
seen.combos['Fight type'].select('enm');
ui, seen = controls(opened); events.draw(settings, view, services, ui);
local fight = seen.combos.Fight.choices[1];
eq(type(fight.name), 'string', 'Source-backed ENM reference choices available');
seen.combos.Fight.select(fight.value);
ui, seen = controls(opened); events.draw(settings, view, services, ui);
eq(has(seen, 'Shared key-item wait:'), true, 'Reference identifies shared ENM group');
eq(has(seen, 'Entry key item:'), true, 'Reference lists entry key item');

settings.alerts.events.event_time.visual = true;
settings.alerts.events.event_drop.sound = true;
ui, seen = controls({ ['Assault and battlefields'] = false });
details.alerts(settings, view, services, ui);
eq(seen.sections['Assault and battlefields'], '2 on', 'Collapsed event alert type reports enabled count');
eq(seen.checks['Play sound'], nil, 'Closed alert group hides detailed controls');
view.events = { active = false, cooldowns = {}, currencies = {}, history = {}, entry_items = {} };
ui, seen = controls({}); events.draw(settings, view, services, ui);
eq(has(seen, 'Enter an Assault, Limbus route'), true, 'Inactive event explains how tracking starts');
eq(has(seen, 'Time left:'), false, 'Inactive run does not display a made-up timer');
return { count = checks };
