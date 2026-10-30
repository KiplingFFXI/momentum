local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local modes = require('ui.modes');
local profiles = require('ui.profiles');
local history = require('ui.history');
local count = 0;
local function eq(actual, expected, title)
    count = count + 1;
    assert(actual == expected, title .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local ids = { 'inventory_slots', 'inventory_free', 'satchel_slots', 'satchel_free' };
local settings = defaults.make();
local first;
for index, row in ipairs(defaults.READOUTS) do if row.id == 'inventory_slots' then first = index; break; end end
for index, id in ipairs(ids) do
    eq(defaults.READOUTS[first + index - 1].id, id, 'Storage readouts keep their saved order');
    eq(settings.display.enabled[id], false, id .. ' starts off');
    eq(readouts.needs_character(id), false, id .. ' does not depend on EXP state');
    local help = readouts.definition(id).help;
    eq(help:find('Each stack uses one slot.', 1, true) ~= nil, true, id .. ' explains stacks and slots');
    eq(help:find('pause or reset your session', 1, true) ~= nil, true, id .. ' explains live counts');
    eq(help:find('-- means', 1, true) ~= nil, true, id .. ' explains unknowns');
end
eq(defaults.READOUTS[first - 1].id, 'kindred_carried', 'Existing readouts stay before storage');
settings.display.order = defaults.copy(ids);
for _, id in ipairs(ids) do settings.display.enabled[id] = true; end
local view = { valid = true, mode = 'exp', storage = {
    inventory = { used = 60, capacity = 80, free = 20 }, satchel = { used = 35, capacity = 80, free = 45 },
} };
local function values()
    local result = {};
    for _, item in ipairs(readouts.cached(settings, view)) do result[item.id] = item.value; end
    return result;
end
eq(values().inventory_slots, '60 / 80', 'Inventory shows occupied slots out of capacity');
eq(values().inventory_free, '20', 'Inventory shows empty slots separately');
eq(values().satchel_slots, '35 / 80', 'Mog Satchel has its own used count');
eq(values().satchel_free, '45', 'Mog Satchel has its own free count');
view.valid, view.paused, view.elapsed = false, true, 0;
eq(values().inventory_slots, '60 / 80', 'Paused or reset EXP state does not hide Inventory');
eq(values().satchel_free, '45', 'Paused or reset EXP state does not hide Mog Satchel');
local before = readouts.cached(settings, view);
view.storage.satchel.free = 44;
eq(values().satchel_free, '44', 'Mog Satchel changes invalidate the visible cache');
eq(readouts.cached(settings, view) ~= before, true, 'A displayed slot change replaces cached items');
before = readouts.cached(settings, view);
view.storage.inventory = { used = 60, capacity = 80, free = 20 };
view.storage.other_bags = { used = 99 };
eq(readouts.cached(settings, view), before, 'Equal numbers and unrelated bag data do not replace cached items');
view.storage.inventory.used, view.storage.inventory.capacity = 61, 81;
eq(values().inventory_slots, '61 / 81', 'Used slots and capacity are both cache dependencies');
view.storage.inventory.free = 19;
eq(values().inventory_free, '19', 'Free slots have their own cache dependency');
view.storage.inventory = nil;
eq(values().inventory_slots, '--', 'Unknown Inventory does not show zero used');
eq(values().inventory_free, '--', 'Unknown Inventory does not show zero free');
eq(values().satchel_slots, '35 / 80', 'Unknown Inventory does not erase known Mog Satchel');
view.storage.satchel = nil;
eq(values().satchel_slots, '--', 'Unknown Mog Satchel stays unknown');
view.storage = nil;
for _, id in ipairs(ids) do eq(values()[id], '--', id .. ' clears when the next character has no storage data'); end
settings.display.conditions.inventory_slots = 'known';
eq(values().inventory_slots, nil, 'Known-only condition hides unknown slot counts');
settings.display.conditions.inventory_slots = 'always';
view.storage = { inventory = { used = 0, capacity = 80, free = 80 }, satchel = { used = 80, capacity = 80, free = 0 } };
eq(values().inventory_slots, '0 / 80', 'A known empty bag shows zero used');
eq(values().satchel_free, '0', 'A known full bag shows zero free');
local live = readouts.cached(settings, view);
local sample = readouts.sample('Leveling');
eq(readouts.cached(settings, sample, true)[1].value, '60 / 80', 'Sample preview has Inventory data');
eq(readouts.cached(settings, view), live, 'Preview cache stays separate from live storage');
eq(readouts.value('satchel_slots', readouts.sample('No data'), settings), '--', 'No-data preview keeps storage unknown');
for _, scenario in ipairs({ 'Leveling', 'Merits', 'Dynamis', 'Assault', 'Limbus', 'BCNM', 'KSNM', 'ENM', 'Paused', 'Capped' }) do
    eq(readouts.value('satchel_free', readouts.sample(scenario), settings), '45', scenario .. ' sample includes Mog Satchel');
end

settings = defaults.make();
settings.display.order = { 'rate', 'food', 'job' };
settings.display.labels.rate = 'My rate';
defaults.tidy(settings);
eq(settings.display.order[1], 'rate', 'Adding readouts keeps the custom first readout');
eq(settings.display.labels.rate, 'My rate', 'Adding readouts keeps custom labels');
for _, mode in ipairs({ 'exp', 'merits', 'dynamis', 'assault', 'limbus', 'bcnm', 'ksnm', 'enm' }) do
    modes.select(settings, mode);
    settings.display.enabled.inventory_slots = true;
    settings.display.labels.inventory_slots = mode .. ' bag';
    defaults.tidy(settings);
end
local captured = profiles.capture(settings);
local restored = defaults.make();
profiles.apply(restored, captured);
defaults.tidy(restored);
for _, mode in ipairs({ 'exp', 'merits', 'dynamis', 'assault', 'limbus', 'bcnm', 'ksnm', 'enm' }) do
    modes.select(restored, mode);
    eq(restored.display.enabled.inventory_slots, true, mode .. ' keeps its saved Storage option through a profile');
    eq(restored.display.labels.inventory_slots, mode .. ' bag', mode .. ' keeps its own Storage label');
end
modes.select(restored, 'exp');
local custom = history.copy(restored.display);
modes.select(restored, 'auto');
eq(restored.display.enabled.inventory_slots, custom.enabled.inventory_slots, 'Automatic keeps the saved EXP Storage option');
eq(restored.display.labels.inventory_slots, custom.labels.inventory_slots, 'Automatic keeps the saved EXP Storage label');
return { count = count };
