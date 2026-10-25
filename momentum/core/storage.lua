local packets = require('core.packets');
local storage = {};
local methods = {};
methods.__index = methods;

local names = { 'inventory', 'satchel' };
local definitions = { inventory = { id = 0, mask = 1 }, satchel = { id = 5, mask = 32 } };
local updates = { [0x01E] = { minimum = 10, bag = 8 }, [0x01F] = { minimum = 12, bag = 10 },
    [0x020] = { minimum = 16, bag = 14 } };

local function integer(value, maximum)
    return type(value) == 'number' and value == value and value >= 0 and value <= maximum
        and value == math.floor(value);
end

local function uint(data, offset, count)
    local value = 0;
    for index = count - 1, 0, -1 do value = value * 256 + data:byte(offset + index + 1); end
    return value;
end

local function inventory()
    local memory = AshitaCore and AshitaCore:GetMemoryManager();
    return memory and memory:GetInventory();
end

local function default_backend()
    return {
        flags = function()
            local current = inventory();
            return current and current:GetContainerUpdateFlags();
        end,
        counter = function()
            local current = inventory();
            return current and current:GetContainerUpdateCounter();
        end,
        counts = function(id)
            local current = inventory();
            if current then return current:GetContainerCount(id), current:GetContainerCountMax(id); end
        end,
    };
end

local function call(backend, name, ...)
    if type(backend[name]) ~= 'function' then return nil; end
    local ok, first, second = pcall(backend[name], ...);
    if ok then return first, second; end
end

local function clear_values(self)
    self.values.inventory, self.values.satchel = nil, nil;
end

local function mark_dirty(self)
    self.dirty = true;
end

local function ready(self, definition)
    return self.all_loaded or self.flags and math.floor(self.flags / definition.mask) % 2 == 1;
end

-- A reset waits for new inventory packets. A new reader can use data already loaded by the client.
function methods:reset()
    clear_values(self);
    self.id, self.zone, self.expected_id, self.expected_zone = nil, nil, nil, nil;
    self.flags, self.all_loaded, self.late_load = nil, false, false;
    self.checked, self.dirty = nil, true;
end

function storage.new(backend)
    return setmetatable({ backend = backend or default_backend(), values = {}, entries = { inventory = {}, satchel = {} },
        selected = {}, all_loaded = false, late_load = true, dirty = true }, methods);
end

function methods:packet(event)
    if type(event) ~= 'table' and type(event) ~= 'userdata' then return; end
    if event.id == 0x00A and packets.valid(event, 50) then
        local id = uint(event.data, 4, 4);
        if id == 0 then return; end
        self:reset();
        self.expected_id, self.expected_zone = id, uint(event.data, 48, 2);
        return;
    end
    if event.id == 0x00B and packets.valid(event, 5) and event.data:byte(5) == 1 then
        self:reset();
        return;
    end
    if event.id == 0x01D and packets.valid(event, 12) then
        local state = event.data:byte(5);
        if state > 1 then return; end
        self.flags, self.all_loaded, self.late_load = uint(event.data, 8, 4), state == 1, false;
        for _, name in ipairs(names) do
            if not ready(self, definitions[name]) then self.values[name] = nil; end
        end
        mark_dirty(self);
        return;
    end
    if event.id == 0x01C and packets.valid(event, 72) then
        for _, name in ipairs(names) do
            local id = definitions[name].id;
            if uint(event.data, 4 + id, 1) > 81 or uint(event.data, 36 + id * 2, 2) > 81 then return; end
        end
        mark_dirty(self);
        return;
    end
    local update = updates[event.id];
    if update and packets.valid(event, update.minimum) then
        local id = event.data:byte(update.bag + 1);
        if id == 0 or id == 5 then mark_dirty(self); end
    end
end

function methods:observe(snapshot, t, demand)
    demand = type(demand) == 'table' and demand or {};
    local any = false;
    for _, name in ipairs(names) do
        local selected = demand[name] == true;
        if selected ~= self.selected[name] then self.selected[name], self.dirty = selected, true; end
        if not selected then self.values[name] = nil; end
        any = any or selected;
    end
    if not any then clear_values(self); return; end
    if not snapshot or not snapshot.valid or not integer(snapshot.id, 4294967295) or snapshot.id == 0
        or not integer(snapshot.zone, 65535) or type(t) ~= 'number' or t ~= t or math.abs(t) == math.huge then
        clear_values(self);
        self.dirty = true;
        return;
    end
    if self.expected_id and (snapshot.id ~= self.expected_id or snapshot.zone ~= self.expected_zone) then
        clear_values(self);
        return;
    end
    if self.id and (snapshot.id ~= self.id or snapshot.zone ~= self.zone) then
        self:reset();
    end
    self.id, self.zone = snapshot.id, snapshot.zone;
    self.expected_id, self.expected_zone = nil, nil;
    if self.checked and t >= self.checked and t - self.checked < (self.dirty and 0.2 or 1) then return; end
    self.checked = t;

    if self.late_load then
        local flags = call(self.backend, 'flags');
        if integer(flags, 4294967295) then self.flags = flags; end
    end
    self.dirty = false;
    local can_read = false;
    for _, name in ipairs(names) do
        if self.selected[name] then
            if ready(self, definitions[name]) then can_read = true;
            else self.values[name] = nil; end
        end
    end
    if not can_read then return; end
    local before = call(self.backend, 'counter');
    for _, name in ipairs(names) do
        if self.selected[name] then
            if ready(self, definitions[name]) then
                local used, capacity = call(self.backend, 'counts', definitions[name].id);
                if integer(used, 80) and integer(capacity, 80) and capacity > 0 and used <= capacity then
                    local entry = self.entries[name];
                    entry.used, entry.capacity, entry.free = used, capacity, capacity - used;
                    self.values[name] = entry;
                else
                    self.values[name] = nil;
                end
            else
                self.values[name] = nil;
            end
        end
    end
    local after = call(self.backend, 'counter');
    if integer(before, 4294967295) and integer(after, 4294967295) and before ~= after then
        clear_values(self);
        self.dirty = true;
    end
end

function methods:view()
    return self.values;
end

return storage;
