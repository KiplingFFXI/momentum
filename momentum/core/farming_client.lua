local packets = require('core.packets');
local client = {};
local methods = {};
methods.__index = methods;

local function integer(value, maximum)
    return type(value) == 'number' and value == value and value >= 0 and value <= maximum and value == math.floor(value);
end

local function uint(data, offset, size)
    local value = 0;
    for index = size - 1, 0, -1 do value = value * 256 + data:byte(offset + index + 1); end
    return value;
end

local function call(object, method, ...)
    if not object or type(object[method]) ~= 'function' then return nil; end
    local ok, value = pcall(object[method], object, ...);
    return ok and value or nil;
end

local function valid(event, minimum)
    return packets.valid(event, minimum) and integer(event.size, 512) and #event.data >= event.size;
end

local function token(event, kind, length)
    if event.data_raw == nil then return nil; end
    return kind .. ':' .. tostring(event.data_raw):sub(1, 96) .. ':' .. event.data:sub(1, length);
end

local function partial(model)
    if model.available and not model.paused then model:mark_partial(); end
end

local function tick()
    local clock = ashita and ashita.time and ashita.time.get_tick64;
    if type(clock) ~= 'function' then return nil; end
    local ok, value = pcall(clock);
    value = ok and tonumber(value) or nil;
    return type(value) == 'number' and value == value and value >= 0 and value < math.huge and value or nil;
end

function client.new()
    return setmetatable({ pool = {}, done = {}, done_order = {}, terminal = {}, closed = {},
        metadata = {}, metadata_order = {} }, methods);
end

function methods:reset()
    self.id, self.zone, self.seeded = nil, nil, nil;
    self.pool, self.done, self.done_order, self.terminal, self.closed = {}, {}, {}, {}, {};
end

function methods:remember(key)
    if self.done[key] then return false; end
    self.done[key] = true;
    self.done_order[#self.done_order + 1] = key;
    if #self.done_order > 256 then self.done[table.remove(self.done_order, 1)] = nil; end
    return true;
end

function methods:observe(snapshot)
    if type(snapshot) ~= 'table' or snapshot.valid ~= true or not integer(snapshot.id, 4294967295) or snapshot.id == 0
        or not integer(snapshot.zone, 65535) or snapshot.zone == 0 then self:reset(); return; end
    if self.id ~= snapshot.id or self.zone ~= snapshot.zone then
        self:reset();
        self.id, self.zone = snapshot.id, snapshot.zone;
    end
    if self.seeded then return; end
    local memory = call(AshitaCore, 'GetMemoryManager');
    local inventory = call(memory, 'GetInventory');
    if not inventory or type(inventory.GetTreasurePoolItem) ~= 'function' then return; end
    self.seeded = true;
    for slot = 0, 9 do
        local item = call(inventory, 'GetTreasurePoolItem', slot);
        if item and integer(item.ItemId, 65534) and item.ItemId > 0 and integer(item.Count, 999) and item.Count > 0 then
            self.pool[slot] = { id = item.ItemId, count = item.Count, seeded = true };
        end
    end
end

function methods:packet(event, now, model, config)
    if not self.id or not model or not valid(event, 4) or type(now) ~= 'number' or now ~= now or now < 0 or now == math.huge then return; end
    local data = event.data;
    if event.id == 0x0D2 and valid(event, 28) then
        local count, item, slot = uint(data, 4, 4), uint(data, 16, 2), uint(data, 20, 1);
        if slot > 9 or count > 999 or item == 65535 then return; end
        if item == 0 or count == 0 then self.pool[slot] = nil; return; end
        local old, started = uint(data, 21, 1) ~= 0, uint(data, 24, 4);
        local key = slot .. ':' .. item .. ':' .. count .. ':' .. started;
        local prior = self.pool[slot];
        if prior and (prior.key == key or prior.seeded and prior.id == item and prior.count == count) then
            prior.key, prior.at, prior.seeded = key, prior.at or now, false;
            return;
        end
        local received = token(event, 'drop', 28) or 'drop:' .. data:sub(1, 28);
        if received and not self:remember(received) then return; end
        local closed = self.closed[slot];
        if old and closed and (closed.key == key or not closed.key and closed.id == item and closed.count == count) then return; end
        if prior and not old then partial(model); end
        self.pool[slot] = { id = item, count = count, at = now, key = key,
            source_id = uint(data, 8, 4), is_container = uint(data, 22, 1) ~= 0, old = old };
        if not old then model:found(item, count, now); end
    elseif event.id == 0x0D3 and valid(event, 22) then
        local slot, result = uint(data, 20, 1), uint(data, 21, 1);
        if slot > 9 or result > 3 or result == 0 then return; end
        local received = token(event, 'solution', 22);
        if received and not self:remember(received) then return; end
        local item = self.pool[slot];
        self.pool[slot] = nil;
        local terminal = data:sub(1, 22);
        if not item then
            if result == 1 and uint(data, 4, 4) == self.id and self.terminal[slot] ~= terminal then
                partial(model);
            end
            self.terminal[slot] = terminal;
            return;
        end
        self.closed[slot] = item;
        self.terminal[slot] = terminal;
        if result ~= 1 or uint(data, 4, 4) ~= self.id then return; end
        if item.at and (now < item.at or now - item.at > 600) then partial(model); return; end
        return model:received(item.id, item.count, now, config);
    elseif event.id == 0x029 and valid(event, 28) then
        if uint(data, 24, 2) ~= 565 or uint(data, 4, 4) ~= self.id or uint(data, 8, 4) ~= self.id then return; end
        local amount = uint(data, 12, 4);
        if amount == 0 or amount > 999999999 then return; end
        local received = token(event, 'gil', 28);
        if received and not self:remember(received) then return; end
        return model:mob_gil(amount, now);
    end
end

function methods:cache_item(id, value)
    local name = value and value.Name and value.Name[1];
    local info;
    if type(name) == 'string' then name = name:gsub('[%c]', ''); end
    if type(name) == 'string' and name:find('%S') and name ~= '.' then
        local stack = tonumber(value.StackSize);
        info = { id = id, name = name, stack_size = integer(stack, 999) and stack > 0 and stack or 1 };
    end
    if self.metadata[id] == nil then self.metadata_order[#self.metadata_order + 1] = id; end
    self.metadata[id] = info or false;
    if #self.metadata_order > 1024 then self.metadata[table.remove(self.metadata_order, 1)] = nil; end
    return info;
end

function methods:item(id)
    if not integer(id, 65534) or id == 0 then return nil; end
    if self.metadata[id] ~= nil then return self.metadata[id] or nil; end
    local resources = call(AshitaCore, 'GetResourceManager');
    return self:cache_item(id, call(resources, 'GetItemById', id));
end

function methods:search(query)
    query = type(query) == 'string' and query:lower():match('^%s*(.-)%s*$') or '';
    local id = tonumber(query);
    if id then local item = self:item(id); return item and { item } or {}, false; end
    if #query < 2 or #query > 80 then return {}, false; end
    if not self.searching or self.searching.query ~= query then self.searching = { query = query, cursor = 1, rows = {} }; end
    local search = self.searching;
    if #search.rows >= 50 or search.cursor > 65534 then return search.rows, false; end
    local resources = call(AshitaCore, 'GetResourceManager');
    local started = tick();
    for _ = 1, 64 do
        local item_id = search.cursor;
        local value = call(resources, 'GetItemById', item_id);
        local name = value and value.Name and value.Name[1];
        if type(name) == 'string' and name:lower():find(query, 1, true) then
            local info = self:cache_item(item_id, value);
            if info then search.rows[#search.rows + 1] = info; end
        end
        search.cursor = item_id + 1;
        local current = started and tick();
        if #search.rows >= 50 or search.cursor > 65534 or current and current - started >= 2 then break; end
    end
    return search.rows, #search.rows < 50 and search.cursor <= 65534;
end

return client;
