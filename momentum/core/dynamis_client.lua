local rules = require('data.dynamis_rules');
local bit = require('bit');
local client = {};
local methods = {};
methods.__index = methods;

local function uint(data, offset, size)
    if type(data) ~= 'string' or #data < offset + size then return nil; end
    local value = 0;
    for i = size - 1, 0, -1 do value = value * 256 + data:byte(offset + i + 1); end
    return value;
end

local function valid(event, size)
    return type(event) == 'table' and not event.injected and type(event.data) == 'string'
        and type(event.size) == 'number' and event.size >= size and #event.data >= event.size;
end

local function call(object, name, ...)
    if not object or type(object[name]) ~= 'function' then return nil; end
    local ok, value = pcall(object[name], object, ...);
    if ok then return value; end
end

function client.glass(item_id, count, extra)
    if item_id ~= rules.hourglass_id or type(count) ~= 'number' or count < 1 or type(extra) ~= 'string' or #extra < 24
        or bit.band(extra:byte(3), 7) ~= 1 then return nil; end
    local ending, started, zone = uint(extra, 8, 4), uint(extra, 12, 4), uint(extra, 16, 2);
    if not rules.zones[zone] or started < 1009810800 or ending <= started or ending - started > 86400 then return nil; end
    return { zone = zone, start_time = started, end_time = ending };
end

function client.parse(event)
    if not valid(event, 4) then return nil; end
    local data, id = event.data, event.id;
    if id == 0x00A and valid(event, 60) then
        return 'zone', { id = uint(data, 4, 4), zone = uint(data, 48, 2), utc = uint(data, 56, 4) };
    elseif id == 0x020 and valid(event, 41) then
        return 'item', { bag = uint(data, 14, 1), slot = uint(data, 15, 1),
            glass = client.glass(uint(data, 12, 2), uint(data, 4, 4), data:sub(18, 41)) };
    elseif id == 0x0D2 and valid(event, 28) then
        local slot, item, count = uint(data, 20, 1), uint(data, 16, 2), uint(data, 4, 4);
        if slot > 9 or count > 999 then return nil; end
        return 'drop', { slot = slot, item_id = item, count = count, old = uint(data, 21, 1) ~= 0,
            start_time = uint(data, 24, 4), source_id = uint(data, 8, 4) };
    elseif id == 0x0D3 and valid(event, 22) then
        local slot, result = uint(data, 20, 1), uint(data, 21, 1);
        if slot > 9 or result > 3 then return nil; end
        return 'lot', { slot = slot, kind = result == 1 and 'win' or result == 0 and 'lot' or 'lost',
            winner_id = uint(data, 4, 4) };
    elseif id == 0x02A and valid(event, 28) then
        return 'message', { actor = uint(data, 4, 4), message = bit.band(uint(data, 26, 2), 0x7FFF),
            first = uint(data, 8, 4), second = uint(data, 12, 4) };
    elseif id == 0x029 and valid(event, 28) then
        local message = bit.band(uint(data, 24, 2), 0x7FFF);
        if message == 6 or message == 20 then return 'death', { id = uint(data, 8, 4) }; end
    elseif id == 0x00E and valid(event, 34) then
        -- Seeing a living mob again establishes a new cycle. A disappearance is not a death.
        local flags = uint(data, 10, 1);
        if bit.band(flags, 4) ~= 0 and bit.band(flags, 32) == 0 and uint(data, 30, 1) > 0 then
            return 'spawn', { id = uint(data, 4, 4) };
        end
    end
end

function client.new(core, options)
    options = options or {};
    return setmetatable({ core = core, memory = options.memory or AshitaCore:GetMemoryManager(),
        server_clock = options.utc, local_clock = options.clock or os.time, seen = {}, seen_order = {},
        inventory_dirty = true, retries = 0, clock_estimated = true }, methods);
end

function methods:utc(now)
    local current = self.server_clock and self.server_clock();
    if type(current) == 'number' and current > 1009810800 then
        self.clock_estimated = false;
        return current;
    end
    if self.server_utc and now >= self.server_at then
        self.clock_estimated = false;
        return self.server_utc + now - self.server_at;
    end
    self.clock_estimated = true;
    return self.local_clock();
end

function methods:context(id, zone, now, settings)
    if type(id) ~= 'number' or id <= 0 or type(zone) ~= 'number' or zone <= 0 then return; end
    local enabled = not settings.dynamis or settings.dynamis.enabled ~= false;
    if self.id ~= id or self.zone ~= zone or self.enabled ~= enabled then
        self.id, self.zone, self.enabled = id, zone, enabled;
        self.inventory_dirty, self.glass_slot, self.retries, self.inventory_at = true, nil, 0, nil;
        self.pool_seeded = false;
        self.seen, self.seen_order = {}, {};
    end
    self.core:context(id, enabled and zone or 0, now, self:utc(now));
end

function methods:inventory(now)
    if not self.enabled or not rules.zones[self.zone] or not self.inventory_dirty then return; end
    if self.inventory_at and now - self.inventory_at < 0.25 then return; end
    self.inventory_at = now;
    local inventory = call(self.memory, 'GetInventory');
    if not inventory then self.inventory_dirty = false; return; end
    local best, location;
    for bag = 0, 16 do
        local size = call(inventory, 'GetContainerCountMax', bag);
        if type(size) == 'number' then
            for slot = 1, math.min(80, math.max(0, size)) do
                local item = call(inventory, 'GetContainerItem', bag, slot);
                local glass = item and client.glass(item.Id, item.Count, item.Extra);
                if glass and glass.zone == self.zone and (not best or glass.start_time > best.start_time
                    or glass.start_time == best.start_time and glass.end_time > best.end_time) then
                    best, location = glass, { bag = bag, slot = slot };
                end
            end
        end
    end
    self.retries = self.retries + 1;
    self.inventory_dirty = not best and self.retries < 5;
    if best then
        self.glass_slot = location;
        self.core:hourglass(best, now, self:utc(now));
    end
end

function methods:seed_pool(now)
    if self.pool_seeded then return; end
    local inventory = call(self.memory, 'GetInventory');
    if not inventory then return; end
    self.pool_seeded = true;
    for slot = 0, 9 do
        local item = call(inventory, 'GetTreasurePoolItem', slot);
        if item and type(item.Id) == 'number' and item.Id > 0 and type(item.Count) == 'number' and item.Count > 0 then
            -- Existing treasure is pending loot, not a newly observed drop.
            self.core:drop({ slot = slot, item_id = item.Id, count = item.Count,
                old = true, seed = true }, now, self:utc(now));
        end
    end
end

function methods:sample(snapshot, now, settings)
    if not snapshot or not snapshot.valid then return; end
    self:context(snapshot.id, snapshot.zone, now, settings);
    if not self.enabled or not rules.zones[self.zone] then return; end
    self:inventory(now);
    self:seed_pool(now);
    local stats = call(self.memory, 'GetPlayer');
    local icons, timers = call(stats, 'GetStatusIcons'), call(stats, 'GetStatusTimers');
    if not icons then icons, timers = call(stats, 'GetBuffs'), nil; end
    local effects = {};
    if icons then
        effects.subjob_locked = false;
        local weak = false;
        local effect_ids = rules.status_effects or { subjob_locked = 157, weakness = 1 };
        for slot = 0, 31 do
            if icons[slot] == effect_ids.subjob_locked then effects.subjob_locked = true; end
            if icons[slot] == effect_ids.weakness then
                weak = true;
                local raw = timers and timers[slot];
                if not self.clock_estimated and type(raw) == 'number' and raw ~= 0 and raw ~= 0x7FFFFFFF then
                    local ticks = (raw - (self:utc(now) - 0x3C307D70) * 60) % 4294967296;
                    if ticks <= 604800 * 60 then effects.weakness_seconds = ticks / 60; end
                end
            end
        end
        if not weak then effects.weakness_seconds = 0;
        elseif not effects.weakness_seconds then effects.weakness_unknown = true; end
    end
    local ki = rules.zones[self.zone].clear_ki;
    if ki then effects.clear_owned = call(stats, 'HasKeyItem', ki); end
    self.core:effects(effects, now);
end

function methods:packet(event, now, settings)
    if event.id ~= 0x00A then
        if not self.enabled then return; end
        if not rules.zones[self.zone] and event.id ~= 0x02A then return; end
    end
    local kind, value = client.parse(event);
    if not kind then return; end
    if kind == 'zone' then
        if value.utc > 1009810800 then self.server_utc, self.server_at = value.utc, now; end
        self:context(value.id, value.zone, now, settings);
        return;
    end
    if not self.enabled then return; end
    local token = tostring(event.id) .. ':' .. event.data:sub(1, event.size);
    if self.seen[token] then return; end
    self.seen[token] = true;
    self.seen_order[#self.seen_order + 1] = token;
    if #self.seen_order > 256 then self.seen[table.remove(self.seen_order, 1)] = nil; end
    local zone = rules.zones[self.zone];
    if not zone then
        if kind == 'message' and value.actor == self.id and value.first == rules.hourglass_id then
            for zone_id, info in pairs(rules.zones) do
                for _, entry in ipairs(info.entry_zones or {}) do
                    if entry == self.zone and value.message == info.registration_message then
                        self.core:registration(zone_id, now, self:utc(now));
                        return;
                    end
                end
            end
        end
        return;
    end
    -- The sequence and payload distinguish equal rewards while ignoring retransmissions.
    local utc = self:utc(now);
    if kind == 'item' then
        if value.glass and value.glass.zone == self.zone then
            self.glass_slot = { bag = value.bag, slot = value.slot };
            self.core:hourglass(value.glass, now, utc);
        elseif self.glass_slot and self.glass_slot.bag == value.bag and self.glass_slot.slot == value.slot then
            self.inventory_dirty, self.retries = true, 0;
        end
    elseif kind == 'drop' or kind == 'lot' then
        self:inventory(now);
        value.token = token;
        self.core[kind](self.core, value, now, utc);
    elseif kind == 'message' and value.message == zone.extension_message and value.actor == self.id
        and value.first > 0 and value.first <= 1440 and value.second == 1 then
        self.core:extension(value.first, now, utc, token);
        self.inventory_dirty, self.retries = true, 0;
    elseif kind == 'death' or kind == 'spawn' then
        if zone.mob_names and zone.mob_names[value.id] then
            self.core[kind](self.core, value.id, now, utc);
        end
    end
end

return client;
