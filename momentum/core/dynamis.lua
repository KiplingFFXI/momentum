local rules = require('data.dynamis_rules')
local dynamis = {}
local methods = {}
methods.__index = methods

local HISTORY_LIMIT = 100
local HISTORY_DEFAULT = 30
local ITEM_LIMIT = 1024
local TOKEN_LIMIT = 1024
local EXTENSION_LIMIT = 64
local PENDING_LIMIT = 32
local POOL_LIFETIME = 297
local families = { 'byne', 'shell', 'bronze' }

local function number(value)
    if type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then return value end
end

local function integer(value, maximum)
    return number(value) and value >= 0 and value == math.floor(value) and value <= (maximum or 1000000000)
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function zone_rule(zone)
    return rules.zones and rules.zones[zone]
end

local function item_rule(id)
    return rules.items and rules.items[id]
end

local function array(value, limit)
    if type(value) ~= 'table' or #value > limit then return false end
    for key in pairs(value) do
        if not integer(key, limit) or key < 1 or key > #value then return false end
    end
    return true
end

local function mob_in_zone(id, zone)
    return integer(id, 4294967295) and id >= 16777216 and math.floor(id / 4096) % 4096 == zone
end

local function settings_for(settings)
    if type(settings) ~= 'table' then return {} end
    return type(settings.dynamis) == 'table' and settings.dynamis or settings
end

local function bounded_append(values, value, limit)
    if #values >= limit then table.remove(values, 1) end
    values[#values + 1] = value
end

local function empty_currency()
    local result = {}
    for _, family in ipairs(families) do
        result[family] = { found = 0, received = 0, singles_found = 0, hundreds_found = 0,
            singles_received = 0, hundreds_received = 0 }
    end
    return result
end

local function summarize(run)
    local zone = zone_rule(run.zone) or {}
    local extension_minutes = run.extension_minutes
    if number(zone.starting_seconds) then
        extension_minutes = math.max(extension_minutes, 0, math.floor((run.end_time - run.start_time - zone.starting_seconds) / 60))
    end
    local currency, found, received, af2, af2_received = empty_currency(), 0, 0, 0, 0
    for id, row in pairs(run.loot) do
        local item = item_rule(id)
        if item and item.kind == 'currency' then
            local value = item.value or 1
            found = found + row.found * value
            received = received + row.received * value
            local family = currency[item.family]
            if family then
                family.found = family.found + row.found * value
                family.received = family.received + row.received * value
                local prefix = value == 100 and 'hundreds_' or 'singles_'
                family[prefix .. 'found'] = family[prefix .. 'found'] + row.found
                family[prefix .. 'received'] = family[prefix .. 'received'] + row.received
            end
        elseif item and item.kind == 'af2' then
            af2 = af2 + row.found
            af2_received = af2_received + row.received
        end
    end
    return { zone = run.zone, name = zone.name or ('Dynamis ' .. run.zone), short_name = zone.short_name or zone.name,
        start_time = run.start_time, end_time = run.end_time, finished_at = run.finished_at,
        currency_found = found, currency_received = received, currency = currency,
        af2 = af2, af2_received = af2_received, kills = run.kills, partial = run.partial,
        extension_minutes = extension_minutes, extension_count = run.extension_count,
        elapsed = math.max(0, (run.finished_at or run.last_utc) - run.tally_since) }
end

local function new_run(id, zone, glass, utc, partial)
    return { player_id = id, zone = zone, start_time = glass.start_time, end_time = glass.end_time,
        tally_since = math.max(glass.start_time, utc), last_utc = utc, partial = partial, loot = {}, loot_count = 0,
        kills = 0, dead = {}, observed = {}, extensions = {}, extension_minutes = 0, extension_count = 0 }
end

function dynamis.new()
    return setmetatable({ revision = 0, history_rows = {}, lockouts = {}, pool = {}, tokens = {}, token_order = {},
        alerts = {}, pending = {}, confirmed = false, verified = false, effects_state = {}, warned = {} }, methods)
end

function methods:_change()
    self.revision = self.revision + 1
    self.cache = nil
end

function methods:_clock(now, utc)
    now = number(now) or self.last_now or 0
    self.last_now = math.max(self.last_now or now, now)
    if number(utc) then self.last_utc = utc end
    return self.last_now, number(utc) or self.last_utc or 0
end

function methods:_queue(id, message, values)
    local event = values or {}
    event.id, event.message = id, message
    bounded_append(self.alerts, event, 128)
end

function methods:_token(token)
    if not token then return true end
    if self.tokens[token] then return false end
    if #self.token_order >= TOKEN_LIMIT then self.tokens[table.remove(self.token_order, 1)] = nil end
    self.tokens[token] = true
    self.token_order[#self.token_order + 1] = token
    return true
end

function methods:_defer(kind, values, now, utc, token)
    if not self.confirmed or not zone_rule(self.zone) then return false end
    if #self.pending >= PENDING_LIMIT then
        table.remove(self.pending, 1)
        self.pending_partial = true
    end
    self.pending[#self.pending + 1] = { kind = kind, values = values, now = now, utc = utc, token = token }
    return true
end

function methods:_ready()
    return self.confirmed and self.verified and self.current and self.current.zone == self.zone
end

function methods:_finish(utc)
    if not self.current then return false end
    local run = self.current
    run.finished_at = math.max(run.tally_since, math.min(utc, run.end_time))
    run.last_utc = utc
    bounded_append(self.history_rows, summarize(run), self.retention or HISTORY_DEFAULT)
    self.resume = run
    self.current, self.verified = nil, false
    self.pool, self.pending, self.warned = {}, {}, {}
    self:_change()
    return true
end

function methods:context(id, zone, now, utc)
    now, utc = self:_clock(now, utc)
    if not integer(id, 4294967295) or id == 0 or not integer(zone, 4095) then return false end
    if self.confirmed and self.player_id == id and self.zone == zone then return false end
    if self.player_id ~= id then
        self:_finish(utc)
        self.current, self.resume = nil, nil
        self.history_rows, self.lockouts = {}, {}
    elseif self.current and self.current.zone ~= zone then
        self:_finish(utc)
    end
    self.player_id, self.zone, self.confirmed = id, zone, true
    self.context_utc = utc
    self.pool, self.pending, self.alerts, self.effects_state = {}, {}, {}, {}
    self.pending_partial = false
    self:_change()
    return true
end

function methods:hourglass(glass, now, utc)
    now, utc = self:_clock(now, utc)
    if type(glass) ~= 'table' or not self.confirmed or not zone_rule(self.zone) or glass.zone ~= self.zone then return false end
    if not number(glass.start_time) or not number(glass.end_time) or glass.start_time < 0
        or glass.end_time <= glass.start_time or glass.end_time - glass.start_time > 86400 or glass.start_time > utc + 60 then return false end
    local changed = false
    local run = self.current
    if not run or run.start_time ~= glass.start_time then
        if glass.end_time <= utc then return false end
        if run then self:_finish(utc) end
        local resumed = self.resume
        if resumed and resumed.player_id == self.player_id and resumed.zone == self.zone and resumed.start_time == glass.start_time then
            run = resumed
            run.partial, run.finished_at = true, nil
            self.resume = nil
            local last = self.history_rows[#self.history_rows]
            if last and last.zone == run.zone and last.start_time == run.start_time then table.remove(self.history_rows) end
        else
            run = new_run(self.player_id, self.zone, glass, utc,
                self.pending_partial == true or (self.context_utc or utc) - glass.start_time > 30)
        end
        self.current, self.pool, self.warned = run, {}, {}
        self.tokens, self.token_order = {}, {}
        changed = true
    end
    if run.end_time ~= glass.end_time then run.end_time = glass.end_time; changed = true end
    if not self.verified then changed = true end
    self.verified = true
    run.last_utc = utc
    if changed then self:_change() end
    local pending = self.pending
    self.pending = {}
    for _, event in ipairs(pending) do self[event.kind](self, event.values, event.now, event.utc, event.token) end
    return changed or #pending > 0
end

function methods:extension(minutes, now, utc, token)
    now, utc = self:_clock(now, utc)
    if not integer(minutes, 240) or minutes == 0 then return false end
    if not self:_ready() then return self:_defer('extension', minutes, now, utc, token) end
    if token and not self:_token('extension:' .. tostring(token)) then return false end
    local run = self.current
    run.extension_minutes = run.extension_minutes + minutes
    run.extension_count = run.extension_count + 1
    bounded_append(run.extensions, { minutes = minutes, time = utc }, EXTENSION_LIMIT)
    run.last_utc = utc
    self:_queue('dyna_extension', 'Time extension: +' .. minutes .. ' minutes.', { minutes = minutes })
    self:_change()
    return true
end

function methods:_loot(id)
    local run = self.current
    if not run.loot[id] then
        if run.loot_count >= ITEM_LIMIT then run.partial = true; return nil end
        run.loot[id] = { found = 0, received = 0, awarded = 0, lost = 0 }
        run.loot_count = run.loot_count + 1
    end
    return run.loot[id]
end

function methods:drop(value, now, utc)
    now, utc = self:_clock(now, utc)
    if type(value) ~= 'table' or not integer(value.slot, 9) or not integer(value.item_id, 65535)
        or not integer(value.count or 1, 99) or (value.count or 1) == 0 then return false end
    if not self:_ready() then return self:_defer('drop', copy(value), now, utc) end
    local slot = value.slot
    if value.item_id == 0 then
        if not self.pool[slot] then return false end
        self.pool[slot] = nil
        self:_change()
        return true
    end
    local count = value.count or 1
    local start = number(value.start_time)
    local generation = start and (slot .. ':' .. value.item_id .. ':' .. start .. ':' .. count) or nil
    local prior = self.pool[slot]
    if value.seed == true and prior then return false end
    local token = value.token and ('packet:' .. tostring(value.token)) or (generation and ('drop:' .. generation))
    if prior and prior.item_id == value.item_id and prior.start_time == start and prior.count == count
        and (value.old == true or not value.token or prior.event_token == value.token) then return false end
    if token and not self:_token(token) then return false end
    if prior and value.old ~= true then self.current.partial = true end
    self.pool[slot] = { slot = slot, item_id = value.item_id, count = count, start_time = start,
        seen_at = value.old ~= true and now or nil, seen_utc = value.old ~= true and utc or nil, old = value.old == true,
        source_id = integer(value.source_id, 4294967295) and value.source_id or nil, event_token = value.token }
    local item = item_rule(value.item_id)
    if value.old == true then self.current.partial = true end
    if item then
        local row = self:_loot(value.item_id)
        if row and value.old ~= true then
            row.found = row.found + count
            self:_queue('dyna_wanted', 'Wanted drop: ' .. item.name .. '.', { item_id = value.item_id, job = item.job })
        end
    end
    self.current.last_utc = utc
    self:_change()
    return true
end

function methods:lot(value, now, utc)
    now, utc = self:_clock(now, utc)
    if type(value) ~= 'table' or not integer(value.slot, 9) then return false end
    if not self:_ready() then return self:_defer('lot', copy(value), now, utc) end
    if value.kind ~= 'win' and value.kind ~= 'lost' then return false end
    local slot = self.pool[value.slot]
    if not slot then return false end
    local item = item_rule(slot.item_id)
    if item then
        local row = self:_loot(slot.item_id)
        if row then
            if value.kind == 'lost' then
                row.lost = row.lost + slot.count
            elseif integer(value.winner_id, 4294967295) and value.winner_id > 0 then
                row.awarded = row.awarded + slot.count
                if value.winner_id == self.player_id then row.received = row.received + slot.count end
            else
                self.current.partial = true
            end
        end
    end
    self.pool[value.slot] = nil
    self.current.last_utc = utc
    self:_change()
    return true
end

function methods:death(id, now, utc)
    now, utc = self:_clock(now, utc)
    if not mob_in_zone(id, self.zone) then return false end
    if not self:_ready() then return self:_defer('death', id, now, utc) end
    local run = self.current
    if run.dead[id] then return false end
    run.dead[id], run.observed[id] = true, true
    run.kills = run.kills + 1
    run.last_utc = utc
    self:_change()
    return true
end

function methods:spawn(id, now, utc)
    now, utc = self:_clock(now, utc)
    if not mob_in_zone(id, self.zone) then return false end
    if not self:_ready() then
        local needed = self.current and self.current.dead[id] == true or false
        for _, event in ipairs(self.pending) do
            if event.values == id and event.kind == 'death' then needed = true
            elseif event.values == id and event.kind == 'spawn' then needed = false end
        end
        return needed and self:_defer('spawn', id, now, utc) or false
    end
    if not self.current.dead[id] then return false end
    self.current.dead[id] = nil
    self:_change()
    return true
end

function methods:effects(values, now)
    now = self:_clock(now)
    if type(values) ~= 'table' or not self.confirmed or not zone_rule(self.zone) then return false end
    local old = self.effects_state
    local changed = false
    for _, key in ipairs({ 'subjob_locked', 'clear_owned' }) do
        if type(values[key]) == 'boolean' and values[key] ~= old[key] then
            if key == 'subjob_locked' and old[key] == true and values[key] == false then
                self:_queue('dyna_subjob', 'Your support job is unlocked.')
            elseif key == 'clear_owned' and old[key] == false and values[key] == true then
                self:_queue('dyna_clear', 'Dynamis clear obtained.')
            end
            old[key], changed = values[key], true
        end
    end
    if values.weakness_unknown == true and old.weakness_end ~= nil then
        old.weakness_end, changed = nil, true
    elseif number(values.weakness_seconds) and values.weakness_seconds >= 0 then
        local deadline = values.weakness_seconds == 0 and 0 or now + values.weakness_seconds
        if not old.weakness_end or math.abs(deadline - old.weakness_end) >= 1 then
            old.weakness_end, changed = deadline, true
        end
    end
    if changed then self.cache = nil end
    return changed
end

function methods:registration(zone, now, utc)
    now, utc = self:_clock(now, utc)
    local rule = zone_rule(zone)
    local duration = rule and (rule.lockout_seconds or rules.lockout_seconds)
    if not duration or not number(duration) or duration <= 0 or not self.player_id then return false end
    for id in pairs(rules.zones) do self.lockouts[id] = utc + duration end
    self:_change()
    return true
end

local function objectives_for(run, rule)
    local result = {}
    for _, objective in ipairs(rule.objectives or {}) do
        local done, total = 0, #(objective.mobs or {})
        for _, id in ipairs(objective.mobs or {}) do if run and run.observed[id] then done = done + 1 end end
        local complete = total > 0 and (objective.any and done > 0 or done == total)
        result[#result + 1] = { id = objective.id, name = objective.name, help = objective.help,
            done = done, total = total, complete = complete,
            status = complete and 'complete' or ((not run or run.partial) and 'unknown' or 'incomplete') }
    end
    return result
end

function methods:view(now, utc, settings)
    now, utc = self:_clock(now, utc)
    local options = settings_for(settings)
    local retention = math.max(1, math.min(HISTORY_LIMIT, math.floor(number(options.retention) or HISTORY_DEFAULT)))
    if self.retention ~= retention then
        self.retention = retention
        while #self.history_rows > retention do table.remove(self.history_rows, 1); self:_change() end
    end
    local second = math.floor(now)
    local utc_second = math.floor(utc)
    if self.cache and self.cache_second == second and self.cache_utc == utc_second then return self.cache end
    local rule = self.confirmed and zone_rule(self.zone) or nil
    local run = self:_ready() and self.current or nil
    local result = run and summarize(run) or { currency_found = 0, currency_received = 0, currency = empty_currency(),
        af2 = 0, af2_received = 0, kills = 0, partial = rule ~= nil, extension_minutes = 0, extension_count = 0, elapsed = 0 }
    result.active = rule ~= nil
    result.zone = self.zone
    result.name = rule and (rule.name or ('Dynamis ' .. self.zone)) or nil
    result.short_name = rule and (rule.short_name or rule.name) or nil
    result.info = rule and rule.info or nil
    result.remaining = run and math.max(0, math.ceil(run.end_time - utc)) or nil
    result.elapsed = run and math.max(0, math.min(utc, run.end_time) - run.tally_since) or 0
    result.currency_rate = result.elapsed >= 60 and result.currency_found > 0 and result.currency_found * 3600 / result.elapsed or nil
    result.history = self.history_rows
    result.extensions = run and run.extensions or {}
    result.objectives = rule and objectives_for(run, rule) or {}
    result.weakening = {}
    for id, entry in pairs(rule and rule.weakening or {}) do
        local done = run and run.observed[id] == true or false
        result.weakening[#result.weakening + 1] = { id = id, name = entry.name, help = entry.help, complete = done,
            done = done, status = done and 'complete' or ((not run or run.partial) and 'unknown' or 'incomplete') }
    end
    if #result.weakening > 1 then table.sort(result.weakening, function(a, b) return a.id < b.id end) end
    result.loot, result.pool, result.pool_count = {}, {}, 0
    local pending = {}
    for _, slot in pairs(self.pool) do
        result.pool_count = result.pool_count + 1
        pending[slot.item_id] = (pending[slot.item_id] or 0) + slot.count
        local item = item_rule(slot.item_id)
        result.pool[#result.pool + 1] = { slot = slot.slot, item_id = slot.item_id, name = item and item.name,
            count = slot.count, remaining = slot.seen_at and math.max(0, math.ceil(POOL_LIFETIME - now + slot.seen_at)) or nil,
            approximate = true, old = slot.old }
    end
    if #result.pool > 1 then table.sort(result.pool, function(a, b) return a.slot < b.slot end) end
    for id, row in pairs(run and run.loot or {}) do
        local item = item_rule(id)
        if item then
            result.loot[#result.loot + 1] = { item_id = id, name = item.name, kind = item.kind, job = item.job,
                found = row.found, received = row.received, awarded = row.awarded, lost = row.lost, pending = pending[id] or 0 }
        end
    end
    if #result.loot > 1 then
        table.sort(result.loot, function(a, b)
            if a.kind ~= b.kind then return a.kind < b.kind end
            return a.name < b.name
        end)
    end
    result.subjob_locked = rule and self.effects_state.subjob_locked or nil
    if rule and self.effects_state.subjob_locked == false then result.subjob_locked = false end
    result.clear_owned = rule and self.effects_state.clear_owned or nil
    if rule and self.effects_state.clear_owned == false then result.clear_owned = false end
    result.weakness_seconds = rule and self.effects_state.weakness_end and math.max(0, math.ceil(self.effects_state.weakness_end - now)) or nil
    local lockout
    for _, deadline in pairs(self.lockouts) do lockout = math.max(lockout or deadline, deadline) end
    result.next_entry_seconds = lockout and math.max(0, math.ceil(lockout - utc)) or nil
    result.lockouts = lockout and { { name = 'Dynamis', remaining = result.next_entry_seconds, end_time = lockout } } or {}
    self.cache, self.cache_second, self.cache_utc = result, second, utc_second
    return result
end

function methods:take_alerts(now, settings, utc)
    now, utc = self:_clock(now, utc)
    local options = settings_for(settings)
    local result, queued = {}, self.alerts
    self.alerts = {}
    for _, event in ipairs(queued) do
        local wanted = event.id ~= 'dyna_wanted'
            or (type(options.wanted_items) == 'table' and (options.wanted_items[tostring(event.item_id)] == true or options.wanted_items[event.item_id] == true))
            or (type(options.wanted_jobs) == 'table' and options.wanted_jobs[event.job] == true)
        if wanted then result[#result + 1] = event end
    end
    if not self:_ready() then return result end
    local remaining = math.max(0, self.current.end_time - utc)
    local nearest
    local warnings = type(options.warning_minutes) == 'table' and options.warning_minutes or { 10, 5, 1 }
    for index, minute in ipairs(warnings) do
        if index > 16 then break end
        if number(minute) and minute > 0 and minute <= 240 then
            if remaining > minute * 60 + 5 then
                self.warned[minute] = nil
            elseif remaining <= minute * 60 and not self.warned[minute] then
                if not nearest or minute < nearest then nearest = minute end
                self.warned[minute] = true
            end
        end
    end
    if nearest and remaining > 0 then
        local minutes = math.ceil(remaining / 60)
        result[#result + 1] = { id = 'dyna_time', message = 'Dynamis: ' .. minutes .. (minutes == 1 and ' minute left.' or ' minutes left.'), minutes = nearest }
    end
    local warning = math.max(0, math.min(300, number(options.pool_warning_seconds) or 60))
    local count, aged, oldest = 0, 0, nil
    for _, slot in pairs(self.pool) do
        count = count + 1
        local left = slot.seen_at and POOL_LIFETIME - now + slot.seen_at or nil
        if warning > 0 and left and left <= warning and not slot.warned then
            slot.warned = true
            aged, oldest = aged + 1, slot.item_id
        end
    end
    if aged > 0 then
        local item = item_rule(oldest)
        result[#result + 1] = { id = 'dyna_pool', item_id = aged == 1 and oldest or nil,
            message = aged == 1 and ((item and item.name or 'An item') .. ' has been in the treasure pool for a while. Check your lot.')
                or (aged .. ' items have been in the treasure pool for a while. Check your lots.') }
    end
    if count >= 9 and not self.pool_warned then
        result[#result + 1] = { id = 'dyna_pool', message = 'Treasure pool: ' .. count .. '/10. Check your lots.' }
        self.pool_warned = true
    elseif count < 9 then self.pool_warned = false end
    return result
end

function methods:clear_totals(now, utc)
    now, utc = self:_clock(now, utc)
    if not self:_ready() then return false end
    local run = self.current
    run.loot, run.loot_count, run.kills = {}, 0, 0
    run.tally_since, run.last_utc, run.partial = math.max(run.start_time, utc), utc, true
    -- Existing pool items can still be received after the totals are cleared.
    self:_change()
    return true
end

function methods:close(now, utc)
    now, utc = self:_clock(now, utc)
    local changed = self:_finish(utc)
    self.zone, self.confirmed, self.verified = nil, false, false
    self.pool, self.pending, self.alerts, self.effects_state = {}, {}, {}, {}
    self.cache = nil
    return changed
end

local function export_map(value)
    local result = {}
    for key, entry in pairs(value) do result[tostring(key)] = copy(entry) end
    return result
end

local function export_run(value)
    if not value then return nil end
    local result = copy(value)
    result.loot, result.dead, result.observed = export_map(value.loot), export_map(value.dead), export_map(value.observed)
    return result
end

function methods:export()
    return { version = 1, player_id = self.player_id, zone = self.zone, current = export_run(self.current),
        resume = export_run(self.resume), history = copy(self.history_rows), lockouts = export_map(self.lockouts) }
end

local function restore_id_set(value, zone)
    if type(value) ~= 'table' then return nil end
    local result, count = {}, 0
    for id, present in pairs(value) do
        id = tonumber(id)
        count = count + 1
        if count > 4096 or not mob_in_zone(id, zone) or present ~= true then return nil end
        result[id] = true
    end
    return result
end

local function restore_run(value, id)
    if value == nil then return nil, true end
    if type(value) ~= 'table' or value.player_id ~= id or not zone_rule(value.zone)
        or not number(value.start_time) or not number(value.end_time) or value.start_time < 0
        or value.end_time <= value.start_time or value.end_time - value.start_time > 86400
        or not number(value.tally_since) or not number(value.last_utc) or value.tally_since < value.start_time
        or not integer(value.kills) or not integer(value.extension_minutes, 10000) or not integer(value.extension_count, 1000)
        or type(value.partial) ~= 'boolean' or not array(value.extensions, EXTENSION_LIMIT) or type(value.loot) ~= 'table' then return nil, false end
    if value.finished_at ~= nil and not number(value.finished_at) then return nil, false end
    local dead = restore_id_set(value.dead, value.zone)
    local observed = restore_id_set(value.observed, value.zone)
    if not dead or not observed then return nil, false end
    local run = new_run(id, value.zone, value, value.tally_since, true)
    run.dead, run.observed, run.kills = dead, observed, value.kills
    run.extension_minutes, run.extension_count = value.extension_minutes, value.extension_count
    run.finished_at, run.last_utc = value.finished_at, value.last_utc
    for _, entry in ipairs(value.extensions) do
        if type(entry) ~= 'table' or not integer(entry.minutes, 240) or entry.minutes == 0 or not number(entry.time) then return nil, false end
        run.extensions[#run.extensions + 1] = { minutes = entry.minutes, time = entry.time }
    end
    for item_id, entry in pairs(value.loot) do
        item_id = tonumber(item_id)
        if not item_rule(item_id) or run.loot_count >= ITEM_LIMIT or type(entry) ~= 'table' then return nil, false end
        local row = {}
        for _, key in ipairs({ 'found', 'received', 'awarded', 'lost' }) do
            if not integer(entry[key]) then return nil, false end
            row[key] = entry[key]
        end
        run.loot[item_id] = row
        run.loot_count = run.loot_count + 1
    end
    return run, true
end

local function restore_summary(value)
    if type(value) ~= 'table' or not zone_rule(value.zone) or type(value.partial) ~= 'boolean' then return nil end
    local result = { zone = value.zone, partial = value.partial }
    for _, key in ipairs({ 'start_time', 'end_time', 'finished_at', 'elapsed' }) do
        if not number(value[key]) or value[key] < 0 then return nil end
        result[key] = value[key]
    end
    for _, key in ipairs({ 'currency_found', 'currency_received', 'af2', 'af2_received', 'kills', 'extension_minutes', 'extension_count' }) do
        if not integer(value[key]) then return nil end
        result[key] = value[key]
    end
    result.currency = empty_currency()
    if type(value.currency) ~= 'table' then return nil end
    for _, family in ipairs(families) do
        if type(value.currency[family]) ~= 'table' then return nil end
        for key in pairs(result.currency[family]) do
            if not integer(value.currency[family][key]) then return nil end
            result.currency[family][key] = value.currency[family][key]
        end
    end
    local rule = zone_rule(value.zone)
    result.name, result.short_name = rule.name, rule.short_name or rule.name
    return result
end

function methods:restore(payload, now, utc)
    if type(payload) ~= 'table' or payload.version ~= 1 or not integer(payload.player_id, 4294967295) or payload.player_id == 0
        or not array(payload.history, HISTORY_LIMIT) or type(payload.lockouts) ~= 'table' then return false, 'Saved Dynamis data is invalid.' end
    if self.player_id and self.player_id ~= payload.player_id then return false, 'Saved Dynamis data belongs to another character.' end
    if payload.zone ~= nil and not integer(payload.zone, 4095) then return false, 'Saved Dynamis zone is invalid.' end
    local current, current_ok = restore_run(payload.current, payload.player_id)
    local resume, resume_ok = restore_run(payload.resume, payload.player_id)
    if not current_ok or not resume_ok then return false, 'Saved Dynamis run is invalid.' end
    if current and payload.zone ~= current.zone then return false, 'Saved Dynamis run does not match its zone.' end
    local history, lockouts, count = {}, {}, 0
    for _, entry in ipairs(payload.history) do
        local row = restore_summary(entry)
        if not row then return false, 'Saved Dynamis history is invalid.' end
        history[#history + 1] = row
    end
    for zone, deadline in pairs(payload.lockouts) do
        zone = tonumber(zone)
        count = count + 1
        if count > 16 or not zone_rule(zone) or not number(deadline) or deadline < 0 then return false, 'Saved Dynamis entry time is invalid.' end
        lockouts[zone] = deadline
    end
    self.player_id, self.zone = payload.player_id, payload.zone
    self.current, self.resume, self.history_rows, self.lockouts = current, resume, history, lockouts
    self.confirmed, self.verified = false, false
    self.pool, self.pending, self.alerts, self.effects_state, self.warned = {}, {}, {}, {}, {}
    self.tokens, self.token_order = {}, {}
    self:_clock(now, utc)
    self:_change()
    return true
end

return dynamis
