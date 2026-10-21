local imgui = require('imgui');
local readouts = require('ui.readouts');
local rules = require('data.dynamis_rules');
local dynamis = {};
local num, time = readouts.format_number, readouts.countdown;
local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' };
local families = { { 'bronze', 'Bronzepieces' }, { 'byne', 'Byne bills' }, { 'shell', 'Whiteshells' } };
local categories = {
    { name = 'All drops', value = 'all' }, { name = 'Relic armor', value = 'af2' },
    { name = 'Relic armor -1', value = 'armor_minus1' }, { name = 'Relic accessories', value = 'accessory' },
    { name = 'Relic weapons', value = 'weapon' }, { name = 'Attestations', value = 'attestation' },
    { name = 'Fragments', value = 'fragment' }, { name = 'Other drops', value = 'other' },
};
local item_filter = { '' };
local item_category, item_page = 'all', 1;
local catalog, filtered, filter_key;
local clear_pending, clear_run, status;
local selected_history;
local history_cache;

local function row(ui, text, help)
    ui.note(text);
    if help then ui.help(help); end
end

local function count_selected(values)
    local count = 0;
    for _, enabled in pairs(values or {}) do if enabled == true then count = count + 1; end end
    return count;
end

function dynamis.summary(view)
    local dyna = view and view.dynamis or view or {};
    local timing = dyna.active and ('Time left: ' .. time(dyna.remaining)) or ('Elapsed time: ' .. readouts.format_time(dyna.elapsed));
    return table.concat({
        'Momentum - ' .. (dyna.name or 'Dynamis run'),
        timing .. ' | Time extensions: +' .. num(dyna.extension_minutes) .. 'm',
        'Currency found: ' .. num(dyna.currency_found) .. ' | Received: ' .. num(dyna.currency_received) .. ' (counted in singles)',
        'Relic armor found: ' .. num(dyna.af2) .. ' | Received: ' .. num(dyna.af2_received),
        'Monsters defeated: ' .. num(dyna.kills),
        dyna.partial and 'Partial run: drops and deaths before tracking or while offline are not included.' or 'Only drops and deaths seen by Momentum are counted.',
    }, '\n');
end

local function run_details(dyna, services, ui)
    local identity = tostring(dyna.zone) .. ':' .. tostring(dyna.start_time);
    if clear_run ~= identity then clear_pending, clear_run = nil, identity; end
    if not ui.section('Current Dynamis run', 'Your hourglass, time extensions, drops, and objectives for this run.', true) then return; end
    if type(dyna.next_entry_seconds) == 'number' then
        row(ui, 'Next Dynamis entry: ' .. (dyna.next_entry_seconds <= 0 and 'Lockout ended' or readouts.format_time(dyna.next_entry_seconds)),
            'Phoenix applies a 72-hour account lockout from successful registration. Events > Account timers can include registrations recorded on your grouped characters on this computer. Unobserved entries and other requirements cannot be checked.');
    end
    if not dyna.active then
        ui.note('Enter Dynamis to track a run.');
        return;
    end
    row(ui, (dyna.name or 'Dynamis') .. '   |   Time left ' .. time(dyna.remaining),
        'The end time comes from your Perpetual Hourglass. Time extensions update it. Your EXP session can be paused or reset while this timer keeps running.');
    if dyna.remaining == nil then ui.note('Waiting for your Perpetual Hourglass. The time left is not known yet.');
    elseif dyna.remaining <= 0 then ui.note('Time expired. Leave enough time to finish with the treasure pool.'); end
    if dyna.clock_estimated and dyna.remaining then ui.note('Using your computer clock until server time is available.'); end
    row(ui, 'Time extensions +' .. num(dyna.extension_minutes) .. 'm   |   Extensions seen ' .. num(dyna.extension_count),
        'The hourglass can recover total minutes after a late join. Extensions seen only counts the extension messages Momentum received.');
    row(ui, 'Currency found ' .. num(dyna.currency_found) .. '   |   Received ' .. num(dyna.currency_received),
        'Found counts currency seen in the treasure pool. Received counts currency awarded to you. Hundred-pieces count as 100.');
    row(ui, 'Relic armor found ' .. num(dyna.af2) .. '   |   Received ' .. num(dyna.af2_received) .. '   |   Monsters defeated ' .. num(dyna.kills),
        'These totals come from drops and deaths the client saw. They do not tell us how many monsters remain in the zone.');
    if dyna.partial then ui.note('Partial run. Drops and deaths before tracking or while offline are not included.'); end
    if dyna.subjob_locked ~= nil then row(ui, 'Support job: ' .. (dyna.subjob_locked and 'Locked' or 'Unlocked'), 'This follows your actual support job restriction effect.'); end
    if dyna.weakness_seconds and dyna.weakness_seconds > 0 then row(ui, 'Weakness: ' .. time(dyna.weakness_seconds), 'Re-entering an active Phoenix Dynamis run applies 10 minutes of Weakness.'); end
    if dyna.clear_owned ~= nil then row(ui, 'Zone clear: ' .. (dyna.clear_owned and 'Obtained' or 'Not obtained'), 'Whether you own this zone\'s clear key item. This may be from a previous run.'); end
    ui.buttons({ { 'Copy run summary', function() if services.copy then services.copy(dynamis.summary(dyna)); status = 'Run summary copied.'; end end,
        'Copy these run totals. This does not send anything to chat.' } });
    imgui.BeginDisabled(not services.dynamis_clear);
    if imgui.Button('Clear run totals...') then clear_pending = true; status = nil; end
    ui.tip('Clear the counted drops and kills after confirmation. Your hourglass and time extensions keep running.');
    imgui.EndDisabled();
    if clear_pending then
        ui.note('Clear the counted drops and kills? Your hourglass, time extensions, and objectives stay as they are.');
        ui.buttons({ { 'Clear run totals now', function()
            if services.dynamis_clear then
                local okay, problem = services.dynamis_clear();
                status = okay == false and (problem or 'Run totals could not be cleared.') or 'Run totals cleared. Your timer is still running.';
            end
            clear_pending = nil;
        end, 'Clear the drop and kill totals for this run.' }, { 'Keep run totals', function() clear_pending = nil; end, 'Keep the current totals.' } });
    end
end

local function objectives(dyna, ui)
    if not ui.section('Objectives and time extensions', 'Zone goals and time extensions. Unknown means Momentum has not seen enough to confirm them.', false) then return; end
    if not dyna.active then ui.note('Enter Dynamis to see this zone\'s objectives.'); return; end
    if dyna.info then ui.note(dyna.info); end
    for _, objective in ipairs(dyna.objectives or {}) do
        local state = objective.status == 'complete' and 'Complete' or objective.status == 'incomplete' and 'In progress' or 'Unknown';
        local progress = objective.total and objective.total > 1 and (' (' .. num(objective.done) .. '/' .. num(objective.total) .. ')') or '';
        row(ui, (objective.name or 'Objective') .. ': ' .. state .. progress, objective.help);
    end
    if #(dyna.objectives or {}) == 0 then ui.note('No objectives listed for this zone.'); end
    for _, entry in ipairs(dyna.weakening or {}) do row(ui, (entry.name or 'Boss weakness') .. ': ' .. (entry.done and 'Confirmed' or 'Unknown'), entry.help); end
    if #(dyna.extensions or {}) > 0 then
        imgui.Spacing();
        ui.note('Time extensions seen');
        for _, extension in ipairs(dyna.extensions) do
            local stamp = type(extension.time) == 'number' and os.date('%H:%M', extension.time) or '--:--';
            row(ui, stamp .. '   +' .. num(extension.minutes) .. ' minutes', 'Time shown uses your computer\'s local time.');
        end
    end
    ui.note('Unseen deaths and unobserved waves stay unknown. Leaving your range does not count as a defeat.');
end

local function drops(dyna, ui)
    if not ui.section('Currency and drops', 'Currency by nation and drops seen in this run. Found and Received are separate totals.', false) then return; end
    for _, family in ipairs(families) do
        local value = (dyna.currency or {})[family[1]] or {};
        row(ui, family[2] .. ': found ' .. num(value.found) .. '   |   Received ' .. num(value.received),
            'Counted in singles. Found includes the treasure pool; Received includes only awards to you.');
        if value.singles_found ~= nil then row(ui, 'Singles ' .. num(value.singles_found) .. '   |   Hundred-pieces ' .. num(value.hundreds_found),
            'The number of single currency pieces and hundred-pieces seen in the treasure pool.'); end
    end
    row(ui, 'Currency/HR: ' .. num(dyna.currency_rate), 'Currency found divided by time since tracking started or totals were cleared. Partial runs can include offline time and missing drops.');
    if #(dyna.loot or {}) == 0 then ui.note('No drops recorded yet.'); return; end
    if imgui.BeginChild('##dynamis_drop_list', { 0, 220 }, 0) then
        for _, item in ipairs(dyna.loot) do
            row(ui, (item.name or 'Item ' .. tostring(item.item_id)) .. (item.job and ' (' .. item.job .. ')' or '')
                .. '   |   Found ' .. num(item.found) .. '   |   Received ' .. num(item.received),
                'Waiting in pool: ' .. num(item.pending) .. '. Awarded: ' .. num(item.awarded) .. '. Lost: ' .. num(item.lost) .. '.');
        end
    end
    imgui.EndChild();
end

local function treasure_pool(dyna, ui)
    if not ui.section('Treasure pool', 'Items still waiting to be lotted or passed. Momentum never lots or passes for you.', false, num(dyna.pool_count) .. ' items') then return; end
    local pool = dyna.pool or {};
    if #pool == 0 then ui.note('No items waiting in the treasure pool.'); return; end
    for _, item in ipairs(pool) do
        row(ui, item.name or 'Item ' .. tostring(item.item_id), 'An item can leave the pool early when everyone has lotted or passed.');
        if item.remaining then row(ui, 'About ' .. time(item.remaining) .. ' left', 'Estimated from when Momentum first saw this item. Joining or reloading can shorten the time you have left.'); end
    end
end

local function prepare_catalog()
    if catalog then return; end
    catalog = {};
    for id, item in pairs(rules.items or {}) do
        if item.kind ~= 'currency' then
            catalog[#catalog + 1] = { id = tostring(id), name = item.name, job = item.job, kind = item.kind,
                search = (item.name .. ' ' .. (item.job or '') .. ' ' .. tostring(id)):lower() };
        end
    end
    table.sort(catalog, function(left, right) return left.name == right.name and tonumber(left.id) < tonumber(right.id) or left.name < right.name; end);
end

local function wanted(settings, ui)
    local options = settings.dynamis;
    local count = count_selected(options.wanted_jobs) + count_selected(options.wanted_items);
    if not ui.section('Wanted drops', 'Choose jobs for relic armor, or choose individual drops. Turn on Wanted Dynamis drop under Alerts to get a notice or sound.', false, count .. ' chosen') then return; end
    ui.note('Relic armor by job');
    local width = imgui.GetContentRegionAvail();
    local columns = math.max(1, math.min(6, math.floor(width / (imgui.CalcTextSize('WAR (?)') + imgui.GetFrameHeight() + 32))));
    for index, job in ipairs(jobs) do
        if (index - 1) % columns ~= 0 then imgui.SameLine(); end
        ui.checkbox(options.wanted_jobs, job, job, 'Watch for ' .. job .. ' relic armor, relic armor -1, and relic accessories.');
    end
    imgui.Spacing();
    local category_name;
    for _, category in ipairs(categories) do if category.value == item_category then category_name = category.name; break; end end
    ui.combo('Drop type', category_name or 'All drops', categories, function(value) item_category = value; item_page = 1; end, nil,
        'Narrow the list of individual drops. Your chosen drops stay selected.');
    imgui.SetNextItemWidth(math.min(360, (imgui.GetContentRegionAvail())));
    imgui.InputTextWithHint('##dynamis_wanted_filter', 'Find a drop or job', item_filter, 81);
    ui.tip('Search item names, job abbreviations, or item numbers.');
    prepare_catalog();
    local term = item_filter[1]:lower():match('^%s*(.-)%s*$');
    local key = item_category .. ':' .. term;
    if key ~= filter_key then
        filtered, filter_key, item_page = {}, key, 1;
        for _, item in ipairs(catalog) do
            local kind = item.kind;
            local other = kind ~= 'af2' and kind ~= 'armor_minus1' and kind ~= 'accessory' and kind ~= 'weapon' and kind ~= 'attestation' and kind ~= 'fragment';
            if (item_category == 'all' or item_category == kind or item_category == 'other' and other)
                and (term == '' or item.search:find(term, 1, true)) then filtered[#filtered + 1] = item; end
        end
    end
    local pages = math.max(1, math.ceil(#filtered / 30));
    item_page = math.min(item_page, pages);
    if #filtered == 0 then ui.note('No matching drops.'); end
    if imgui.BeginChild('##dynamis_wanted_items', { 0, 210 }, 0) then
        for index = (item_page - 1) * 30 + 1, math.min(item_page * 30, #filtered) do
            local item = filtered[index];
            imgui.PushID(item.id);
            ui.checkbox(options.wanted_items, item.id, item.name .. (item.job and ' (' .. item.job .. ')' or ''), 'Watch for this drop in the treasure pool.');
            imgui.PopID();
        end
    end
    imgui.EndChild();
    if pages > 1 then
        ui.note('Page ' .. item_page .. ' / ' .. pages .. '   |   ' .. #filtered .. ' drops');
        imgui.BeginDisabled(item_page == 1);
        if imgui.Button('Previous drops') then item_page = item_page - 1; end
        imgui.EndDisabled(); imgui.SameLine();
        imgui.BeginDisabled(item_page == pages);
        if imgui.Button('Next drops') then item_page = item_page + 1; end
        imgui.EndDisabled();
    end
end

local function history(dyna, services, ui)
    if not ui.section('Dynamis run history', 'Saved totals from previous runs for this character.', false) then return; end
    local entries = services.dynamis_history and services.dynamis_history() or dyna.history or {};
    if #entries == 0 then ui.note('No saved Dynamis runs yet.'); return; end
    if not history_cache or history_cache.source ~= entries or history_cache.count ~= #entries or history_cache.latest ~= entries[#entries] then
        history_cache = { source = entries, count = #entries, latest = entries[#entries], choices = {}, labels = {} };
        for index = #entries, 1, -1 do
            local entry = entries[index];
            local timestamp = entry.start_time or entry.finished_at;
            local date = type(timestamp) == 'number' and os.date('%Y-%m-%d %H:%M', timestamp) or 'Date unknown';
            local label = (entry.short_name or entry.name or 'Dynamis') .. ' - ' .. date;
            history_cache.choices[#history_cache.choices + 1] = { name = label, value = index };
            history_cache.labels[index] = label;
        end
    end
    if not selected_history or not entries[selected_history] then selected_history = #entries; end
    ui.combo('Saved run', history_cache.labels[selected_history], history_cache.choices, function(value) selected_history = value; end);
    local entry = entries[selected_history];
    row(ui, 'Currency found ' .. num(entry.currency_found) .. '   |   Received ' .. num(entry.currency_received), 'Saved totals, counted in singles.');
    row(ui, 'Relic armor found ' .. num(entry.af2) .. '   |   Received ' .. num(entry.af2_received), 'Relic armor seen in the pool and awarded to you.');
    row(ui, 'Monsters defeated ' .. num(entry.kills) .. '   |   Time extensions +' .. num(entry.extension_minutes) .. 'm', 'Only observed monster deaths are counted.');
    if entry.partial then ui.note('This record covers only part of the run.'); end
    ui.buttons({ { 'Copy saved run summary', function() if services.copy then services.copy(dynamis.summary(entry)); status = 'Saved run summary copied.'; end end,
        'Copy the selected run totals. Your current run stays as it is.' } });
end

function dynamis.draw(settings, view, services, ui)
    local dyna = view.dynamis or {};
    if not settings.dynamis.enabled then ui.note('Dynamis tracking is off. Turn on Track Dynamis runs under Dynamis options to track time and drops.'); end
    run_details(dyna, services, ui);
    if ui.section('Dynamis options', 'Use a separate compact layout for Dynamis, with the same position, colors, and readout controls.', false) then
        ui.checkbox(settings.dynamis, 'enabled', 'Track Dynamis runs', 'Track your hourglass, drops, and observed objectives in Dynamis.');
        imgui.BeginDisabled(settings.modes.selected ~= 'auto');
        ui.checkbox(settings.dynamis, 'auto_layout', 'Switch layouts in Dynamis', 'When Bar mode is Automatic, use your Dynamis layout in Dynamis and return to EXP or Merits when you leave. Manual modes stay selected.');
        imgui.EndDisabled();
        if services.bar_mode then
            ui.buttons({ { 'Use Dynamis bar', function()
                services.bar_mode('dynamis');
                settings.window.tab = 'Display'; ui.changed();
            end, 'Select Dynamis, then use Display to arrange its readouts. Use Bar mode at the top to switch back to EXP, Merits, or Automatic.' } });
        end
        ui.slider(settings.dynamis, 'retention', 'Dynamis runs to keep', 1, 100, '%.0f', 'Keep this many completed runs for this character. The oldest saved run is removed first.');
        settings.dynamis.retention = math.floor(settings.dynamis.retention + 0.5);
    end
    objectives(dyna, ui);
    drops(dyna, ui);
    treasure_pool(dyna, ui);
    wanted(settings, ui);
    history(dyna, services, ui);
    if dyna.saved_error then ui.note(dyna.saved_error); end
    if status then ui.note(status); end
end

function dynamis.cancel_pending()
    clear_pending = nil;
end

return dynamis;
