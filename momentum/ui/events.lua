local imgui = require('imgui');
local readouts = require('ui.readouts');
local rules = require('data.event_rules');
local names = require('ui.event_layout').names;
local events = {};
local num, time = readouts.format_number, readouts.format_time;
local wanted_filter = { '' };
local wanted_kind, wanted_page = 'all', 1;
local catalog, filtered, filtered_key;
local reference_kind, reference_id = 'assault', nil;
local references;
local selected_history;
local mission_order, enm_choices;

local function row(ui, text, help)
    ui.note(text);
    if help then ui.help(help); end
end

local function known(value)
    return value == nil and 'Unknown' or num(value);
end

local function observed(value)
    return type(value) == 'number' and os.date('%b %d, %H:%M', value) or 'not observed';
end

local function chosen_count(settings)
    local count = 0;
    for _, enabled in pairs(settings.events.wanted) do if enabled == true then count = count + 1; end end
    return count;
end

local function count_items(items)
    local total = 0;
    for _, item in ipairs(items or {}) do total = total + (item.count or 1); end
    return total;
end

function events.summary(view)
    local event = view and view.events or view or {};
    return table.concat({
        'Momentum - ' .. (event.name or names[event.kind] or 'Battlefield run'),
        'Status: ' .. (event.status or 'Not observed') .. ' | Time spent: ' .. time(event.elapsed),
        'Time left: ' .. (event.time_estimated and '~' or '') .. readouts.countdown(event.remaining),
        'Objective: ' .. (event.objective or 'Progress not observed'),
        'Drops found: ' .. num(count_items(event.drops)) .. ' | Received: ' .. num(count_items(event.received)),
        'EXP received: ' .. num(event.exp) .. ' | LP received: ' .. num(event.lp) .. ' | Assault points: ' .. num(event.points),
        'Only progress, drops, and rewards seen by Momentum are counted.',
    }, '\n');
end

local function current(event, services, ui)
    if not ui.section('Current Assault or battlefield', 'The current run, its timer, and progress seen by Momentum. EXP session pause and reset leave this running.', true) then return; end
    if not event.active then ui.note('Enter an Assault, Limbus route, BCNM, KSNM, or ENM to track a run.'); return; end
    row(ui, (event.name or names[event.kind] or 'Battlefield') .. '   |   ' .. (event.status or 'Status not observed'),
        'Choosing a bar mode only changes the layout. A run starts when Momentum sees normal game updates for an entry.');
    row(ui, 'Time left: ' .. (event.time_estimated and event.remaining and '~' or '') .. readouts.countdown(event.remaining)
        .. '   |   Time spent: ' .. time(event.elapsed),
        'The countdown follows normal game updates. ~ marks an estimate. Time spent covers the part of this run Momentum observed. Missing timing information stays unknown.');
    row(ui, event.objective or 'Progress not observed', 'This is observed progress. Enemy deaths outside your range and hidden objectives can be missed.');
    if event.floor then row(ui, 'Last identified floor: ' .. num(event.floor) .. (event.floors and event.floors > 0 and ' / ' .. num(event.floors) or ''), 'Known enemies and game updates can identify a floor. Using a vortex alone may not confirm the next floor.'); end
    if event.partial then ui.note('Partial run. Progress before tracking or while offline is not included.'); end
    row(ui, 'EXP received: ' .. known(event.exp) .. '   |   LP received: ' .. known(event.lp) .. '   |   Assault points: ' .. known(event.points),
        'Confirmed rewards seen during this run. Potential rewards in the fight reference are listed separately.');
    ui.buttons({ { 'Copy event summary', function() if services.copy then services.copy(events.summary(event)); end end,
        'Copy these run totals. This does not send anything to chat.' } });
end

local function objectives(event, ui)
    if not ui.section('Event objectives', 'Source-backed goals and milestones seen during this run. Unknown progress is left unknown.', false) then return; end
    if not event.active then ui.note('No active event. Choose a fight under Fight reference to read its objective.'); return; end
    row(ui, event.objective or 'Progress not observed', 'A death count is not always a count of enemies left. Some fights reuse enemies or have changing waves.');
    if event.objective_hint and event.objective_hint ~= event.objective then row(ui, event.objective_hint, 'The objective listed in Phoenix rules. Progress is confirmed separately from normal game updates.'); end
    for _, objective in ipairs(event.objectives or {}) do
        if type(objective) == 'table' then
            row(ui, (objective.name or objective.text or 'Objective') .. (objective.status and ': ' .. objective.status or ''), objective.help);
        else ui.note(tostring(objective)); end
    end
    if event.extension_minutes then row(ui, 'Time extensions: ' .. num(event.extensions) .. '   |   Minutes added: +' .. num(event.extension_minutes), 'Only extensions observed during this run are counted.'); end
    row(ui, 'Enemy deaths seen: ' .. known(event.kills), 'Deaths outside your range may be missed. This does not show a guessed number of enemies remaining.');
    if event.personal_best then row(ui, 'Your fastest confirmed clear: ' .. time(event.personal_best), 'Saved clear times recorded for this fight. Incomplete runs cannot set a personal best.'); end
    if event.record then row(ui, 'Last reported battlefield record: ' .. time(event.record), 'This is the record reported through a normal entry or result event. It is separate from your personal best.'); end
end

local function drops(event, ui)
    if not ui.section('Event treasure', 'Items found in the treasure pool and items awarded to you are separate totals.', false) then return; end
    row(ui, 'Ancient Beastcoins: found ' .. known(event.coins_found) .. '   |   Received ' .. known(event.coins_received), 'Moving items between bags does not add to run rewards.');
    row(ui, 'AF upgrade materials: found ' .. known(event.materials_found) .. '   |   Received ' .. known(event.materials_received));
    local combined, order = {}, {};
    for _, side in ipairs({ { event.drops, 'found' }, { event.received, 'received' } }) do
        for _, item in ipairs(side[1] or {}) do
            local id = item.item_id or item.id or item.name;
            local entry = combined[id];
            if not entry then entry = { item = item, found = 0, received = 0 }; combined[id] = entry; order[#order + 1] = id; end
            entry[side[2]] = entry[side[2]] + (item.count or 1);
        end
    end
    if #order == 0 then ui.note('No drops recorded yet.'); return; end
    if imgui.BeginChild('##event_loot', { 0, 190 }, 0) then
        for _, id in ipairs(order) do
            local entry, item = combined[id], combined[id].item;
            row(ui, (item.name or 'Item ' .. tostring(id)) .. (item.job and ' (' .. item.job .. ')' or '')
                .. '   |   Found ' .. num(entry.found) .. '   |   Received ' .. num(entry.received), item.reward and 'Trade reward: ' .. item.reward .. '.' or item.help);
        end
    end
    imgui.EndChild();
end

local currency_names = {
    beastmen_seals = 'Stored Beastmen\'s Seals', kindred_seals = 'Stored Kindred\'s Seals', ancient_beastcoins = 'Stored Ancient Beastcoins',
    assault_leujaoam = 'Leujaoam Assault points', assault_mamool = 'Mamool Ja Assault points', assault_lebros = 'Lebros Assault points',
    assault_periqia = 'Periqia Assault points', assault_ilrusi = 'Ilrusi Assault points', assault_tags = 'Stored Imperial Army I.D. tags',
};
local currency_order = { 'assault_leujaoam', 'assault_mamool', 'assault_lebros', 'assault_periqia', 'assault_ilrusi', 'assault_tags', 'beastmen_seals', 'kindred_seals', 'ancient_beastcoins' };

local function readiness(event, ui)
    if not ui.section('Entry items and balances', 'Carried entry items and last observed stored balances. These do not guarantee that every entry requirement is met.', false) then return; end
    if #(event.entry_items or {}) == 0 then ui.note('No entry-item information is available yet.'); end
    for _, item in ipairs(event.entry_items or {}) do
        local state = item.owned == nil and 'Unknown' or item.owned and 'Carried' or 'Not carried';
        row(ui, (item.name or 'Item ' .. tostring(item.id)) .. ': ' .. state,
            'Only items the client can read are checked. A carried orb may be worn, and other fight requirements still apply.');
    end
    for _, key in ipairs(currency_order) do
        local value = (event.currencies or {})[key];
        row(ui, currency_names[key] .. ': ' .. known(type(value) == 'table' and value.value or value),
            'Last updated: ' .. observed(type(value) == 'table' and value.observed_at) .. '. '
                .. ((key == 'beastmen_seals' or key == 'kindred_seals')
                    and 'These seals are stored with Shami. Seals in Inventory are counted separately. Talk to Shami, deposit seals, or buy an orb to refresh the confirmed balance.'
                    or 'Stored balances update from normal game or NPC messages.'));
    end
    if event.inventory_available then
        row(ui, 'Inventory: Beastmen\'s Seals ' .. num((event.inventory or {})[1126] or 0)
            .. '   |   Kindred\'s Seals ' .. num((event.inventory or {})[1127] or 0)
            .. '   |   Ancient Beastcoins ' .. num((event.inventory or {})[1875] or 0), 'Counts only your Inventory bag. This does not include other bags, seals stored with Shami, or coins stored with Sagheera.');
        for id, count in pairs(event.inventory or {}) do
            local item = (rules.items or {})[id] or (rules.orbs or {})[id];
            if item and ((rules.orbs or {})[id] or item.kind == 'chip') then
                row(ui, (item.name or 'Item ' .. id) .. ': ' .. num(count) .. ' in Inventory', 'Possession alone does not confirm every entry requirement. A carried orb may already be worn.');
            end
        end
    end
end

local function assault_checklist(event, ui)
    if not ui.section('Assault mission checklist', 'The five supported missions and clears reported through normal game updates.', false) then return; end
    if not mission_order then
        mission_order = {};
        for id in pairs(rules.assault_missions or {}) do mission_order[#mission_order + 1] = id; end
        table.sort(mission_order);
    end
    for _, id in ipairs(mission_order) do
        local mission = rules.assault_missions[id];
        local complete = (event.assault_completed or {})[id];
        row(ui, mission.name .. ': ' .. (complete == nil and 'Not observed' or complete and 'Complete' or 'Not complete')
            .. (event.assault_current == id and '   |   Current mission' or ''),
            'The mission list updates when the client receives your Assault record. Loading without that update leaves the clear state unknown.');
    end
    if event.assault_report and event.assault_report > 0 then ui.note('Report your Assault result to Rytaal.');
    elseif event.assault_report == nil then ui.note('Report status has not been observed yet.'); end
end

local function cooldowns(settings, event, ui)
    if not ui.section('Entry cooldowns', 'Observed entry and key-item waits. A finished wait does not check the other entry requirements.', false) then return; end
    if not enm_choices then
        enm_choices = {};
        for id, group in pairs(rules.enm_groups or {}) do enm_choices[#enm_choices + 1] = { name = group.name, value = id }; end
        table.sort(enm_choices, function(left, right) return left.name < right.name; end);
        table.insert(enm_choices, 1, { name = 'Current ENM', value = 0 });
    end
    local current = 'Current ENM';
    for _, group in ipairs(enm_choices) do
        if settings.events.enm_group == group.value then current = group.name; end
    end
    ui.combo('ENM wait on bar', current, enm_choices, function(value) settings.events.enm_group = value; ui.changed(); end, nil,
        'Choose which shared key-item wait Next ENM shows. Current ENM follows the fight you are in. The other choices stay selected outside the fight.');
    if #(event.cooldowns or {}) == 0 then ui.note('No entry cooldowns have been observed yet.'); end
    for _, cooldown in ipairs(event.cooldowns or {}) do
        row(ui, (cooldown.name or cooldown.key or 'Entry wait') .. ': '
            .. (cooldown.remaining == 0 and 'Wait ended' or (cooldown.estimated and '~' or '') .. time(cooldown.remaining)),
            (cooldown.kind == 'enm' and 'ENM key-item waits start when you obtain the key item. Fights using the same key item share this wait. '
                or cooldown.kind == 'limbus' and 'Phoenix starts this character\'s 20-hour Limbus wait when Cosmo-Cleanse is consumed on entry. '
                or 'This is a wait observed from normal game updates. ')
                .. 'Last updated: ' .. observed(cooldown.observed_at) .. '.');
    end
end

local function account_timers(settings, view, ui)
    if not ui.section('Account timers', 'Share observed Dynamis timers and Limbus reminders between your characters on this computer.', false) then return; end
    ui.input(settings.account, 'group', 'Account group', 80,
        'Use the same group on characters on the same account. Shares recorded timers on this computer. Leave blank to keep them separate.');
    ui.checkbox(settings.account, 'share_dynamis', 'Share Dynamis timer', 'Use the latest Dynamis registration recorded in this local group. Phoenix applies its 72-hour Dynamis lockout account-wide.');
    ui.checkbox(settings.account, 'share_limbus', 'Share Limbus reminder', 'Use the latest Limbus entry recorded in this local group as a shared reminder. Phoenix currently enforces the Limbus timer per character.');
    for _, kind in ipairs({ 'dynamis', 'limbus' }) do
        local cooldown = (view.account_cooldowns or {})[kind];
        if cooldown then row(ui, (kind == 'dynamis' and 'Dynamis account timer: ' or 'Limbus account reminder: ')
            .. (cooldown.remaining == 0 and 'Wait ended' or time(cooldown.remaining)),
            'Includes only entries Momentum recorded for this local group. Entries on another computer or unobserved characters are not known.'); end
    end
    ui.note('This uses a nickname you choose. No account name or password is read.');
end

local function prepare_catalog()
    if catalog then return; end
    catalog, references = {}, {};
    for id, item in pairs(rules.items or {}) do
        catalog[#catalog + 1] = { id = tostring(id), name = item.name or 'Item ' .. tostring(id), kind = item.kind, job = item.job,
            search = ((item.name or '') .. ' ' .. (item.job or '') .. ' ' .. tostring(id)):lower() };
    end
    table.sort(catalog, function(left, right) return left.name == right.name and left.id < right.id or left.name < right.name; end);
    for _, area in pairs(rules.areas or {}) do for _, fight in pairs(area.battles or {}) do references[#references + 1] = fight; end end
    for _, mission in pairs(rules.assault_missions or {}) do references[#references + 1] = mission; end
    table.sort(references, function(left, right) return left.name < right.name; end);
end

local function wanted(settings, ui)
    if not ui.section('Wanted event drops', 'Choose individual drops, then turn on Wanted Assault or battlefield drop under Alerts.', false, chosen_count(settings) .. ' chosen') then return; end
    prepare_catalog();
    ui.combo('Show drops', wanted_kind == 'chosen' and 'Chosen drops' or 'All drops', {
        { name = 'All drops', value = 'all' }, { name = 'Chosen drops', value = 'chosen' },
    }, function(value) wanted_kind, wanted_page, filtered_key = value, 1, nil; end);
    imgui.SetNextItemWidth(math.min(360, (imgui.GetContentRegionAvail())));
    imgui.InputTextWithHint('##event_wanted_filter', 'Find a drop or job', wanted_filter, 81);
    local term = wanted_filter[1]:lower():match('^%s*(.-)%s*$');
    local key = term .. ':' .. wanted_kind .. ':' .. tostring(settings.events.wanted) .. ':' .. tostring(chosen_count(settings));
    if key ~= filtered_key then
        filtered, filtered_key, wanted_page = {}, key, 1;
        for _, item in ipairs(catalog) do
            if (wanted_kind ~= 'chosen' or settings.events.wanted[item.id]) and (term == '' or item.search:find(term, 1, true)) then filtered[#filtered + 1] = item; end
        end
    end
    local pages = math.max(1, math.ceil(#filtered / 20));
    wanted_page = math.max(1, math.min(pages, wanted_page));
    ui.note(num(#filtered) .. ' drops   |   Page ' .. wanted_page .. ' / ' .. pages);
    ui.buttons({ { 'Previous drops', function() wanted_page = math.max(1, wanted_page - 1); end },
        { 'Next drops', function() wanted_page = math.min(pages, wanted_page + 1); end } });
    for index = (wanted_page - 1) * 20 + 1, math.min(#filtered, wanted_page * 20) do
        local item = filtered[index];
        ui.checkbox(settings.events.wanted, item.id, item.name .. (item.job and ' (' .. item.job .. ')' or '') .. '##event_wanted_' .. item.id,
            'Watch for this item in the treasure pool. Momentum never lots or passes for you.');
    end
    if #filtered == 0 then ui.note('No drops match this search.'); end
end

local function reference(ui)
    if not ui.section('Fight reference', 'Phoenix entry items, limits, objectives, and possible rewards. These are rules for the fight, not a claim that you can enter now.', false) then return; end
    prepare_catalog();
    local choices = {};
    for _, kind in ipairs({ 'assault', 'limbus', 'bcnm', 'ksnm', 'enm' }) do choices[#choices + 1] = { name = names[kind], value = kind }; end
    ui.combo('Fight type', names[reference_kind], choices, function(kind) reference_kind, reference_id = kind, nil; end);
    local fights, current = {}, nil;
    for _, fight in ipairs(references) do
        if fight.kind == reference_kind then
            local id = tostring(fight.zone) .. ':' .. tostring(fight.index or fight.id);
            fights[#fights + 1] = { name = fight.name, value = id };
            if reference_id == id then current = fight; end
        end
    end
    ui.combo('Fight', current and current.name or '(choose)', fights, function(id) reference_id = id; end);
    if not current then return; end
    row(ui, current.name .. '   |   ' .. time(current.time_limit) .. ' limit', 'The current run timer uses observed remaining time, not a fresh full limit after a reload.');
    if current.level_cap then row(ui, 'Level cap: ' .. num(current.level_cap) .. '   |   Maximum players: ' .. known(current.max_players)); end
    if current.objective then row(ui, current.objective.text or 'Objective not listed'); end
    if current.orb then
        local orb = (rules.orbs or {})[current.orb] or {};
        row(ui, 'Orb: ' .. (orb.name or 'Item ' .. tostring(current.orb)) .. (orb.cost and '   |   ' .. num(orb.cost) .. (orb.seal == 'kindred' and ' Kindred\'s Seals' or ' Beastmen\'s Seals') or ''));
    end
    for _, id in ipairs(current.key_items or {}) do
        row(ui, 'Entry key item: ' .. ((rules.key_item_names or {})[id] or tostring(id)));
    end
    for _, alternatives in ipairs(current.key_item_options or {}) do
        local items = {};
        for _, id in ipairs(alternatives) do items[#items + 1] = (rules.key_item_names or {})[id] or tostring(id); end
        row(ui, 'Entry key item: ' .. table.concat(items, ' or '), 'You need one of these alternatives, along with the other listed requirements.');
    end
    for _, id in ipairs(current.entry_items or {}) do
        local item = (rules.items or {})[id] or {};
        row(ui, 'Entry item: ' .. (item.name or tostring(id)));
    end
    if current.enm_group then
        local group = (rules.enm_groups or {})[current.enm_group] or {};
        row(ui, 'Shared key-item wait: ' .. (group.name or current.enm_group) .. '   |   ' .. time(group.duration), 'The wait starts when the key item is obtained. A win does not start a new wait.');
    end
    if current.grant_xp then row(ui, 'Possible EXP reward: ' .. num(current.grant_xp), 'Potential reward under Phoenix rules. Your actual award can differ and is recorded separately.'); end
    if #(current.loot or {}) > 0 then
        ui.note('Possible drops');
        if imgui.BeginChild('##event_reference_loot', { 0, 150 }, 0) then
            for _, id in ipairs(current.loot) do
                local item = (rules.items or {})[id] or {};
                row(ui, (item.name or 'Item ' .. id) .. (item.job and ' (' .. item.job .. ')' or ''),
                    item.reward and 'Trade reward: ' .. item.reward .. '.' or 'A possible drop under Phoenix rules. This does not mean the item will drop in your run.');
            end
        end
        imgui.EndChild();
    end
end

local function history(event, services, ui)
    if not ui.section('Event run history', 'Recorded attempts, confirmed results, times, and observed drops. Incomplete tracking stays marked.', false) then return; end
    local records = event.history or {};
    if #records == 0 then ui.note('No saved event runs yet.'); return; end
    selected_history = math.max(1, math.min(#records, selected_history or 1));
    local choices = {};
    for index, record in ipairs(records) do choices[#choices + 1] = { name = (record.name or names[record.kind] or 'Run') .. ' - ' .. observed(record.started_at or record.start_time), value = index }; end
    ui.combo('Recorded run', choices[selected_history].name, choices, function(index) selected_history = index; end);
    local record = records[selected_history];
    row(ui, (record.name or 'Run') .. '   |   ' .. (record.status or 'Incomplete') .. '   |   ' .. time(record.elapsed));
    if record.partial then ui.note('Partial run. Some progress or drops were not observed.'); end
    row(ui, 'Drops found: ' .. num(count_items(record.drops)) .. '   |   Received: ' .. num(count_items(record.received)));
    ui.buttons({ { 'Copy recorded event', function() if services.copy then services.copy(events.summary(record)); end end, 'Copy this record without sending anything to chat.' } });
end

function events.draw(settings, view, services, ui)
    local event = view.events or {};
    if ui.section('Event tracking options', 'Assault, Limbus, BCNM, KSNM, and ENM tracking. Each mode keeps its own readouts, order, labels, and dividers.', false) then
        ui.checkbox(settings.events, 'enabled', 'Track Assault and battlefields', 'Track normal game messages, timers, rewards, and drops. Turning this off does not stop Time in zone.');
        ui.checkbox(settings.events, 'auto_layout', 'Switch event layouts in Automatic', 'Switch to the matching saved layout after an observed entry. Leaving the event restores your previous EXP or Merits layout. Manual bar modes stay selected.');
        ui.slider(settings.events, 'history_limit', 'Saved event runs', 1, 100, '%.0f runs', 'Keep up to this many local run records. This does not change your current run.');
        settings.events.history_limit = math.floor(settings.events.history_limit + 0.5);
        local buttons = {};
        for _, kind in ipairs({ 'assault', 'limbus', 'bcnm', 'ksnm', 'enm' }) do
            local chosen = kind;
            buttons[#buttons + 1] = { 'Edit ' .. names[kind] .. ' bar', function()
                if services.bar_mode then services.bar_mode(chosen); settings.window.tab = 'Display'; ui.changed(); end
            end, 'Open this saved layout in Display. This does not start a run or enter a fight.' };
        end
        ui.buttons(buttons);
    end
    current(event, services, ui);
    objectives(event, ui);
    drops(event, ui);
    readiness(event, ui);
    assault_checklist(event, ui);
    cooldowns(settings, event, ui);
    account_timers(settings, view, ui);
    wanted(settings, ui);
    reference(ui);
    history(event, services, ui);
end

function events.cancel_pending()
    selected_history = nil;
end

return events;
