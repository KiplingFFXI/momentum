local rules = require('data.event_rules');
local events = {};
local methods = {};
methods.__index = methods;

local function finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge;
end

local function integer(value, maximum)
    return finite(value) and value >= 0 and value % 1 == 0 and value <= (maximum or 4294967295);
end

local function copy(value)
    if type(value) ~= 'table' then return value; end
    local result = {};
    for key, item in pairs(value) do result[key] = copy(item); end
    return result;
end

local function settings_for(settings)
    return type(settings) == 'table' and (settings.events or settings) or {};
end

local function append(values, value, limit)
    if #values >= limit then table.remove(values, 1); end
    values[#values + 1] = value;
end

local function valid_loot(values)
    if type(values) ~= 'table' or #values > 512 then return false; end
    for key, row in pairs(values) do
        if not integer(key, 512) or key < 1 or key > #values or type(row) ~= 'table'
            or not integer(row.item_id, 65535) or row.item_id == 0 or not integer(row.count, 100000)
            or type(row.name) ~= 'string' or #row.name > 160 then return false; end
    end
    return true;
end

local function battle(zone, index)
    local area = rules.areas and rules.areas[zone];
    return area and area.battles and area.battles[index];
end

local function loot_rows(run, side)
    local result = {};
    for id, row in pairs(run and run.loot or {}) do
        if row[side] > 0 then
            local item = rules.items and rules.items[id] or {};
            result[#result + 1] = { item_id = id, name = item.name or ('Item ' .. id), count = row[side],
                kind = item.kind, job = item.job, reward = item.reward };
        end
    end
    table.sort(result, function(a, b) return a.item_id < b.item_id; end);
    return result;
end

function events.new()
    return setmetatable({ revision = 0, history_rows = {}, currencies = {}, cooldowns = {}, entry_items = {},
        inventory = {}, pool = {}, alerts_queue = {}, tokens = {}, token_order = {}, visits = 0 }, methods);
end

function methods:change()
    self.revision = self.revision + 1;
    self.cached, self.cache_revision = nil, nil;
end

function methods:token(token)
    if token == nil then return true; end
    if self.tokens[token] then return false; end
    if #self.token_order >= 512 then self.tokens[table.remove(self.token_order, 1)] = nil; end
    self.tokens[token] = true;
    self.token_order[#self.token_order + 1] = token;
    return true;
end

function methods:queue(id, message, values)
    values = values or {};
    values.id, values.message = id, message;
    append(self.alerts_queue, values, 64);
end

function methods:finish(now, utc)
    local run = self.current;
    if not run then return false; end
    run.finished_at, run.last_utc = run.finished_at or utc, utc;
    local elapsed = run.reported_elapsed or math.max(0, run.finished_at - run.started_at);
    append(self.history_rows, { kind = run.kind, name = run.name, zone = run.zone, index = run.index,
        started_at = run.started_at, finished_at = run.finished_at, elapsed = elapsed, status = run.status,
        partial = run.partial, verified_elapsed = run.reported_elapsed ~= nil, kills = run.kills, points = run.points, exp = run.exp, lp = run.lp,
        extensions = run.extensions, extension_minutes = run.extension_minutes,
        drops = loot_rows(run, 'found'), received = loot_rows(run, 'received') }, self.retention or 30);
    self.last_run, self.current, self.pool = run, nil, {};
    self:change();
    return true;
end

function methods:context(id, zone, now, utc, observed)
    if not integer(id) or id == 0 or not integer(zone, 4095) or not finite(now) or not finite(utc) then return false; end
    if self.player_id == id and self.zone == zone and not observed then return false; end
    if self.player_id == id and self.zone == zone and observed and self.zone_observed then return false; end
    if self.player_id ~= id then
        self.current, self.last_run = nil, nil;
        self.history_rows, self.currencies, self.cooldowns, self.inventory, self.entry_items = {}, {}, {}, {}, {};
        self.assault_current, self.assault_completed, self.assault_report, self.resume = nil, nil, nil, nil;
        self.inventory_available, self.zone_name, self.time_signature, self.alerts_at = false, nil, nil, nil;
    elseif self.zone ~= zone then self:finish(now, utc); end
    self.player_id, self.zone, self.zone_at, self.zone_utc = id, zone, now, utc;
    self.zone_observed, self.zone_partial = observed == true, observed ~= true;
    self.visits = self.visits + 1;
    self.pool, self.alerts_queue, self.tokens, self.token_order = {}, {}, {}, {};
    self:change();
    return true;
end

function methods:begin(zone, index, now, utc, partial)
    local info = battle(zone, index);
    if not info or zone ~= self.zone then return false; end
    if self.current and self.current.zone == zone and self.current.index == index
        and self.current.status ~= 'Won' and self.current.status ~= 'Lost' then return true; end
    self:finish(now, utc);
    self.current = { kind = info.kind, name = info.name, zone = zone, index = index,
        started_at = utc, last_utc = utc, partial = partial == true, kills = 0, dead = {}, loot = {},
        points = 0, exp = 0, lp = 0, extensions = 0, extension_minutes = 0, status = 'Fighting',
        warnings = {}, observed_objectives = {}, objective_count = 0, waves_seen = 0, wave_alive = {},
        floor = info.floor_count == 1 and 1 or nil };
    self.pool = {};
    self.tokens, self.token_order = {}, {};
    self:change();
    return true;
end

function methods:timer(seconds, now, utc, estimated, initial)
    if not self.current or not finite(seconds) or seconds < 0 or seconds > 86400 then return false; end
    local run = self.current;
    if initial and run.timer_seen then return false; end
    if not run.timer_seen then run.previous_remaining = seconds; end
    run.ends_at, run.time_estimated, run.timer_seen = utc + seconds, estimated == true, true;
    if not estimated and not run.time_limit then run.time_limit = math.max(seconds, (battle(run.zone, run.index) or {}).time_limit or 0); end
    run.last_utc = utc;
    self:change();
    return true;
end

function methods:extension(minutes, now, utc, token)
    if not self.current or not integer(minutes, 240) or minutes == 0 or not self:token(token) then return false; end
    local run = self.current;
    run.extensions, run.extension_minutes = run.extensions + 1, run.extension_minutes + minutes;
    if run.ends_at then run.ends_at = run.ends_at + minutes * 60; run.time_estimated = true; end
    self:queue('event_extension', run.name .. ': +' .. minutes .. ' minutes.', { minutes = minutes });
    self:change();
    return true;
end

function methods:objective(text, complete, now, utc, key)
    local run = self.current;
    if not run or type(text) ~= 'string' or #text > 512 then return false; end
    key = key or text;
    if run.observed_objectives[key] then return false; end
    if run.objective_count >= 128 then run.partial = true; return false; end
    run.observed_objectives[key] = text;
    run.objective_count = run.objective_count + 1;
    if complete then run.status = run.kind == 'assault' and 'Rune ready' or 'Objective complete'; end
    run.last_objective, run.last_utc = text, utc;
    self:queue('event_objective', run.name .. ': ' .. text);
    self:change();
    return true;
end

function methods:death(id, now, utc, name)
    local run = self.current;
    if not run or not integer(id) or run.dead[id] then return false; end
    local area, info = rules.areas[run.zone], battle(run.zone, run.index);
    local mob = area and area.mobs and area.mobs[id];
    name = name or (type(mob) == 'table' and mob.name or mob);
    if type(name) ~= 'string' then return false; end
    local objective = info.objective or {};
    local allowed = objective.mobs;
    if objective.mob_ids and not objective.mob_ids[id] then return false; end
    if not objective.mob_ids and type(allowed) == 'table' and not allowed[id] and not allowed[name] then return false; end
    if info.mob_floors and next(info.mob_floors) and not info.mob_floors[id] then return false; end
    run.dead[id], run.kills, run.last_utc = true, run.kills + 1, utc;
    if run.wave_alive then
        run.wave_alive[id] = nil;
        if next(run.wave_alive) == nil then run.wave_ended_at = now; end
    end
    if info.mob_floors and info.mob_floors[id] then run.floor = info.mob_floors[id]; end
    self:change();
    return true;
end

function methods:spawn(id, now)
    local run = self.current;
    if not run then return false; end
    local info, area = battle(run.zone, run.index), rules.areas[run.zone];
    local objective = info and info.objective or {};
    local name = area and area.mobs and area.mobs[id];
    if objective.type == 'waves' and name and (not objective.mobs or objective.mobs[id] or objective.mobs[name]) then
        if not run.wave_alive[id] then
            if next(run.wave_alive) == nil and (run.waves_seen == 0 or run.wave_ended_at and now
                and now - run.wave_ended_at >= 5) then run.waves_seen = run.waves_seen + 1; end
            run.wave_alive[id] = true;
            self:change();
        end
    end
    if run.dead[id] then run.dead[id] = nil; return true; end
    return false;
end

function methods:position(x, y, z)
    local run = self.current;
    local info = run and battle(run.zone, run.index);
    if not info or not finite(x) or not finite(z) then return false; end
    for _, floor in ipairs(info.floors or {}) do
        if finite(floor.x_min) and finite(floor.x_max) and finite(floor.z_min) and finite(floor.z_max)
            and x >= floor.x_min and x <= floor.x_max and z >= floor.z_min and z <= floor.z_max
            and (not floor.y_min or finite(y) and y >= floor.y_min and y <= floor.y_max) then
            if run.floor ~= floor.index then run.floor = floor.index; self:change(); return true; end
            return false;
        end
    end
    return false;
end

function methods:drop(value, now, utc, token)
    local run = self.current;
    if not run or not integer(value.slot, 9) or not integer(value.item_id, 65535) or value.item_id == 0
        or not integer(value.count, 999) or value.count == 0 then return false; end
    local identity = value.start_time and value.start_time ~= 0 and value.item_id .. ':' .. value.start_time .. ':' .. value.slot;
    if identity and self.pool[value.slot] and self.pool[value.slot].identity == identity then return false; end
    local pending = self.pool[value.slot];
    if value.old and not identity and pending and pending.item_id == value.item_id and pending.count == value.count then return false; end
    if not self:token(token) then return false; end
    self.pool[value.slot] = { item_id = value.item_id, count = value.count, identity = identity, at = utc };
    if not run.loot[value.item_id] then
        local count = 0; for _ in pairs(run.loot) do count = count + 1; end
        if count >= 512 then run.partial = true; return false; end
        run.loot[value.item_id] = { found = 0, received = 0 };
    end
    if not value.old then
        run.loot[value.item_id].found = run.loot[value.item_id].found + value.count;
        self:queue('event_drop', run.name .. ': ' .. (((rules.items or {})[value.item_id] or {}).name or ('Item ' .. value.item_id)),
            { item_id = value.item_id, count = value.count });
    end
    run.last_utc = utc;
    self:change();
    return true;
end

function methods:lot(value, now, utc, token)
    local run, item = self.current, self.pool[value.slot];
    if not run or not item or value.kind == 'lot' or not self:token(token) then return false; end
    if value.kind == 'win' and value.winner_id == self.player_id and utc >= item.at and utc - item.at <= 600 then
        local row = run.loot[item.item_id];
        if row then row.received = row.received + item.count; end
    end
    self.pool[value.slot] = nil;
    self:change();
    return true;
end

function methods:award(value, now, utc)
    if not self.current or not integer(value.amount, 2147483647) or not self:token(value.token) then return false; end
    if value.kind ~= 'exp' and value.kind ~= 'lp' then return false; end
    self.current[value.kind] = self.current[value.kind] + value.amount;
    self.current.last_utc = utc;
    self:change();
    return true;
end

function methods:points(amount, now, utc, token)
    if not self.current or self.current.kind ~= 'assault' or not integer(amount, 1000000) or not self:token(token) then return false; end
    self.current.points, self.current.last_utc = self.current.points + amount, utc;
    self:change();
    return true;
end

function methods:outcome(won, now, utc, elapsed, record)
    local run = self.current;
    if not run or run.status == 'Won' or run.status == 'Lost' then return false; end
    run.status, run.last_utc, run.reported_elapsed = won and 'Won' or 'Lost', utc, integer(elapsed, 86400) and elapsed or nil;
    run.finished_at, run.ends_at = utc, nil;
    if run.kind == 'assault' then self.assault_report = run.index; end
    if integer(record, 86400) and record > 0 then run.record = record; end
    self:queue(won and 'event_clear' or 'event_failure', run.name .. (won and ': cleared.' or ': failed.'));
    self:change();
    return true;
end

function methods:currency(values, utc)
    if type(values) ~= 'table' then return false; end
    for key, value in pairs(values) do
        if type(key) == 'string' and #key <= 64 and integer(value, 2147483647) then
            self.currencies[key] = { value = value, observed_at = utc };
        end
    end
    self:change();
    return true;
end

function methods:cooldown(key, name, ready_at, utc, source, estimated)
    if type(key) ~= 'string' or #key > 80 or type(name) ~= 'string' or #name > 120
        or not finite(ready_at) or ready_at < 0 or ready_at > utc + 604800 * 30 then return false; end
    self.cooldowns[key] = { key = key, kind = key == 'limbus' and 'limbus' or key:match('^enm:') and 'enm' or 'assault',
        group = key:match('^enm:(.+)$'), name = name, ready_at = ready_at, observed_at = utc, observed = true,
        source = source, estimated = estimated == true, warned = ready_at <= utc };
    self:change();
    return true;
end

function methods:items(items, inventory)
    self.entry_items, self.inventory = copy(items or {}), copy(inventory or {});
    self:change();
end

function methods:view(now, utc, settings)
    local config, run = settings_for(settings), self.current;
    self.retention = math.max(1, math.min(100, tonumber(config.history_limit) or 30));
    while #self.history_rows > self.retention do table.remove(self.history_rows, 1); self:change(); end
    local result;
    if self.cached and self.cache_revision == self.revision then result = self.cached;
    else
        local area = rules.areas and rules.areas[self.zone];
        result = { active = run ~= nil and config.enabled ~= false, zone = self.zone,
            zone_name = area and area.name or self.zone_name or ('Zone ' .. tostring(self.zone or 0)),
            zone_partial = self.zone_partial ~= false, history = copy(self.history_rows),
            currencies = copy(self.currencies), entry_items = copy(self.entry_items), inventory = copy(self.inventory), cooldowns = {} };
        result.inventory_available = self.inventory_available == true;
        result.assault_current, result.assault_completed = self.assault_current, copy(self.assault_completed or {});
        result.assault_report = self.assault_report;
        for _, row in pairs(self.cooldowns) do result.cooldowns[#result.cooldowns + 1] = copy(row); end
        if #result.cooldowns > 1 then table.sort(result.cooldowns, function(a, b) return a.key < b.key; end); end
        if run then
            local info = battle(run.zone, run.index) or {};
            local objective = info.objective or {};
            for _, key in ipairs({ 'kind', 'name', 'index', 'status', 'kills', 'points', 'exp', 'lp', 'extensions', 'waves_seen',
                'extension_minutes', 'floor', 'record', 'partial', 'time_estimated', 'time_limit' }) do result[key] = run[key]; end
            result.duration, result.floors = run.time_limit or info.time_limit, info.floor_count or #(info.floors or {});
            result.drops, result.received = loot_rows(run, 'found'), loot_rows(run, 'received');
            result.coins_found, result.coins_received, result.materials_found, result.materials_received = 0, 0, 0, 0;
            result.chips_found, result.chips_received, result.trophies_found, result.trophies_received = 0, 0, 0, 0;
            for _, side in ipairs({ 'found', 'received' }) do
                for id, row in pairs(run.loot) do
                    local kind = ((rules.items or {})[id] or {}).kind;
                    local key = kind == 'coin' and 'coins_' or kind == 'material' and 'materials_'
                        or kind == 'chip' and 'chips_' or kind == 'trophy' and 'trophies_';
                    if key then result[key .. side] = result[key .. side] + row[side]; end
                end
            end
            result.objectives = {};
            for _, text in pairs(run.observed_objectives) do result.objectives[#result.objectives + 1] = text; end
            table.sort(result.objectives);
            if run.last_objective then result.objective = run.last_objective;
            elseif (objective.type == 'kills' or objective.type == 'rocks' or objective.type == 'repeated_deaths') and integer(objective.required, 10000) then
                result.objective = tostring(run.kills) .. '/' .. objective.required .. ' deaths seen';
            elseif objective.type == 'waves' and run.waves_seen > 0 then
                result.objective = '~' .. tostring(run.waves_seen) .. (objective.required and '/' .. objective.required or '') .. ' waves seen';
            else result.objective = objective.text or 'Progress not observed'; end
            result.objective_hint = objective.text;
            if run.floor and info.floors and info.floors[run.floor] then result.objective_hint = info.floors[run.floor].text or result.objective_hint; end
            result.level_cap, result.max_players, result.orb = info.level_cap, info.max_players, info.orb;
            result.required_items = copy(info.key_items or {});
            result.enm_group = info.enm_group;
            result.cooldown_key = info.enm_group and ('enm:' .. info.enm_group) or info.kind == 'limbus' and 'limbus' or nil;
            for _, row in ipairs(self.history_rows) do
                if row.zone == run.zone and row.index == run.index and row.status == 'Won' and not row.partial and row.verified_elapsed == true
                    and (not result.personal_best or row.elapsed < result.personal_best) then result.personal_best = row.elapsed; end
            end
        end
        self.cached, self.cache_revision = result, self.revision;
    end
    result.zone_elapsed = self.zone_at and math.max(0, now - self.zone_at) or nil;
    result.active = run ~= nil and config.enabled ~= false;
    if run then
        result.elapsed = run.reported_elapsed or math.max(0, (run.finished_at or utc) - run.started_at);
        result.remaining = run.ends_at and math.max(0, run.ends_at - utc) or nil;
    end
    for _, row in ipairs(result.cooldowns) do row.remaining, row.ready = math.max(0, row.ready_at - utc), row.ready_at <= utc; end
    return result;
end

function methods:take_alerts(now, utc, settings)
    local config, run = settings_for(settings), self.current;
    local configured = ((settings or {}).alerts or {}).events or {};
    local time_config = configured.event_time or {};
    local signature = tostring(time_config.visual == true) .. ':' .. tostring(time_config.sound == true)
        .. ':' .. tostring(config.warning_minutes or 5);
    local time_armed = self.time_signature == signature and self.alerts_at and now >= self.alerts_at and now - self.alerts_at <= 2;
    self.time_signature, self.alerts_at = signature, now;
    if run and run.ends_at then
        local remaining = run.ends_at - utc;
        local threshold = math.max(1, math.min(30, tonumber(config.warning_minutes) or 5)) * 60;
        if remaining > 0 and remaining <= threshold and run.previous_remaining and run.previous_remaining > threshold
            and time_armed and not run.warnings.time then
            run.warnings.time = true;
            self:queue('event_time', run.name .. ': ' .. math.ceil(remaining / 60) .. ' minutes left.');
        end
        run.previous_remaining = remaining;
    end
    for _, row in pairs(self.cooldowns) do
        if row.ready_at <= utc and not row.warned then
            row.warned = true;
            self:queue('event_ready', row.name .. ': ready.');
            self:change();
        end
    end
    local result = {};
    for _, alert in ipairs(self.alerts_queue) do
        if alert.id ~= 'event_drop' or type(config.wanted) == 'table'
            and (config.wanted[alert.item_id] == true or config.wanted[tostring(alert.item_id)] == true) then
            result[#result + 1] = alert;
        end
    end
    self.alerts_queue = {};
    if config.enabled == false then return {}; end
    return result;
end

function methods:clear(now, utc)
    self.history_rows = {};
    if self.current then
        local run = self.current;
        run.loot, run.points, run.exp, run.lp, run.kills = {}, 0, 0, 0, 0;
        run.dead, run.partial = {}, true;
    end
    self:change();
    return true;
end

function methods:export(utc)
    return { schema = 1, player_id = self.player_id, saved_at = utc, current = copy(self.current),
        history = copy(self.history_rows), currencies = copy(self.currencies), cooldowns = copy(self.cooldowns),
        assault_current = self.assault_current, assault_completed = copy(self.assault_completed or {}), assault_report = self.assault_report };
end

function methods:restore(data, utc)
    if type(data) ~= 'table' or data.schema ~= 1 or data.player_id ~= self.player_id
        or type(data.history) ~= 'table' or #data.history > 100 or type(data.currencies) ~= 'table'
        or type(data.cooldowns) ~= 'table' then return false, 'The saved event data could not be read.'; end
    for key in pairs(data.history) do
        if not integer(key, 100) or key < 1 or key > #data.history then return false, 'The saved event history could not be read.'; end
    end
    for _, row in ipairs(data.history) do
        if type(row) ~= 'table' or type(row.name) ~= 'string' or #row.name > 160
            or not integer(row.zone, 4095) or not integer(row.index, 65535) or not finite(row.elapsed)
            or row.elapsed < 0 or row.elapsed > 604800 or not finite(row.started_at) or not finite(row.finished_at)
            or type(row.status) ~= 'string' or #row.status > 80 or not valid_loot(row.drops) or not valid_loot(row.received)
            then return false, 'The saved event history could not be read.'; end
    end
    self.history_rows = copy(data.history);
    if integer(data.assault_current, 128) then self.assault_current = data.assault_current; end
    if type(data.assault_completed) == 'table' then
        self.assault_completed = {};
        for id, complete in pairs(data.assault_completed) do
            if integer(tonumber(id), 128) and type(complete) == 'boolean' then self.assault_completed[tonumber(id)] = complete; end
        end
    end
    if integer(data.assault_report, 128) then self.assault_report = data.assault_report; end
    local total = 0;
    for key, row in pairs(data.currencies) do
        total = total + 1;
        if total > 64 then return false, 'The saved currency snapshots could not be read.'; end
        if type(row) == 'table' and integer(row.value, 2147483647) and finite(row.observed_at) then
            self:currency({ [key] = row.value }, row.observed_at);
        end
    end
    total = 0;
    for key, row in pairs(data.cooldowns) do
        total = total + 1;
        if total > 64 then return false, 'The saved event cooldowns could not be read.'; end
        if type(row) == 'table' then
            self:cooldown(key, row.name, row.ready_at, finite(row.observed_at) and row.observed_at or utc,
                type(row.source) == 'string' and row.source:sub(1, 120) or 'Saved observation', row.estimated);
            if self.cooldowns[key] then self.cooldowns[key].warned = row.ready_at <= utc; end
        end
    end
    -- A saved fight resumes only after the client confirms the matching battlefield.
    if type(data.current) == 'table' and finite(data.saved_at) and utc >= data.saved_at and utc - data.saved_at <= 120 then
        self.resume = copy(data.current);
    end
    self:change();
    return true;
end

function methods:resume_run(zone, now, utc, confirmed)
    local run = self.resume;
    self.resume = nil;
    if not confirmed or not run or run.zone ~= zone or not battle(zone, run.index)
        or not finite(run.started_at) or run.started_at > utc or utc - run.started_at > 86400
        or type(run.loot) ~= 'table' or type(run.dead) ~= 'table' or type(run.observed_objectives) ~= 'table'
        or not integer(run.kills, 100000) or not integer(run.exp, 2147483647) or not integer(run.lp, 2147483647)
        or not integer(run.points, 2147483647) or not integer(run.extensions, 1000)
        or not integer(run.extension_minutes, 10000) or not integer(run.objective_count, 128)
        or run.kind ~= battle(zone, run.index).kind or run.name ~= battle(zone, run.index).name
        or type(run.status) ~= 'string' or #run.status > 80 then return false; end
    if run.reported_elapsed ~= nil and (not finite(run.reported_elapsed) or run.reported_elapsed < 0 or run.reported_elapsed > 86400)
        or run.finished_at ~= nil and (not finite(run.finished_at) or run.finished_at < run.started_at or run.finished_at > utc)
        or run.record ~= nil and (not finite(run.record) or run.record < 0 or run.record > 86400)
        or run.time_limit ~= nil and not integer(run.time_limit, 86400)
        or run.floor ~= nil and (not integer(run.floor, 100) or run.floor == 0)
        or run.last_objective ~= nil and (type(run.last_objective) ~= 'string' or #run.last_objective > 512) then return false; end
    local count = 0;
    for id, row in pairs(run.loot) do
        count = count + 1;
        if not integer(tonumber(id), 65535) or type(row) ~= 'table' or not integer(row.found, 100000)
            or not integer(row.received, 100000) or count > 512 then return false; end
    end
    count = 0;
    for key, text in pairs(run.observed_objectives) do
        count = count + 1;
        if type(key) ~= 'string' or #key > 512 or type(text) ~= 'string' or #text > 512 or count > 128 then return false; end
    end
    local dead = {};
    count = 0;
    for id, value in pairs(run.dead) do
        count = count + 1;
        if not integer(tonumber(id)) or type(value) ~= 'boolean' or count > 10000 then return false; end
        dead[tonumber(id)] = value;
    end
    local loot = {}; for id, row in pairs(run.loot) do loot[tonumber(id)] = row; end; run.loot = loot;
    run.dead = dead;
    run.partial, run.warnings, run.last_utc = true, { time = true }, utc;
    run.wave_alive, run.waves_seen = {}, integer(run.waves_seen, 1000) and run.waves_seen or 0;
    run.wave_ended_at = nil;
    if run.ends_at and (not finite(run.ends_at) or run.ends_at < utc or run.ends_at > utc + 86400) then run.ends_at = nil; end
    run.previous_remaining = run.ends_at and math.max(0, run.ends_at - utc) or nil;
    self.current, self.pool = run, {};
    self:change();
    return true;
end

return events;
