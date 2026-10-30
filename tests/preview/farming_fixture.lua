local settings = PREVIEW.settings;
local services = PREVIEW.services;
local item = { id = 833, name = 'Silk thread', stack_size = 12, count = 9, rate = 18, last_seconds = 24 };
settings.window.tab = 'Farming';
settings.window.sections['Farming/Farming options'] = false;
settings.window.sections['Farming/Watched items and goal'] = true;
settings.window.sections['Farming/Estimated loot value'] = true;
settings.window.sections['Farming/Items received'] = false;
settings.window.sections['Farming/Recent items'] = false;
settings.window.sections['Farming/Gil and bag space'] = false;
settings.farming.selected_item, settings.farming.goal = 0, 1;
settings.farming.wanted, settings.farming.prices = {}, {};
PREVIEW.view.farming = { total = 9, rate = 18, elapsed = 1800, selected = { id = 833, count = 9, goal = 12 },
    recent = { { item_id = 833, count = 1 } }, estimated_value = 900, value_rate = 1800 };
PREVIEW.farming_searches = 0;
services.farming_items = function(query)
    assert(query == 'silk', 'The item query changed');
    PREVIEW.farming_searches = PREVIEW.farming_searches + 1;
    return { item }, PREVIEW.farming_searches == 1;
end;
services.farming_item = function(id) return id == 833 and item or nil; end;
services.farming_rows = function() return { item }; end;
services.farming_summary = function() return 'Items 9 | Net gil 1,900'; end;
services.copy = function(text) PREVIEW.farming_copied = text; end;
function PREVIEW.assert_farming_selected()
    assert(settings.farming.selected_item == 833, 'Search did not select the item');
    assert(settings.farming.wanted['833'], 'Selected result is not watched');
    assert(settings.farming.stack_size == 12, 'Selected item uses the wrong stack size');
    assert(PREVIEW.farming_searches == 2, 'Completed search keeps polling resources');
    assert(PREVIEW.view.farming.total == 9, 'Editing settings changed recorded drops');
end;
