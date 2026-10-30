local defaults = require('ui.defaults');
local farming = require('ui.farming');
local imgui = require('imgui');
local count = 0;
local function equal(actual, expected, title)
    count = count + 1;
    assert(actual == expected, title .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local settings = defaults.make();
local opened, inputs, notices, shown_inputs = {}, {}, {}, {};
local changed, searches, rows_read, metadata_read, copied, space_reads = 0, 0, 0, 0, nil, 0;
local silk = { id = 833, name = 'Silk thread', stack_size = 12, count = 9, rate = 18, last_seconds = 24 };
local view = { farming = { total = 9, rate = 18, elapsed = 1800, selected = { id = 833, count = 9, goal = 12 },
    recent = { { item_id = 833, count = 1 } }, estimated_value = 900, value_rate = 1800 },
    gil = { current = 12000, gained = 2000, spent = 100, net = 1900, rate = 3800 },
    storage = { inventory = { free = 18 }, satchel = { free = 27 } } };
local services = {
    farming_item = function(id) metadata_read = metadata_read + 1; return id == 833 and silk or nil; end,
    farming_items = function(term)
        searches = searches + 1;
        equal(term, 'silk', 'Search receives the player\'s query');
        return { silk }, searches == 1;
    end,
    farming_rows = function() rows_read = rows_read + 1; return { silk }; end,
    farming_summary = function() return 'Items 9 | Net gil 1,900'; end,
    copy = function(text) copied = text; end,
    farming_storage_visible = function(visible)
        if visible then space_reads = space_reads + 1; return { inventory = { free = 21 }, satchel = { free = 22 } }; end
    end,
};
local ui = {
    section = function(title) return opened[title] == true; end,
    note = function(text) notices[#notices + 1] = text; end,
    help = function() end, tip = function() end,
    changed = function() changed = changed + 1; end,
    slider = function() end, pick = function() end,
    checkbox = function(options, key, title)
        local value = { options[key] == true };
        if imgui.Checkbox(title, value) then options[key] = value[1]; changed = changed + 1; end
    end,
    buttons = function(buttons)
        for _, button in ipairs(buttons) do if imgui.Button(button[1]) then button[2](); end end
    end,
};
imgui.InputTextWithHint = function(label, _, values)
    shown_inputs[label] = values[1];
    if inputs[label] ~= nil then values[1] = inputs[label]; return true; end
    return false;
end;
local function draw(click)
    if click then MOCK.clicks[click] = true; end
    farming.draw(settings, view, services, ui);
end
draw();
equal(searches, 0, 'Collapsed Farming sections do not search resources');
equal(rows_read, 0, 'Collapsed item breakdown does not request rows');
equal(metadata_read, 0, 'Collapsed sections do not look up names');
equal(space_reads, 0, 'Collapsed bag details do not request slot reads');

opened['Watched items and goal'] = true;
inputs['##Find farming item'] = 's';
draw();
equal(searches, 0, 'One letter does not start a broad search');
inputs['##Find farming item'] = 'silk';
draw(); draw(); draw();
equal(searches, 2, 'Search continues while busy then reuses completed results');
draw('Silk thread##farm_result_833');
inputs['##Find farming item'] = nil;
equal(settings.farming.selected_item, 833, 'A search result selects the item');
equal(settings.farming.wanted['833'], true, 'A search result adds the watched item');
equal(settings.farming.stack_size, 12, 'The goal uses the selected item\'s stack size');
equal(view.farming.total, 9, 'Selecting an item keeps recorded totals');
draw('Watch this item');
equal(settings.farming.wanted['833'], false, 'Unchecking removes the watched alert target');
equal(settings.farming.selected_item, 833, 'Removing a watch does not clear selected readouts');

opened['Estimated loot value'] = true;
inputs['##Farming unit price'] = '250';
draw('Save item price');
equal(settings.farming.prices['833'], 250, 'Manual price is saved per individual item');
equal(view.gil.net, 1900, 'Entering a price never changes actual gil');
equal(view.farming.total, 9, 'Entering a price never changes item totals');
inputs['##Farming unit price'] = nil;
draw('Clear item price');
equal(settings.farming.prices['833'], nil, 'Clearing a price leaves the item unpriced');
settings.farming.prices['833'] = 250;
draw();
inputs['##Farming unit price'] = '999';
draw();
inputs['##Farming unit price'] = nil;
draw();
equal(shown_inputs['##Farming unit price'], '999', 'An unsaved price draft stays while editing the same settings');
local other_farming = defaults.make().farming;
other_farming.selected_item, other_farming.prices['833'] = 833, 250;
settings.farming = other_farming;
draw();
equal(shown_inputs['##Farming unit price'], '250', 'A new character or profile cannot inherit another settings table\'s price draft');

opened['Items received'] = true;
draw();
equal(rows_read, 1, 'Opening item breakdown requests the current rows');
opened['Items received'] = false;
draw();
equal(rows_read, 1, 'Closing the breakdown stops row requests');
opened['Gil and bag space'] = true;
draw();
equal(space_reads, 1, 'Open bag details request current slot counts');
local shown_space = false;
for _, text in ipairs(notices) do if text == 'Mog Satchel free: 22' then shown_space = true; end end
equal(shown_space, true, 'Bag details use freshly requested counts');
opened['Gil and bag space'] = false;
draw();
equal(space_reads, 1, 'Closing bag details stops extra slot reads');
opened['Farming options'] = true;
draw('Copy farming summary');
equal(copied, 'Items 9 | Net gil 1,900', 'Summary copies locally through the existing service');
equal(#MOCK.commands, 0, 'Farming settings send no game commands');
equal(changed > 0, true, 'Saved Farming edits mark settings dirty');
farming.cancel_pending();
opened['Watched items and goal'] = true;
draw();
equal(searches, 2, 'Closing settings clears a pending search without restarting it');
return { count = count };
