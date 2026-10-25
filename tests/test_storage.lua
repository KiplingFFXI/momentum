local storage = require('core.storage');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local function packet(id, size, fields)
    local data = MOCK.bytes(size);
    for _, field in ipairs(fields or {}) do MOCK.put(data, field[1], field[2], field[3]); end
    return MOCK.packet(id, data);
end
local function sync(flags, state)
    return packet(0x01D, 12, { { 4, 1, state or 0 }, { 8, 4, flags } });
end
local function zone(id, area)
    return packet(0x00A, 50, { { 4, 4, id }, { 48, 2, area } });
end
local function fixture(flags)
    local current = { valid = true, id = 1001, zone = 102 };
    local data = { flags = flags == nil and 33 or flags, counter = 1, flags_calls = 0, counter_calls = 0,
        reads = {}, bags = { [0] = { used = 37, capacity = 80 }, [5] = { used = 12, capacity = 50 } } };
    local reader = storage.new({
        flags = function() data.flags_calls = data.flags_calls + 1; return data.flags; end,
        counter = function() data.counter_calls = data.counter_calls + 1; return data.counter; end,
        counts = function(id)
            data.reads[#data.reads + 1] = id;
            if data.fail then error('Unavailable client API'); end
            if data.changing then data.counter = data.counter + 1; end
            return data.bags[id].used, data.bags[id].capacity;
        end,
    });
    return reader, data, current;
end
local both = { inventory = true, satchel = true };
local only_inventory = { inventory = true };
local reader, data, current = fixture();
local view = reader:view();
for index = 1, 100 do reader:observe(current, index / 100, {}); end
eq(data.flags_calls, 0, 'Disabled storage does not query readiness');
eq(data.counter_calls, 0, 'Disabled storage does not query update state');
eq(#data.reads, 0, 'Disabled storage does not query either bag');
reader:observe(current, 2, only_inventory);
eq(reader:view(), view, 'The outer view remains stable');
eq(view.inventory.used, 37, 'A late load accepts ready client inventory');
eq(view.inventory.capacity, 80, 'Inventory reports actual unlocked capacity');
eq(view.inventory.free, 43, 'Free slots subtract occupied slots');
eq(view.satchel, nil, 'Unselected Satchel stays absent');
eq(#data.reads, 1, 'Only one selected bag is read');
eq(data.reads[1], 0, 'Inventory uses container zero');
local first = view.inventory;
for index = 1, 99 do reader:observe(current, 2 + index / 100, only_inventory); end
eq(#data.reads, 1, 'Unchanged storage refreshes at most once a second');
reader:observe(current, 3, only_inventory);
eq(#data.reads, 2, 'A quiet fallback refresh stays responsive');
eq(view.inventory, first, 'Known bag tables are reused');
reader:observe(current, 3.1, both);
eq(view.satchel, nil, 'A layout change respects the read throttle');
reader:observe(current, 3.21, both);
eq(view.satchel.used, 12, 'Satchel uses its own occupied count');
eq(view.satchel.capacity, 50, 'Satchel does not assume eighty slots');
eq(view.satchel.free, 38, 'Satchel free slots are correct');
eq(data.reads[#data.reads], 5, 'Satchel uses container five');
reader:observe(nil, 3.22, nil);
eq(view.inventory, nil, 'Removing demand clears inventory immediately');
eq(view.satchel, nil, 'Removing demand clears Satchel immediately');
local disabled_reads = #data.reads;
reader:observe(nil, 20, {});
eq(#data.reads, disabled_reads, 'No player and no demand do no work');

reader, data, current = fixture();
local time = 0;
for _, invalid in ipairs({ -1, 81, 1.5, '2', false, math.huge, -math.huge, 0 / 0 }) do
    data.bags[0].used = invalid;
    reader:observe(current, time, only_inventory);
    eq(reader:view().inventory, nil, 'Invalid occupied count remains unknown');
    time = time + 1;
end
data.bags[0].used = 0;
for _, invalid in ipairs({ -1, 0, 81, 1.5, '80', false, math.huge, -math.huge, 0 / 0 }) do
    data.bags[0].capacity = invalid;
    reader:observe(current, time, only_inventory);
    eq(reader:view().inventory, nil, 'Invalid or unavailable capacity remains unknown');
    time = time + 1;
end
data.bags[0].used, data.bags[0].capacity = 31, 30;
reader:observe(current, time, only_inventory);
eq(reader:view().inventory, nil, 'Occupied slots cannot exceed capacity');
time = time + 1;
data.bags[0].used, data.bags[0].capacity = 0, 30;
reader:observe(current, time, only_inventory);
eq(reader:view().inventory.free, 30, 'A confirmed empty bag is valid');
time = time + 1;
data.bags[0].used = 30;
reader:observe(current, time, only_inventory);
eq(reader:view().inventory.free, 0, 'A confirmed full bag has zero free slots');
time = time + 1;
data.fail = true;
reader:observe(current, time, only_inventory);
eq(reader:view().inventory, nil, 'A failed getter clears the old value');
data.fail = false;
reader:observe(current, time + 1, only_inventory);
eq(reader:view().inventory.used, 30, 'A failed getter can recover');

reader, data, current = fixture(0);
reader:observe(current, 0, both);
eq(#data.reads, 0, 'Unloaded bags are never read as empty');
reader:packet(sync(32));
reader:observe(current, .21, both);
eq(reader:view().inventory, nil, 'Inventory waits for its own sync bit');
eq(reader:view().satchel.used, 12, 'Satchel can load before Inventory');
eq(#data.reads, 1, 'Only the ready selected bag is read');
reader:packet(sync(1));
eq(reader:view().satchel, nil, 'A lost sync bit clears its old value immediately');
reader:observe(current, .42, both);
eq(reader:view().inventory.used, 37, 'Inventory accepts its sync bit');
reader:packet(sync(0, 1));
reader:observe(current, .63, both);
eq(reader:view().satchel.used, 12, 'All-loaded state supports a complete normal sync');
data.bags[5].used = 17;
reader:packet(sync(33));
reader:observe(current, .84, both);
eq(reader:view().inventory.used, 37, 'Ordinary state-zero updates retain the cumulative Inventory bit');
eq(reader:view().satchel.used, 17, 'Ordinary state-zero updates retain the cumulative Satchel bit');

reader, data, current = fixture();
data.flags = '33';
reader:observe(current, 0, both);
eq(#data.reads, 0, 'Malformed native readiness does not imply an empty bag');
data.flags = 33;
reader:observe(current, 1, both);
eq(reader:view().satchel.used, 12, 'Late native readiness can recover without replayed packets');

reader, data, current = fixture();
reader:observe(current, 0, both);
reader:packet(zone(1001, 103));
eq(reader:view().inventory, nil, 'Zoning clears old counts immediately');
reader:observe(current, .3, both);
eq(#data.reads, 2, 'The previous zone snapshot cannot read the new zone');
current.zone = 103;
reader:observe(current, .4, both);
eq(#data.reads, 2, 'Old public flags cannot bypass a fresh zone sync');
reader:packet(sync(1));
reader:observe(current, .61, both);
eq(reader:view().inventory.used, 37, 'Fresh inventory packets restore the new zone');
eq(reader:view().satchel, nil, 'Satchel still waits for its new-zone data');
reader:packet(sync(33));
reader:observe(current, .82, both);
eq(reader:view().satchel.used, 12, 'Fresh Satchel packets restore its count');
reader:observe({ valid = false }, .9, both);
eq(reader:view().inventory, nil, 'A temporary invalid player clears counts');
reader:observe(current, 1.04, both);
eq(reader:view().inventory.used, 37, 'A short job-data gap recovers without another inventory sync');

reader:packet(packet(0x00B, 5, { { 4, 1, 1 } }));
reader:observe(current, 2, both);
eq(reader:view().inventory, nil, 'Logout cannot reuse memory from the last character');
reader:packet(zone(1002, 103));
reader:packet(sync(33));
reader:observe(current, 2.3, both);
eq(reader:view().inventory, nil, 'A new character waits for its matching player snapshot');
current.id, data.bags[0].used = 1002, 8;
reader:observe(current, 2.6, both);
eq(reader:view().inventory.used, 8, 'The new character gets its own counts');
current.id, data.bags[0].used = 1003, 19;
reader:observe(current, 3, both);
eq(reader:view().inventory, nil, 'A character change without a login packet does not trust old flags');
reader:packet(sync(33));
reader:observe(current, 3.3, both);
eq(reader:view().inventory.used, 19, 'A later sync recovers an identity change');
current.zone = 104;
reader:observe(current, 4, both);
eq(reader:view().inventory, nil, 'A zone change without a login packet waits for new data');
reader:packet(sync(33));
reader:observe(current, 4.3, both);
eq(reader:view().inventory.used, 19, 'A later sync recovers a zone change');

reader, data, current = fixture();
reader:observe(current, 0, only_inventory);
local ignored = {
    packet(0x01D, 11), sync(33, 2), packet(0x01C, 71), packet(0x01E, 9), packet(0x01F, 11), packet(0x020, 15),
    packet(0x01C, 72, { { 4, 1, 82 } }), packet(0x01E, 10, { { 8, 1, 8 } }),
};
for _, property in ipairs({ 'blocked', 'blocked_original', 'injected', 'is_injected' }) do
    local event = sync(0);
    event[property] = true;
    ignored[#ignored + 1] = event;
end
for _, event in ipairs(ignored) do reader:packet(event); end
reader:packet(nil);
reader:observe(current, .21, only_inventory);
eq(#data.reads, 1, 'Malformed, unrelated, blocked and injected updates do not force reads');
eq(reader:view().inventory.used, 37, 'Ignored packets cannot clear ready data');
for index = 1, 1000 do reader:packet(packet(0x01E, 10, { { 8, 1, 0 } })); end
reader:observe(current, .22, only_inventory);
eq(#data.reads, 2, 'A burst is coalesced into one selected-bag refresh');
for index = 1, 10 do
    reader:packet(packet(0x01F, 12, { { 10, 1, 0 } }));
    reader:observe(current, .22 + index / 100, only_inventory);
end
eq(#data.reads, 2, 'Repeated observed updates respect the five-Hz maximum');
reader:observe(current, .43, only_inventory);
eq(#data.reads, 3, 'The next due sample consumes the queued update');
data.bags[0].capacity = 75;
reader:packet(packet(0x01C, 72, { { 4, 1, 76 }, { 36, 2, 76 } }));
reader:observe(current, .64, only_inventory);
eq(reader:view().inventory.capacity, 75, 'Capacity changes refresh without an item scan');
reader:packet(packet(0x020, 16, { { 14, 1, 5 } }));
reader:observe(current, .85, only_inventory);
eq(data.reads[#data.reads], 0, 'A Satchel update never causes an unselected Satchel query');

reader, data, current = fixture();
data.changing = true;
reader:observe(current, 0, both);
eq(reader:view().inventory, nil, 'A changing native snapshot is not published');
eq(reader:view().satchel, nil, 'Both bags remain unknown during a torn update');
data.changing = false;
reader:observe(current, .21, both);
eq(reader:view().inventory.used, 37, 'A stable retry recovers the native snapshot');
reader:reset();
reader:observe(current, 1, both);
eq(reader:view().inventory, nil, 'Explicit reset discards readiness as well as counts');
reader:packet(sync(33));
reader:observe(current, 1.21, both);
eq(reader:view().inventory.used, 37, 'Explicit reset recovers after normal sync');
reader:observe(current, .1, both);
eq(reader:view().inventory.used, 37, 'A backward clock does not strand the reader');

local memory = AshitaCore.GetMemoryManager;
local native_reads, item_reads = {}, 0;
AshitaCore.GetMemoryManager = function()
    return { GetInventory = function()
        return {
            GetContainerUpdateFlags = function() return 33; end,
            GetContainerUpdateCounter = function() return 17; end,
            GetContainerCount = function(_, id) native_reads[#native_reads + 1] = id; return id == 0 and 32 or 9; end,
            GetContainerCountMax = function(_, id) return id == 0 and 60 or 40; end,
            GetContainerItem = function() item_reads = item_reads + 1; error('Slot scans are not needed'); end,
        };
    end };
end;
local native = storage.new();
native:observe({ valid = true, id = 1001, zone = 102 }, 0, only_inventory);
eq(native:view().inventory.used, 32, 'The default backend reads the public occupied-slot API');
eq(native:view().inventory.capacity, 60, 'The default backend uses public capacity without a wire-slot adjustment');
eq(native:view().inventory.free, 28, 'The default backend calculates free slots');
eq(#native_reads, 1, 'The default backend reads only a requested bag');
eq(native_reads[1], 0, 'The default backend reads Inventory zero');
native:observe({ valid = true, id = 1001, zone = 102 }, .21, both);
eq(native:view().satchel.capacity, 40, 'The default backend reads Satchel five when selected');
eq(native_reads[#native_reads], 5, 'The default backend uses the correct Satchel ID');
eq(item_reads, 0, 'Capacity tracking never scans item slots');
AshitaCore.GetMemoryManager = memory;

return { count = count };
