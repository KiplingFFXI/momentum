local defaults = require('ui.defaults');
local history = require('ui.history');
local modes = require('ui.modes');
local profiles = require('ui.profiles');
local count = 0;
local function eq(actual, expected, message)
    count = count + 1;
    assert(actual == expected, message .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local function shown(settings)
    local result = {};
    for _, id in ipairs(settings.display.order) do
        if settings.display.enabled[id] then result[#result + 1] = id; end
    end
    return table.concat(result, ',');
end

local settings = defaults.make();
eq(settings.farming.auto_layout, false, 'Automatic Farming starts off');
eq(settings.farming.goal_fill, false, 'Farming goal fill starts off');
eq(settings.farming.space_bag, 'inventory', 'Only current Inventory is selected initially');
for _, alert in ipairs({ 'farm_item', 'farm_goal', 'farm_space' }) do
    eq(settings.alerts.events[alert].visual, false, 'New Farming notices start off');
    eq(settings.alerts.events[alert].sound, false, 'New Farming sounds start off');
end
for _, id in ipairs(defaults.STARTER_LAYOUTS.Farming) do
    if id:sub(1, 5) == 'farm_' then eq(settings.display.enabled[id], false, 'Existing layouts do not enable new readouts'); end
end
settings.display.labels.rate = 'Saved EXP';
settings.display.divider = ' / ';
eq(modes.select(settings, 'farming'), true, 'Farming is directly selectable');
eq(shown(settings), 'farm_items,farm_rate,gil_net,gil_rate,inventory_free', 'Farming starts with a compact item and gil row');
eq(settings.modes.active, 'farming', 'Farming has its own normal-mode bank');
eq(settings.display.divider, ' | ', 'The Farming starter uses compact dividers');
settings.display.labels.farm_rate, settings.display.alignment = 'My items', 'center';
settings.display.dividers.gil_net = false;
settings.display.enabled.food = true;
local farming_display = history.copy(settings.display);
modes.select(settings, 'exp');
eq(settings.display.labels.rate, 'Saved EXP', 'Farming does not overwrite the EXP layout');
eq(settings.display.divider, ' / ', 'EXP keeps its own divider');
modes.select(settings, 'merits');
settings.display.labels.lp_rate = 'Saved LP';
modes.select(settings, 'farming');
eq(history.equal(settings.display, farming_display), true, 'Farming keeps its edits across mode changes');
modes.select(settings, 'dynamis');
eq(settings.dynamis.layout_active, true, 'Dynamis can overlay the Farming bank');
modes.select(settings, 'farming');
eq(settings.dynamis.layout_active, false, 'Manual Farming leaves the Dynamis overlay');
eq(history.equal(settings.display, farming_display), true, 'The saved Farming row returns after Dynamis');
eq(modes.automatic(settings, 'lp'), false, 'Earning LP cannot change a manually chosen Farming layout');
eq(settings.modes.active, 'farming', 'Manual Farming remains selected');

settings = defaults.make();
modes.select(settings, 'merits');
settings.display.labels.lp_rate = 'Prior merits';
settings.farming.auto_layout = true;
modes.select(settings, 'auto');
eq(settings.modes.active, 'farming', 'Choosing Automatic immediately uses the enabled Farming fallback');
eq(settings.modes.farming_previous, 'merits', 'Choosing Automatic retains the previous Merits bank');
settings.farming.auto_layout = false;
eq(modes.automatic(settings, nil), true, 'Disabling the fallback can restore the previous bank without earning-mode data');
eq(settings.modes.active, 'merits', 'Disabling the fallback restores Merits after directly choosing Automatic');
eq(settings.display.labels.lp_rate, 'Prior merits', 'Returning from the fallback keeps the previous Merits edits');

settings = defaults.make();
modes.select(settings, 'merits');
settings.display.labels.lp_rate = 'My merit rate';
modes.select(settings, 'auto');
settings.farming.auto_layout = true;
eq(modes.automatic(settings, nil), true, 'Automatic Farming does not require EXP or LP');
eq(settings.modes.active, 'farming', 'Automatic chooses the Farming bank');
eq(settings.modes.farming_previous, 'merits', 'The previous normal bank is retained');
settings.display.labels.farm_items = 'My loot';
eq(modes.automatic(settings, 'exp'), false, 'Earning-mode changes do not replace Automatic Farming');
eq(settings.display.labels.farm_items, 'My loot', 'Automatic keeps Farming edits');
settings.farming.auto_layout = false;
eq(modes.automatic(settings, nil), true, 'Turning Farming off restores a normal bank without a new reward');
eq(settings.modes.active, 'merits', 'The previous Merits bank returns');
eq(settings.display.labels.lp_rate, 'My merit rate', 'The previous Merits settings remain');
settings.display.auto_layout = true;
settings.farming.auto_layout = true;
modes.automatic(settings, 'lp');
settings.events.active_kind = 'limbus';
eq(modes.automatic(settings, 'exp'), false, 'An event overlay retains priority over Automatic Farming');
settings.events.active_kind = nil;
settings.dynamis.layout_active = true;
eq(modes.automatic(settings, 'exp'), false, 'Dynamis retains priority over Automatic Farming');
settings.dynamis.layout_active = false;
settings.farming.auto_layout = false;
modes.automatic(settings, 'exp');
eq(settings.modes.active, 'exp', 'Returning to normal automatic switching follows EXP when enabled');
settings.farming.auto_layout = true;
modes.automatic(settings, 'exp');
local capture = profiles.capture(settings);
local restored = defaults.make();
profiles.apply(restored, capture);
defaults.tidy(restored);
eq(restored.modes.active, 'farming', 'A captured profile restores its Farming bank');
eq(restored.display.labels.farm_items, 'My loot', 'A captured profile restores Farming edits');
eq(restored.farming.auto_layout, true, 'A captured profile retains the Automatic fallback option');

restored.farming.selected_item, restored.farming.goal = -3, math.huge;
restored.farming.goal_unit, restored.farming.stack_size = 'bad', 0;
restored.farming.space_bag, restored.farming.low_slots = 'safe', 900;
restored.farming.wanted = { ['4'] = true, ['-1'] = true, bad = true, ['5'] = false };
restored.farming.prices = { ['4'] = 123.75, ['0'] = 1, ['6'] = math.huge, ['7'] = -1, ['8'] = 0 };
defaults.tidy(restored);
eq(restored.farming.selected_item, 0, 'Invalid selected items are disabled');
eq(restored.farming.goal, 0, 'Invalid goals use an empty target');
eq(restored.farming.goal_unit, 'items', 'Invalid units use items');
eq(restored.farming.stack_size, 1, 'Stack size remains positive');
eq(restored.farming.space_bag, 'inventory', 'Unknown bags cannot become tracked bags');
eq(restored.farming.low_slots, 80, 'Slot warnings remain within supported capacity');
eq(restored.farming.wanted['4'], true, 'A valid wanted item survives');
eq(restored.farming.wanted.bad, nil, 'Invalid wanted items are removed');
eq(restored.farming.wanted['5'], nil, 'Disabled wanted items are removed');
eq(restored.farming.prices['4'], 123, 'Unit prices normalize to whole gil');
eq(restored.farming.prices['6'], nil, 'Infinite prices are removed');
eq(restored.farming.prices['7'], nil, 'Negative prices are removed');
eq(restored.farming.prices['8'], 0, 'A known zero value remains known');
restored.farming.space_bag = 'both';
restored.window.tab, restored.preview.scenario = 'Farming', 'Farming';
defaults.tidy(restored);
eq(restored.farming.space_bag, 'both', 'Both supported bags can be chosen');
eq(restored.window.tab, 'Farming', 'The Farming tab survives settings normalization');
eq(restored.preview.scenario, 'Farming', 'The Farming preview survives settings normalization');
return { count = count };
