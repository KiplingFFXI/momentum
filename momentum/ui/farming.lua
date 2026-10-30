local imgui = require('imgui');
local bit = require('bit');
local readouts = require('ui.readouts');
local farming = {};
local search = { '' };
local filter = { '' };
local price = { '' };
local search_key, search_rows, searching;
local price_key;
local status;
local page = 1;
local num, time = readouts.format_number, readouts.format_time;

local function known(value)
    return type(value) == 'number' and num(value) or '--';
end

local function item_info(services, id)
    local item = services.farming_item and services.farming_item(id);
    return item or { id = id, name = 'Item ' .. tostring(id), stack_size = 1 };
end

local function select_item(settings, item, ui, watch)
    local options = settings.farming;
    options.selected_item = item.id;
    options.stack_size = math.max(1, tonumber(item.stack_size) or 1);
    if watch then options.wanted[tostring(item.id)] = true; end
    price_key = nil;
    ui.changed();
end

local function options(settings, view, services, ui)
    if not ui.section('Farming options', 'Choose the Farming layout and how its item goal looks. These choices do not reset your session.', true) then return; end
    ui.checkbox(settings.farming, 'auto_layout', 'Use Farming outside events',
        'When Bar mode is Automatic, use Farming outside detected events. Your event layouts still take priority. EXP and LP keep tracking.');
    ui.checkbox(settings.farming, 'goal_fill', 'Use item goal for the Farming bar fill',
        'Fill the Farming bar toward the selected item goal. Without an item goal, its fill stays empty. Other modes keep their usual fill.');
    local farm = view.farming or {};
    ui.note('Items received: ' .. known(farm.total) .. '   |   Items/HR: ' .. known(farm.rate)
        .. '   |   Farming time: ' .. (farm.elapsed and time(farm.elapsed) or '--'));
    ui.help('Item rates need one minute after your first received treasure item. Paused and offline time do not count. Farming time works even when you gain no EXP.');
    ui.note('Pool drops seen: ' .. known(farm.pool_found));
    ui.help('Pool drops seen includes treasure offered to the party. Items received counts only treasure awarded to you.');
    ui.note('Items count personal treasure received. Buying, crafting, and moving items between bags do not add drops.');
    ui.help('Normal treasure-pool loot is counted, including solo drops. Fishing, gathering, digging, and Steal are not included. Pool drops seen is a separate total.');
    if view.farming and view.farming.partial then
        ui.note('Some item history is unavailable. Totals include only loot Momentum recorded.');
    end
    ui.buttons({ { 'Copy farming summary', function()
        if services.copy and services.farming_summary then services.copy(services.farming_summary()); status = 'Farming summary copied.'; end
    end, 'Copy your recorded item and gil totals. This does not send anything to chat.' } });
    if status then ui.note(status); end
end

local function wanted(settings, services, ui)
    if not ui.section('Watched items and goal', 'Choose an item for its readouts and goal. Watched items can also trigger the wanted-item alert.', true) then return; end
    local options = settings.farming;
    imgui.SetNextItemWidth(math.min(400, (imgui.GetContentRegionAvail())));
    imgui.InputTextWithHint('##Find farming item', 'Item name or number', search, 81);
    ui.tip('Enter an item number or at least two letters. Selecting a result watches it and selects it for the item readouts.');
    local term = search[1]:match('^%s*(.-)%s*$');
    if #term >= 2 or term:match('^%d+$') then
        if search_key ~= term or searching then
            search_rows, searching = {}, false;
            if services.farming_items then search_rows, searching = services.farming_items(term); end
            search_rows, search_key = search_rows or {}, term;
        end
        if searching then ui.note('Searching...'); end
        if #search_rows == 0 and not searching then ui.note('No matching items.'); end
        if #search_rows > 0 then
            if imgui.BeginChild('##farming_item_search', { 0, math.min(160, #search_rows * 26 + 8) }, 0) then
                for _, item in ipairs(search_rows) do
                    if imgui.Selectable(item.name .. '##farm_result_' .. item.id, options.selected_item == item.id) then
                        select_item(settings, item, ui, true);
                        search[1], search_key = '', nil;
                    end
                    ui.tip('Watch ' .. item.name .. ' and use it for the selected item count, rate, and goal.');
                end
            end
            imgui.EndChild();
        end
    else search_key, search_rows, searching = nil, nil, false; end

    local ids = {};
    for id, enabled in pairs(options.wanted) do
        id = tonumber(id);
        if enabled == true and id and id > 0 and id <= 65535 and id == math.floor(id) then ids[#ids + 1] = id; end
    end
    table.sort(ids);
    if #ids > 0 then
        ui.note('Watched items: ' .. #ids);
        if imgui.BeginChild('##farming_watched', { 0, math.min(140, math.min(#ids, 25) * 28 + 8) }, 0) then
            for index = 1, math.min(#ids, 25) do
                local item = item_info(services, ids[index]);
                if imgui.Selectable(item.name .. '##farm_watch_' .. item.id, options.selected_item == item.id) then select_item(settings, item, ui); end
            end
        end
        imgui.EndChild();
        if #ids > 25 then ui.note('Use the search above to select another watched item.'); end
    end
    if options.selected_item <= 0 then ui.note('Choose an item above to set its goal or price.'); return; end
    local selected = item_info(services, options.selected_item);
    if options.stack_size ~= selected.stack_size then options.stack_size = selected.stack_size; ui.changed(); end
    ui.note('Selected item: ' .. selected.name);
    ui.checkbox(options.wanted, tostring(selected.id), 'Watch this item',
        'Include this item in the watched list. Wanted-item alerts use this list. Unchecking does not remove its recorded drops.');
    ui.pick(options, 'goal_unit', 'Item goal unit', { { name = 'Items', value = 'items' }, { name = 'Stacks', value = 'stacks' } },
        'Count individual items or full stacks. A stack uses this item\'s normal stack size.');
    ui.slider(options, 'goal', 'Item goal', 0, 9999, '%.0f', 'Set the quantity you want to receive this session. Zero turns the goal off. Ctrl-click the slider to enter an exact amount.');
    options.goal = math.floor(options.goal + 0.5);
    if options.goal_unit == 'stacks' then ui.note('One stack: ' .. known(options.stack_size) .. ' items.'); end
    ui.note('Enable wanted-item and goal notices or sounds under Alerts > Farming.');
end

local function prices(settings, view, services, ui)
    if not ui.section('Estimated loot value', 'Enter your own price per item. Estimated loot value stays separate from actual gil changes.', false) then return; end
    local options = settings.farming;
    if options.selected_item <= 0 then ui.note('Choose an item under Watched items and goal first.'); return; end
    local item = item_info(services, options.selected_item);
    local id = tostring(item.id);
    local current = options.prices[id];
    local key = tostring(options) .. ':' .. id .. ':' .. tostring(current);
    if price_key ~= key then price_key, price[1] = key, current and tostring(current) or ''; end
    ui.note(item.name);
    imgui.SetNextItemWidth(math.min(240, (imgui.GetContentRegionAvail())));
    imgui.InputTextWithHint('##Farming unit price', 'Gil per individual item', price, 16);
    ui.tip('Enter gil per individual item, not per stack. Prices are saved choices, not live auction house prices.');
    local amount = price[1]:match('^%d+$') and tonumber(price[1]);
    imgui.BeginDisabled(not amount or amount > 999999999);
    ui.buttons({ { 'Save item price', function()
        options.prices[id] = amount; price_key = nil; ui.changed();
    end, 'Use this price for received items. This never changes your actual gil.' } });
    imgui.EndDisabled();
    ui.buttons({ { 'Clear item price', function() options.prices[id] = nil; price_key = nil; ui.changed(); end,
        'Remove this estimate. Recorded item quantities stay the same.' } });
    local farm = view.farming or {};
    ui.note('Estimated loot value: ' .. (farm.estimated_value and '~' .. num(farm.estimated_value) or '--')
        .. '   |   Value/HR: ' .. (farm.value_rate and '~' .. num(farm.value_rate) or '--'));
    ui.note('Only priced items are included. Selling loot changes your actual gil separately; these figures are not added together as profit.');
end

local function breakdown(settings, view, services, ui)
    if not ui.section('Items received', 'Personal items recorded this session. Changing this filter only changes the list.', false) then return; end
    imgui.SetNextItemWidth(math.min(400, (imgui.GetContentRegionAvail())));
    if imgui.InputTextWithHint('##Filter farming items', 'Filter received items', filter, 81) then page = 1; end
    local term, rows = filter[1]:lower(), {};
    for _, item in ipairs(services.farming_rows and services.farming_rows() or {}) do
        if term == '' or tostring(item.id) == term or item.name:lower():find(term, 1, true) then rows[#rows + 1] = item; end
    end
    if #rows == 0 then ui.note('No matching items received this session.'); return; end
    local pages = math.max(1, math.ceil(#rows / 25));
    page = math.max(1, math.min(page, pages));
    ui.note('Page ' .. page .. ' / ' .. pages .. '   |   ' .. #rows .. ' item types');
    if imgui.BeginTable('##farming_received', 4, bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_SizingStretchProp)) then
        for _, title in ipairs({ 'Item', 'Received', 'Items/HR', 'Last received' }) do imgui.TableSetupColumn(title); end
        imgui.TableHeadersRow();
        for index = (page - 1) * 25 + 1, math.min(#rows, page * 25) do
            local item = rows[index];
            imgui.TableNextRow(); imgui.TableNextColumn();
            if imgui.Selectable(item.name .. '##farm_received_' .. item.id, settings.farming.selected_item == item.id) then select_item(settings, item, ui); end
            ui.tip('Select this item for its count, rate, goal, or manual price.');
            imgui.TableNextColumn(); imgui.TextUnformatted(known(item.count));
            imgui.TableNextColumn(); imgui.TextUnformatted(known(item.rate));
            imgui.TableNextColumn(); imgui.TextUnformatted(item.last_seconds and time(item.last_seconds) .. ' ago' or '--');
        end
        imgui.EndTable();
    end
    ui.buttons({ { 'Previous items', function() page = math.max(1, page - 1); end },
        { 'Next items', function() page = math.min(pages, page + 1); end } });
    local selected = (view.farming or {}).selected or {};
    if selected.goal and selected.goal > 0 then
        ui.note('Selected item goal: ' .. known(selected.count) .. ' / ' .. known(selected.goal)
            .. (selected.goal_complete and '   |   Complete' or ''));
    end
end

local function recent(view, services, ui)
    if not ui.section('Recent items', 'The last personal treasure receipts recorded while the session was running.', false) then return; end
    local rows = (view.farming or {}).recent or {};
    if #rows == 0 then ui.note('No recent items recorded.'); return; end
    for index = #rows, 1, -1 do
        local item = rows[index];
        local info = item_info(services, item.item_id or item.id);
        ui.note(info.name .. ' x' .. known(item.count));
    end
end

local function gil_and_space(settings, view, services, ui)
    if not ui.section('Gil and bag space', 'Actual wallet changes and live space in your Inventory and Mog Satchel.', false) then return; end
    local storage = services.farming_storage_visible and services.farming_storage_visible(true) or view.storage or {};
    local gil, farm = view.gil or {}, view.farming or {};
    ui.note('Gil: ' .. known(gil.current) .. '   |   Gained: ' .. known(gil.gained) .. '   |   Spent: ' .. known(gil.spent));
    ui.note('Net gil: ' .. known(gil.net) .. '   |   Gil/HR: ' .. known(gil.rate) .. '   |   Gil from mobs: ' .. known(farm.mob_gil));
    ui.help('Net gil includes all observed wallet changes, including shops and trades. Gil from mobs counts the game\'s specific gil awards. Item value is separate. Gil/HR keeps its own timer.');
    for _, bag in ipairs({ { 'inventory', 'Inventory' }, { 'satchel', 'Mog Satchel' } }) do
        local space = storage[bag[1]] or {};
        ui.note(bag[2] .. ' free: ' .. known(space.free));
    end
    ui.pick(settings.farming, 'space_bag', 'Bag space warning', {
        { name = 'Inventory', value = 'inventory' }, { name = 'Mog Satchel', value = 'satchel' }, { name = 'Both bags', value = 'both' },
    }, 'Choose which of your bags can trigger the low-space alert. Counts stay live while the session is paused.');
    ui.slider(settings.farming, 'low_slots', 'Free slots warning', 0, 30, '%.0f', 'Warn when a chosen bag reaches this many free slots or fewer. Enable the alert under Alerts > Farming.');
    settings.farming.low_slots = math.floor(settings.farming.low_slots + 0.5);
end

function farming.draw(settings, view, services, ui)
    if services.farming_storage_visible then services.farming_storage_visible(false); end
    options(settings, view, services, ui);
    wanted(settings, services, ui);
    breakdown(settings, view, services, ui);
    recent(view, services, ui);
    gil_and_space(settings, view, services, ui);
    prices(settings, view, services, ui);
end

function farming.cancel_pending()
    search[1], filter[1], price[1] = '', '', '';
    search_key, search_rows, searching, price_key, status, page = nil, nil, false, nil, nil, 1;
end

return farming;
