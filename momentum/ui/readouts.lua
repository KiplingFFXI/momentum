local defaults = require('ui.defaults');
local layout = require('ui.layout');
local rules = require('data.phoenix_rules');
local readouts = {};
local definitions = {};
for _, item in ipairs(defaults.READOUTS) do definitions[item.id] = item; end

function readouts.format_number(value, short)
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return '--'; end
    local sign = value < 0 and '-' or '';
    value = math.abs(value);
    if short and value >= 1000000 then return sign .. string.format('%.1fm', math.floor(value / 100000 + 0.5) / 10); end
    if short and value >= 10000 then return sign .. string.format('%.1fk', math.floor(value / 100 + 0.5) / 10); end
    local digits = tostring(math.floor(value + 0.5));
    local text = digits:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '');
    return sign .. text;
end

function readouts.format_time(seconds)
    if type(seconds) ~= 'number' or seconds ~= seconds or seconds == math.huge or seconds < 0 then return '--'; end
    seconds = math.floor(seconds + 0.5);
    if seconds >= 3600 then return string.format('%dh %02dm', math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)); end
    return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60);
end

function readouts.countdown(seconds)
    if type(seconds) ~= 'number' or seconds ~= seconds or seconds < 0 or seconds == math.huge then return '--'; end
    seconds = math.ceil(seconds);
    if seconds >= 3600 then return string.format('%d:%02d:%02d', math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60); end
    return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60);
end

local currency_family = {
    dyna_bynes = { 'byne', 'found' }, dyna_bronze = { 'bronze', 'found' }, dyna_shells = { 'shell', 'found' },
    dyna_bynes_received = { 'byne', 'received' }, dyna_bronze_received = { 'bronze', 'received' }, dyna_shells_received = { 'shell', 'received' },
};

local function objective_count(objectives)
    local complete, total = 0, 0;
    for _, objective in ipairs(objectives or {}) do
        total = total + 1;
        if objective.status == 'complete' then complete = complete + 1; end
    end
    return complete, total;
end

local function dynamis_value(id, view, short)
    local dyna = view.dynamis or {};
    local function number(value) return readouts.format_number(value, short); end
    if id == 'dyna_next_entry' then return dyna.next_entry_seconds == 0 and 'Lockout ended' or readouts.format_time(dyna.next_entry_seconds); end
    if not dyna.active then return '--'; end
    if id == 'dyna_zone' then return dyna.short_name or dyna.name or 'Dynamis';
    elseif id == 'dyna_time' then return (dyna.clock_estimated and dyna.remaining and '~' or '') .. readouts.countdown(dyna.remaining);
    elseif id == 'dyna_extensions' then return type(dyna.extension_minutes) == 'number' and '+' .. number(dyna.extension_minutes) .. 'm' or '--';
    elseif id == 'dyna_currency' then return number(dyna.currency_found);
    elseif id == 'dyna_currency_received' then return number(dyna.currency_received);
    elseif id == 'dyna_currency_rate' then return number(dyna.currency_rate);
    elseif id == 'dyna_af2' then return number(dyna.af2);
    elseif id == 'dyna_af2_received' then return number(dyna.af2_received);
    elseif id == 'dyna_kills' then return number(dyna.kills);
    elseif id == 'dyna_pool' then return number(dyna.pool_count) .. ' / 10';
    elseif id == 'dyna_subjob' then return dyna.subjob_locked == nil and '--' or dyna.subjob_locked and 'Locked' or 'Unlocked';
    elseif id == 'dyna_weakness' then return dyna.weakness_seconds == 0 and 'None' or readouts.countdown(dyna.weakness_seconds);
    elseif id == 'dyna_objectives' then
        local complete, total = objective_count(dyna.objectives);
        return total == 0 and '--' or tostring(complete) .. ' / ' .. tostring(total);
    end
    local family = currency_family[id];
    if family then return number(dyna.currency and dyna.currency[family[1]] and dyna.currency[family[1]][family[2]]); end
    return '--';
end

local function value_for(id, view, settings)
    if not definitions[id] then return nil; end
    if id:sub(1, 5) == 'dyna_' then return dynamis_value(id, view, settings.display.short); end
    if not view.valid and id ~= 'status' then return '--'; end
    local lp = view.mode == 'lp';
    local function number(value) return readouts.format_number(value, settings.display.short); end
    if id == 'job' then
        local value = view.job_name or '--';
        if view.level then value = value .. ' ' .. tostring(view.level); end
        if view.effective_level and view.level and view.effective_level < view.level then value = value .. ' (sync ' .. view.effective_level .. ')'; end
        return value;
    elseif id == 'progress' then return number(view.current) .. ' / ' .. number(view.needed);
    elseif id == 'remaining' then return lp and view.lp and view.lp.blocked and 'Spend merits' or view.capped and 'Full' or number(view.remaining);
    elseif id == 'rate' then return number(view.rate);
    elseif id == 'eta' then return lp and view.lp and view.lp.blocked and 'Spend merits' or view.capped and 'Full' or ((view.eta and view.rate and view.rate > 0) and '~' .. readouts.format_time(view.eta) or '--');
    elseif id == 'chain' then
        local value = view.chain and tostring(view.chain) or '--';
        if view.chain_bonus and view.chain and view.chain > 0 then value = value .. ' (+' .. tostring(view.chain_bonus) .. '%)'; end
        return value;
    elseif id == 'chain_time' then
        if (view.chain_source == 'server' or view.chain_source == 'local') and view.chain_active ~= false
            and type(view.chain_left) == 'number' and view.chain_left >= 0 and view.chain_left < math.huge then
            return (view.chain_source == 'local' and '~' or '') .. readouts.format_time(view.chain_left);
        end
        return '--';
    elseif id == 'last' then return view.last_amount and '+' .. number(view.last_amount) .. ' ' .. string.upper(view.last_kind or (lp and 'LP' or 'EXP')) or '--';
    elseif id == 'percent' then return view.percent and string.format('%.1f%%', view.percent * 100) or '--';
    elseif id == 'merits' then return number(view.merits) .. ' / ' .. number(view.merit_cap);
    elseif id == 'merit_rate' then return view.lp and view.lp.rate and string.format('%.2f', view.lp.rate / rules.lp_per_merit) or '--';
    elseif id == 'merits_session' then return number(view.merits_gained);
    elseif id == 'merit_headroom' then return number(view.merit_headroom);
    elseif id == 'lp_remaining' then return view.lp and view.lp.blocked and 'Spend merits' or number(view.lp and view.lp.remaining);
    elseif id == 'merit_eta' then
        local progress = view.lp or {};
        return progress.blocked and 'Spend merits' or (progress.eta and progress.rate and progress.rate > 0 and '~' .. readouts.format_time(progress.eta) or '--');
    elseif id == 'goal' then
        local goal = view.goal;
        if goal and not goal.available then return '--'; end
        if goal and goal.complete then return 'Complete'; end
        local value = number(goal and goal.remaining or (not goal and view.goal_remaining)) .. ' ' .. (goal and (goal.unit or '') or 'LP') .. ' left';
        local eta = goal and goal.eta or (not goal and view.goal_eta);
        if eta then value = value .. ' (~' .. readouts.format_time(eta) .. ')'; end
        return value;
    elseif id == 'buffer' then return number(view.buffer_current) .. ' / ' .. number(view.buffer_needed);
    elseif id == 'session' then return number(lp and view.session_lp or view.session_exp);
    elseif id == 'net' then return number(lp and view.net_lp or view.net_exp);
    elseif id == 'elapsed' then return readouts.format_time(view.elapsed);
    elseif id == 'average' then return number(view.average);
    elseif id == 'best_chain' then return number(view.best_chain);
    elseif id == 'dedication' then
        local value = view.dedication == nil and 'Dedication --' or (view.dedication and 'Dedication' or 'No Dedication');
        if view.dedication and view.dedication_seconds then value = value .. ' ' .. readouts.format_time(view.dedication_seconds); end
        return value;
    elseif id == 'status' then return not view.valid and 'Waiting for character' or view.paused and 'Paused' or view.capped and 'Full' or view.collecting and 'Calculating rate' or 'Tracking';
    elseif id == 'sync' then
        if not view.sync_active then return view.sync_active == false and 'Off' or '--'; end
        return number(view.level) .. ' > ' .. number(view.sync_level or view.effective_level)
            .. (view.sync_source == 'server' and type(view.sync_penalty) == 'number' and ' (-' .. number(view.sync_penalty) .. '%)' or ' (penalty unknown)');
    elseif id == 'no_exp' then return ({ sync_target = 'Level Sync target unavailable', distance = 'Too far for EXP' })[view.no_exp_reason] or '--';
    elseif id == 'exp_progress' or id == 'lp_progress' then
        local progress = view[id:sub(1, -10)] or {};
        return number(progress.current) .. ' / ' .. number(progress.needed);
    elseif id == 'exp_rate' or id == 'lp_rate' then return number((view[id:sub(1, -6)] or {}).rate);
    elseif id == 'exp_session' or id == 'lp_session' then return number(view['session_' .. id:sub(1, -9)]);
    elseif id == 'average3' then return number(view.recent3 and view.recent3.average);
    elseif id == 'average10' then return number(view.recent10 and view.recent10.average);
    elseif id == 'average_n' then return number(view.recent and view.recent.average);
    elseif id == 'sample_count' then return number(view.recent and view.recent.count) .. ' / ' .. number(view.recent and view.recent.requested);
    elseif id == 'minimum' then return number(view.recent and view.recent.min);
    elseif id == 'maximum' then return number(view.recent and view.recent.max);
    elseif id == 'median' then return number(view.recent and view.recent.median);
    elseif id == 'food' then
        local value = view.food == false and 'None' or view.food and (view.food_name or 'Active') or '--';
        if view.food and view.food_seconds then value = value .. ' ' .. readouts.format_time(view.food_seconds); end
        return value;
    elseif id == 'dedication_budget' then return number(view.dedication_pool);
    elseif id == 'ring' then
        if not view.rings or not view.rings.available then return '--'; end
        local ring;
        for _, entry in ipairs(view.rings.entries or {}) do if not ring or entry.ready and not ring.ready then ring = entry; end end
        if not ring then return 'None found'; end
        local value = (ring.name or 'EXP ring') .. ' ' .. number(ring.charges) .. ' charges';
        if ring.ready then return value .. ' recast ready'; end
        return value .. (ring.recast and ' ' .. readouts.format_time(ring.recast) or '');
    end
end

local function visible(condition, view, value)
    if condition == 'known' then return not value:find('--', 1, true); end
    if condition == 'exp' or condition == 'lp' then return view.mode == condition; end
    if condition == 'synced' then return view.sync_active == true or view.level and view.effective_level and view.effective_level < view.level; end
    if condition == 'chain' then
        return view.valid == true and (view.chain_source == 'server' and view.chain_active == true
            or view.chain_source == 'local' and type(view.chain_left) == 'number' and view.chain_left > 0 and view.chain_left < math.huge);
    end
    if condition == 'dedication' then return view.dedication == true; end
    if condition == 'food' then return view.food == true; end
    return true;
end

function readouts.build(settings, view)
    view = view or {};
    local result = {};
    for _, id in ipairs(settings.display.order) do
        local value = settings.display.enabled[id] and value_for(id, view, settings);
        if value and visible((settings.display.conditions or {})[id], view, value) then
            local label = settings.display.labels[id] or '';
            local unit = view.mode == 'lp' and 'LP' or 'EXP';
            local built_in = id == 'progress' and unit or id == 'rate' and unit .. '/HR' or nil;
            if built_in and label:upper() ~= built_in then label = label == '' and built_in or label .. ' ' .. built_in; end
            result[#result + 1] = { id = id, label = label, value = value,
                role = 'text' };
            if id == 'chain' or id == 'chain_time' then result[#result].role = 'chain'; end
        end
    end
    return result;
end

local dependencies = {
    job = 'job job_name level effective_level', progress = 'current needed', remaining = 'capped remaining lp.blocked', rate = 'rate', eta = 'capped eta rate lp.blocked',
    chain = 'chain chain_bonus', chain_time = 'chain_source chain_active chain_left', last = 'last_amount last_kind', percent = 'percent',
    merits = 'merits merit_cap', merit_rate = 'lp.rate', merits_session = 'merits_gained', merit_headroom = 'merit_headroom',
    lp_remaining = 'lp.remaining lp.blocked', merit_eta = 'lp.eta lp.rate lp.blocked', goal = 'goal goal_remaining goal_eta', buffer = 'buffer_current buffer_needed',
    session = 'session_exp session_lp', net = 'net_exp net_lp', elapsed = 'elapsed', average = 'average', best_chain = 'best_chain',
    dedication = 'dedication dedication_seconds', status = 'paused capped collecting', sync = 'sync_active level sync_level effective_level sync_source sync_penalty',
    no_exp = 'no_exp_reason', exp_progress = 'exp.current exp.needed', lp_progress = 'lp.current lp.needed', exp_rate = 'exp.rate', lp_rate = 'lp.rate',
    exp_session = 'session_exp', lp_session = 'session_lp', average3 = 'recent3.average', average10 = 'recent10.average', average_n = 'recent.average',
    sample_count = 'recent.count recent.requested', minimum = 'recent.min', maximum = 'recent.max', median = 'recent.median',
    food = 'food food_name food_seconds', dedication_budget = 'dedication_pool', ring = 'rings',
    dyna_zone = 'dynamis.active dynamis.name dynamis.short_name', dyna_time = 'dynamis.active dynamis.remaining dynamis.clock_estimated',
    dyna_extensions = 'dynamis.active dynamis.extension_minutes', dyna_currency = 'dynamis.active dynamis.currency_found',
    dyna_currency_received = 'dynamis.active dynamis.currency_received', dyna_currency_rate = 'dynamis.active dynamis.currency_rate',
    dyna_af2 = 'dynamis.active dynamis.af2', dyna_af2_received = 'dynamis.active dynamis.af2_received',
    dyna_kills = 'dynamis.active dynamis.kills', dyna_pool = 'dynamis.active dynamis.pool_count',
    dyna_objectives = 'dynamis.active dynamis.objectives', dyna_subjob = 'dynamis.active dynamis.subjob_locked',
    dyna_weakness = 'dynamis.active dynamis.weakness_seconds', dyna_next_entry = 'dynamis.next_entry_seconds',
};
for id, family in pairs(currency_family) do dependencies[id] = 'dynamis.active dynamis.currency.' .. family[1] .. '.' .. family[2]; end
for id, fields in pairs(dependencies) do
    local names = {}; for name in fields:gmatch('%S+') do names[#names + 1] = name; end
    dependencies[id] = names;
end
local condition_fields = { synced = { 'sync_active', 'level', 'effective_level' },
    chain = { 'chain_source', 'chain_active', 'chain_left' }, dedication = { 'dedication' }, food = { 'food' } };
local timer_fields = { chain_left = true, eta = true, ['lp.eta'] = true, goal_eta = true, elapsed = true, dedication_seconds = true, food_seconds = true, recast = true };
local countdown_fields = { ['dynamis.remaining'] = true, ['dynamis.weakness_seconds'] = true };
timer_fields['dynamis.next_entry_seconds'] = true;
local cached = setmetatable({}, { __mode = 'k' });

local function field_value(view, field)
    local value = view;
    for name in field:gmatch('[^.]+') do
        if type(value) ~= 'table' then return nil; end
        value = value[name];
    end
    return value;
end

local function append_key(parts, value, field)
    if type(value) == 'table' then
        parts[#parts + 1] = '{';
        for key, inner in pairs(value) do append_key(parts, key); append_key(parts, inner, key); end
        parts[#parts + 1] = '}';
    elseif type(value) == 'number' and countdown_fields[field] and value >= 0 and value < math.huge then
        parts[#parts + 1] = 'countdown' .. tostring(math.ceil(value));
    elseif type(value) == 'number' and timer_fields[field] and value >= 0 and value < math.huge then
        parts[#parts + 1] = (value > 0 and 't+' or 't0') .. tostring(math.floor(value + 0.5));
    else
        local text = tostring(value);
        parts[#parts + 1] = type(value) .. #text .. ':' .. text;
    end
end

local function same_items(before, after)
    if not before or #before ~= #after then return false; end
    for index, item in ipairs(after) do
        local previous = before[index];
        if previous.id ~= item.id or previous.label ~= item.label or previous.value ~= item.value or previous.role ~= item.role then return false; end
    end
    return true;
end

local function number_key(value, short)
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return nil; end
    local magnitude = math.abs(value);
    local sign = value < 0 and '-' or '';
    if short and magnitude >= 1000000 then return sign .. 'm' .. tostring(math.floor(magnitude / 100000 + 0.5)); end
    if short and magnitude >= 10000 then return sign .. 'k' .. tostring(math.floor(magnitude / 100 + 0.5)); end
    local rounded = math.floor(magnitude + 0.5);
    return value < 0 and '-' .. tostring(rounded) or rounded;
end

local function append_dependency(parts, view, id, field, short)
    local value = field_value(view, field);
    if id == 'dyna_objectives' and field == 'dynamis.objectives' then
        local complete, total = objective_count(value);
        value = tostring(complete) .. '/' .. tostring(total);
    elseif id == 'rate' or id == 'exp_rate' or id == 'lp_rate' or id == 'dyna_currency_rate' then
        value = number_key(value, short);
    elseif id == 'merit_rate' then
        value = value and string.format('%.2f', value / rules.lp_per_merit) or '--';
    elseif (id == 'eta' or id == 'merit_eta') and (field == 'rate' or field == 'lp.rate') then
        value = value and value > 0 or false;
    end
    append_key(parts, value, field);
end

-- Keep only the current formatted line. Rates and timers change at their displayed precision.
function readouts.cached(settings, view, sample)
    view = view or {};
    local parts = {};
    append_key(parts, view.valid); append_key(parts, view.mode); append_key(parts, settings.display.short);
    for _, id in ipairs(settings.display.order) do
        if settings.display.enabled[id] then
            local condition = (settings.display.conditions or {})[id];
            append_key(parts, id); append_key(parts, settings.display.labels[id]); append_key(parts, condition);
            for _, field in ipairs(dependencies[id] or {}) do append_dependency(parts, view, id, field, settings.display.short); end
            for _, field in ipairs(condition_fields[condition] or {}) do append_key(parts, view[field], field); end
        end
    end
    local key = table.concat(parts, '|');
    local slots = cached[settings];
    if not slots then slots = {}; cached[settings] = slots; end
    local slot = sample and 'sample' or 'live';
    local entry = slots[slot];
    if not entry or entry.key ~= key then
        local items = readouts.build(settings, view);
        if entry and same_items(entry.items, items) then
            -- Keep the layout while the displayed values stay the same.
            entry.key = key;
        else
            entry = { key = key, items = items };
            slots[slot] = entry;
        end
    end
    return entry.items;
end

function readouts.text(settings, view)
    local result = {};
    for _, part in ipairs(layout.segments(readouts.cached(settings, view), settings.display)) do
        result[#result + 1] = (part.gap and string.rep(' ', math.ceil(part.gap / 4)) or '') .. part.text;
    end
    return table.concat(result);
end

function readouts.summary(view)
    local num, time = readouts.format_number, readouts.format_time;
    return table.concat({
        'Momentum session',
        'Time: ' .. time(view.elapsed) .. (view.paused and ' (paused)' or ''),
        'EXP received: ' .. num(view.session_exp) .. ' | EXP change: ' .. num(view.net_exp),
        'LP received: ' .. num(view.session_lp) .. ' | LP change: ' .. num(view.net_lp),
        'EXP lost: ' .. num(view.lost) .. ' | Recovered: ' .. num(view.recovered),
        'Other EXP changes: ' .. num(view.adjustment),
        'Merit points earned: ' .. num(view.merits_gained) .. ' | Stored: ' .. num(view.merits) .. ' / ' .. num(view.merit_cap),
        'Best EXP chain: ' .. num(view.best_chain),
        'Current rate: ' .. num(view.rate) .. ' ' .. (view.mode == 'lp' and 'LP' or 'EXP') .. '/HR',
        'At a cap, EXP or LP received can be more than the amount you keep.',
    }, '\n');
end

function readouts.sample(scenario)
    local sample = {
        valid = true, job = 1, job_name = 'WAR', level = 61, effective_level = 61, mode = 'exp',
        current = 12450, needed = 20000, remaining = 7550, percent = 0.6225, rate = 8500, eta = 3198,
        session_exp = 6375, session_lp = 0, net_exp = 6200, net_lp = 0, lost = 525, recovered = 350, adjustment = 0,
        merits = 3, merit_cap = 10, merit_headroom = 7, merit_full = false, merits_gained = 0, elapsed = 2700, last_amount = 240, last_kind = 'exp', average = 185,
        chain = 4, chain_bonus = 40, chain_left = 38, chain_window = 60, chain_source = 'server', chain_active = true,
        best_chain = 5, paused = false, collecting = false, capped = false, dedication = true,
        dedication_seconds = 1830, buffer_current = 12450, buffer_needed = 20000, goal_remaining = nil, goal_eta = nil,
    };
    if scenario == 'Merits' or scenario == 'Capped' then
        sample.level, sample.effective_level, sample.mode = 75, 75, 'lp';
        sample.current, sample.needed, sample.remaining, sample.percent = 7250, 10000, 2750, 0.725;
        sample.rate, sample.eta, sample.session_lp, sample.net_lp = 12500, 792, 17250, 17250;
        sample.last_kind, sample.merits_gained = 'lp', 1;
        sample.buffer_current, sample.buffer_needed, sample.goal_eta, sample.goal_remaining = 43999, 44000, 3672, 12750;
    end
    if scenario == 'Capped' then
        sample.current, sample.remaining, sample.percent, sample.merits, sample.capped = 9999, 0, 0.9999, 10, true;
        sample.merit_headroom, sample.merit_full = 0, true;
        sample.eta, sample.goal_eta, sample.goal_remaining = nil, nil, 0;
    elseif scenario == 'No data' then
        return { valid = false, mode = 'exp', collecting = true };
    elseif scenario == 'Paused' then
        sample.paused = true;
    end
    sample.exp = { current = sample.buffer_current, needed = sample.buffer_needed, rate = sample.mode == 'exp' and sample.rate or 0,
        session = sample.session_exp, net = sample.net_exp };
    sample.lp = { current = sample.mode == 'lp' and sample.current or 0, needed = 10000,
        remaining = sample.mode == 'lp' and sample.remaining or 10000, eta = sample.mode == 'lp' and sample.eta or nil,
        blocked = sample.merit_full, rate = sample.mode == 'lp' and sample.rate or 0, session = sample.session_lp, net = sample.net_lp };
    sample.recent3 = { count = 3, requested = 3, average = 198.33, min = 170, max = 240, median = 185, total = 595 };
    sample.recent10 = { count = 10, requested = 10, average = 185, min = 100, max = 240, median = 180, total = 1850 };
    sample.recent = defaults.copy(sample.recent10);
    sample.sync_active, sample.sync_source, sample.sync_gap = false, 'unknown', 0;
    sample.food, sample.food_seconds = true, 840;
    sample.rings = { available = false, entries = {} };
    if scenario == 'Dynamis' then
        sample.dynamis = {
            active = true, zone = 185, name = 'Dynamis - San d\'Oria', short_name = 'San d\'Oria',
            remaining = 3832, extension_minutes = 55, extension_count = 3, currency_found = 247, currency_received = 12,
            currency_rate = 294, af2 = 4, af2_received = 1, kills = 83, partial = false, pool_count = 2,
            subjob_locked = false, clear_owned = true, next_entry_seconds = 254232, start_time = 1780000000,
            currency = { bronze = { found = 247, received = 12, singles_found = 147, hundreds_found = 1 },
                byne = { found = 0, received = 0, singles_found = 0, hundreds_found = 0 },
                shell = { found = 0, received = 0, singles_found = 0, hundreds_found = 0 } },
            objectives = { { id = 'boss', name = 'Overlord\'s Tombstone', status = 'unknown', help = 'Defeat the zone boss.' },
                { id = 'extension', name = 'Time extension statue', status = 'complete', help = 'This statue was defeated during the observed run.' } },
            weakening = {}, extensions = { { minutes = 15, time = 1780000300 }, { minutes = 15, time = 1780000720 }, { minutes = 25, time = 1780001100 } },
            loot = { { item_id = 15132, name = 'Warrior\'s Calligae', kind = 'af2', job = 'WAR', found = 1, received = 1, lost = 0, awarded = 1, pending = 0 } },
            pool = { { name = 'Ordelle Bronzepiece', item_id = 1452, remaining = 185 }, { name = 'Warrior\'s Calligae', item_id = 15132, remaining = 92 } },
            history = {},
        };
    end
    return sample;
end

function readouts.definition(id)
    return definitions[id];
end

return readouts;
