local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local modes = require('ui.modes');
local hud = require('ui.hud');
local theme = require('ui.theme');
local count = 0;
local function eq(actual, expected, message)
    count = count + 1;
    assert(actual == expected, message .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local settings, view = defaults.make(), readouts.sample('Farming');
for _, id in ipairs({ 'farm_items', 'farm_rate', 'farm_time', 'farm_last', 'farm_watched', 'farm_watched_rate', 'farm_watched_last',
    'farm_goal', 'farm_pool', 'farm_mob_gil', 'farm_value', 'farm_value_rate' }) do
    eq(readouts.definition(id) ~= nil, true, 'Farming readouts have menu definitions');
    eq(readouts.needs_character(id), false, 'Saved Farming totals are not EXP progress');
end
eq(readouts.value('farm_items', view, settings), '24', 'Received items count individual quantities');
eq(readouts.value('farm_rate', view, settings), '48', 'The farming rate formats normally');
eq(readouts.value('farm_time', view, settings), '30:00', 'Farming uses its own elapsed time');
eq(readouts.value('farm_last', view, settings), '0:14', 'Last-received age uses farming time');
eq(readouts.value('farm_watched', view, settings), 'Shell 6', 'The watched item uses its provided name');
eq(readouts.value('farm_watched_rate', view, settings), '12', 'The watched rate is separate from EXP');
eq(readouts.value('farm_watched_last', view, settings), '0:42', 'The watched item has its own last-received age');
eq(readouts.value('farm_goal', view, settings), '6 / 12', 'The item goal shows unit progress');
eq(readouts.value('farm_pool', view, settings), '32', 'Pool appearances stay separate from personal items');
eq(readouts.value('farm_mob_gil', view, settings), '450', 'Monster gil stays separate from wallet net');
eq(readouts.value('farm_value', view, settings), '~7,200', 'Manual item values are visibly estimated');
eq(readouts.value('farm_value_rate', view, settings), '~14,400', 'Estimated value rates remain separate from actual gil');
settings.farming.goal_unit, settings.farming.stack_size = 'stacks', 12;
eq(readouts.value('farm_goal', view, settings), '0.5 / 1 stacks', 'Stack goals use the selected item stack size');
view.farming.selected.name = nil;
eq(readouts.value('farm_watched', view, settings), 'Item 4 6', 'Missing resource names retain a clear item-ID fallback');
view.farming.selected.id = 0;
eq(readouts.value('farm_watched', view, settings), '--', 'An unselected watched item stays unknown');
eq(readouts.value('farm_goal', view, settings), '--', 'An unselected item has no goal');
eq(readouts.value('farm_watched_last', view, settings), '--', 'An unselected item has no last-received age');
view.farming.total, view.farming.rate = 0, nil;
eq(readouts.value('farm_items', view, settings), '0', 'Zero received items remains known');
eq(readouts.value('farm_rate', view, settings), '--', 'The warm-up rate stays unknown');
view.farming.rate = 0.5;
eq(readouts.value('farm_rate', view, settings), '0.5', 'Slow farming rates do not round down to zero');
view.farming.estimated_value, view.farming.value_rate = nil, nil;
eq(readouts.value('farm_value', view, settings), '--', 'Unpriced loot is not assigned a value');
view.farming.estimated_value = 0;
eq(readouts.value('farm_value', view, settings), '~0', 'Known zero manual value remains visible');

settings.display.order, settings.display.enabled = { 'farm_rate' }, { farm_rate = true };
local previous = readouts.cached(settings, view);
view.farming.rate = 0.54;
eq(readouts.cached(settings, view), previous, 'Undisplayed farming rate precision keeps the same cached row');
view.farming.rate = 0.56;
eq(readouts.cached(settings, view) ~= previous, true, 'A changed displayed farming rate refreshes the row');
settings.display.order, settings.display.enabled = { 'farm_goal' }, { farm_goal = true };
view.farming.selected = { id = 4, count = 6, goal = 12, goal_fraction = 0.5 };
previous = readouts.cached(settings, view);
settings.farming.goal_unit = 'items';
eq(readouts.cached(settings, view) ~= previous, true, 'Changing goal units refreshes its formatted row');
settings.display.order, settings.display.enabled = { 'farm_time' }, { farm_time = true };
view.farming.elapsed = 1800.1;
previous = readouts.cached(settings, view);
view.farming.elapsed = 1800.2;
eq(readouts.cached(settings, view), previous, 'Undisplayed farming timer precision stays cached');

settings, view = defaults.make(), readouts.sample('Farming');
modes.select(settings, 'farming');
settings.bar.docked, settings.bar.auto_width, settings.bar.width = false, false, 600;
settings.display.show_text = false;
local function fills()
    MOCK.imgui_calls = {};
    hud.draw(settings, view, {});
    local amount, width = 0, 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddRectFilled' and call[4] == theme.u32(settings.style.colors.fill) then
            amount, width = amount + 1, width + call[3][1] - call[2][1];
        end
    end
    return amount, width;
end
eq(fills(), 0, 'Farming never shows unrelated EXP progress');
settings.farming.goal_fill = true;
local amount, width = fills();
eq(amount, 1, 'A selected Farming goal can fill the bar');
view.farming.selected.goal_fraction = 0.25;
local quarter, quarter_width = fills();
eq(quarter, 1, 'A partially completed Farming goal still fills');
eq(quarter_width * 2, width, 'The progress amount follows the item goal');
settings.events.active_kind = 'limbus';
view.events = { active = false };
eq(fills(), 0, 'An event overlay never inherits a Farming goal fill');
settings.events.active_kind = nil;
settings.dynamis.layout_active = true;
view.dynamis = { active = false };
eq(fills(), 0, 'An inactive Dynamis overlay does not inherit a Farming goal fill');
settings.dynamis.layout_active = false;
modes.select(settings, 'exp');
eq(fills(), 1, 'The normal EXP fill returns outside Farming');
return { count = count };
