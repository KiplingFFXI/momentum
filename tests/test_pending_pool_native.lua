local Farming = require('core.farming');
local FarmingClient = require('core.farming_client');
local Events = require('core.events');
local EventClient = require('core.events_client');
local Dynamis = require('core.dynamis');
local DynamisClient = require('core.dynamis_client');
local settings = require('ui.defaults').make();
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end

-- SDK treasureitem_t exposes ItemId; ordinary item_t instead exposes Id.
-- Reject an unsupported property as the native binding can, rather than hiding
-- a bad field name behind table-only fixtures.
local function native(fields, known)
    local value = newproxy(true);
    getmetatable(value).__index = function(_, key)
        if not known[key] then error('Unknown native member: ' .. tostring(key)); end
        return fields[key];
    end;
    return value;
end
local treasure_fields = { Use = true, ItemId = true, Count = true };
local pool = {
    [0] = native({ Use = 1, ItemId = 1455, Count = 2 }, treasure_fields),
    [1] = native({ Use = 0, ItemId = 0, Count = 0 }, treasure_fields),
};
local reads = 0;
local inventory = {
    GetTreasurePoolItem = function(_, slot) reads = reads + 1; return pool[slot]; end,
    GetContainerCountMax = function() return 0; end,
};
local memory = { GetInventory = function() return inventory; end, GetPlayer = function() return {}; end };
local old_memory = AshitaCore.GetMemoryManager;
AshitaCore.GetMemoryManager = function() return memory; end;
local id, now, utc = 1001, 10, 1800000000;
local packet_fields = { id = true, size = true, data = true, data_raw = true, blocked = true, injected = true };
local function award(slot, winner, sequence)
    -- Phoenix 0x0D3: recipient server ID at 0x04, pool slot at 0x14,
    -- result 1 (personal award) at 0x15. Header sequence distinguishes packets.
    local bytes = MOCK.bytes(24);
    MOCK.put(bytes, 2, 2, sequence or 1);
    MOCK.put(bytes, 4, 4, winner or id);
    MOCK.put(bytes, 20, 1, slot or 0);
    MOCK.put(bytes, 21, 1, 1);
    return native(MOCK.packet(0x0D3, bytes), packet_fields);
end
local function old_drop(slot, quantity)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 2, 2, 10);
    MOCK.put(bytes, 4, 4, quantity);
    MOCK.put(bytes, 16, 2, 1455);
    MOCK.put(bytes, 20, 1, slot);
    MOCK.put(bytes, 21, 1, 1);
    return native(MOCK.packet(0x0D2, bytes), packet_fields);
end

local farming, farm_client = Farming.new(), FarmingClient.new();
farming:observe(true, now);
farm_client:observe({ valid = true, id = id, zone = 102 });
eq(farm_client.pool[0].id, 1455, 'Farming seeds the documented native ItemId');
eq(farm_client.pool[1], nil, 'Empty native treasure is ignored');
eq(farming:view(now).pool_found, 0, 'Loading does not invent a newly found drop');
local win = award();
farm_client:packet(win, now + 1, farming);
farm_client:packet(win, now + 1, farming);
eq(farming:view(now + 1).total, 2, 'Pending personal receipt counts exactly once');
farm_client:packet(old_drop(0, 2), now + 2, farming);
farm_client:packet(award(0, id, 2), now + 2, farming);
eq(farming:view(now + 2).total, 2, 'Old pool resend cannot replay a seeded receipt');
local before = reads;
farm_client:observe({ valid = true, id = id, zone = 102 });
eq(reads, before, 'Steady samples retain the bounded one-time pool snapshot');

local rules = require('data.event_rules');
local zone, battle;
for candidate, area in pairs(rules.areas) do
    for index, info in pairs(area.battles or {}) do
        if info.kind == 'limbus' then zone, battle = candidate, index; break; end
    end
    if zone then break; end
end
assert(zone, 'Source-backed Limbus fixture');
local event_core = Events.new();
local event_client = EventClient.new(event_core, { memory = memory, utc = function() return utc; end });
event_client:context(id, zone, now, settings, true);
event_core:begin(zone, battle, now, utc, false);
event_client:seed_pool(now);
eq(event_core.pool[0].item_id, 1455, 'Event reader seeds native treasure');
eq(#event_core:view(now, utc, settings).drops, 0, 'Event seed is not a fresh found drop');
win = award();
event_client:packet(win, now + 1, settings);
event_client:packet(win, now + 1, settings);
local event_view = event_core:view(now + 1, utc, settings);
eq(#event_view.received, 1, 'Event personal receipt is recorded once');
eq(event_view.received[1].count, 2, 'Event receipt preserves pending quantity');
eq(#event_view.drops, 0, 'Receiving a seeded item does not invent a found total');

local dyna_core = Dynamis.new();
dyna_core:context(id, 185, now, utc);
dyna_core:hourglass({ zone = 185, start_time = utc, end_time = utc + 3600 }, now, utc);
local dyna_client = DynamisClient.new(dyna_core, { memory = memory, utc = function() return utc; end });
dyna_client:context(id, 185, now, settings);
dyna_client:seed_pool(now);
eq(dyna_core.pool[0].item_id, 1455, 'Dynamis reader seeds native treasure');
eq(dyna_core:view(now, utc, settings).currency_found, 0, 'Dynamis seed is not fresh currency');
win = award();
dyna_client:packet(win, now + 1, settings);
dyna_client:packet(win, now + 1, settings);
local dyna_view = dyna_core:view(now + 1, utc, settings);
eq(dyna_view.currency_received, 2, 'Pending Dynamis currency receipt counts once');
eq(dyna_view.currency_found, 0, 'Pending receipt leaves found currency unchanged');

-- A fresh observer, as after a reload, can hydrate the still-pending pool.
local reloaded, reload_client = Farming.new(), FarmingClient.new();
reloaded:observe(true, now);
reload_client:observe({ valid = true, id = id, zone = 102 });
reload_client:packet(award(0, id, 3), now + 3, reloaded);
eq(reloaded:view(now + 3).total, 2, 'Reload snapshot remains usable for a later award');
reload_client:observe({ valid = true, id = id + 1, zone = 102 });
reload_client:packet(award(0, id, 4), now + 4, reloaded);
eq(reloaded:view(now + 4).total, 2, 'Previous character cannot receive under the next identity');
AshitaCore.GetMemoryManager = old_memory;
return { count = count };
