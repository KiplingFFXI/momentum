local client = require('core.dynamis_client');
local core = require('core.dynamis');
local rules = require('data.dynamis_rules');
local defaults = require('ui.defaults');
local count = 0;
local function eq(a, b, label) count = count + 1; assert(a == b, label .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); end
local utc, zone, id = 1800000000, 185, 1001;
assert(rules.zones[zone]);
local function bytes(size, fields)
    local data = MOCK.bytes(size);
    for _, field in ipairs(fields or {}) do MOCK.put(data, field[1], field[2], field[3]); end
    return data;
end
local extra = MOCK.packet(0, bytes(24, { { 2, 1, 1 }, { 8, 4, utc + 3600 }, { 12, 4, utc }, { 16, 2, zone } })).data;
eq(client.glass(4237, 1, extra).end_time, utc + 3600, 'Hourglass UTC');
eq(client.glass(4237, 0, extra), nil, 'Empty slot stale extra ignored');
eq(client.glass(1, 1, extra), nil, 'Other item ignored');
eq(client.glass(4237, 1, extra:sub(1, 23)), nil, 'Truncated extra ignored');
local inventory_reads, pool_reads = 0, 0;
local inventory = {
    GetContainerCountMax = function(_, bag) return bag == 0 and 10 or 0; end,
    GetContainerItem = function(_, bag, slot)
        inventory_reads = inventory_reads + 1;
        if bag == 0 and slot == 1 then return { Id = 4237, Count = 1, Extra = extra }; end
    end,
    GetTreasurePoolItem = function(_, slot)
        pool_reads = pool_reads + 1;
        if slot == 0 then return { Id = 1455, Count = 1, DropTime = 55 }; end
    end,
};
local stats = { GetBuffs = function() return { [0] = 157 }; end, HasKeyItem = function() return false; end };
local memory = { GetInventory = function() return inventory; end, GetPlayer = function() return stats; end };
local tracker = core.new();
local observer = client.new(tracker, { memory = memory, clock = function() return utc; end });
local settings = defaults.make();
local snapshot = { valid = true, id = id, zone = zone };
observer:sample(snapshot, 0, settings);
local view = tracker:view(0, utc, settings);
eq(view.remaining, 3600, 'Initial inventory timer');
eq(view.currency_found, 0, 'Existing pool not counted as fresh');
eq(view.pool_count, 1, 'Existing pool seeded');
eq(view.subjob_locked, true, 'Restriction from actual effect');
local initial = inventory_reads;
for i = 1, 120 do observer:sample(snapshot, i / 60, settings); end
eq(inventory_reads, initial, 'Stable frames do not rescan inventory');
eq(pool_reads, 10, 'Pool seeded once');
local zone_packet = MOCK.packet(0x00A, bytes(60, { { 4, 4, id }, { 48, 2, zone }, { 56, 4, utc } }));
observer:packet(zone_packet, 5, settings);
eq(observer:utc(15), utc + 10, 'Server UTC advances monotonically');
eq(observer.clock_estimated, false, 'Packet UTC confirmed');
local drop = MOCK.packet(0x0D2, bytes(28, { { 2, 2, 10 }, { 4, 4, 1 }, { 16, 2, 1456 }, { 20, 1, 1 }, { 24, 4, 66 } }));
observer:packet(drop, 15, settings);
observer:packet(drop, 15, settings);
eq(tracker:view(15, utc + 10, settings).currency_found, 100, 'Duplicate packet counted once');
local lot = MOCK.packet(0x0D3, bytes(24, { { 4, 4, id }, { 20, 1, 1 }, { 21, 1, 1 } }));
observer:packet(lot, 16, settings);
eq(tracker:view(16, utc + 11, settings).currency_received, 100, 'Personal win counted');
local extension = MOCK.packet(0x02A, bytes(28, { { 4, 4, id }, { 8, 4, 10 }, { 12, 4, 1 }, { 26, 2, rules.zones[zone].extension_message } }));
observer:packet(extension, 17, settings);
observer:packet(extension, 17, settings);
view = tracker:view(17, utc + 12, settings);
eq(view.extension_minutes, 10, 'Extension ledger deduplicated');
eq(view.remaining, 3588, 'Announcement cannot double-add authoritative time');
for _, packet_id in ipairs({ 0x00A, 0x020, 0x0D2, 0x0D3, 0x029, 0x02A, 0x00E }) do
    eq(client.parse(MOCK.packet(packet_id, bytes(4))), nil, 'Truncated packet rejected');
end
drop.injected = true;
eq(client.parse(drop), nil, 'Injected packet ignored');
local corpse = MOCK.packet(0x00E, bytes(36, { { 10, 1, 36 }, { 30, 1, 100 } }));
eq(client.parse(corpse), nil, 'Despawn not a new life');
settings.dynamis.enabled = false;
observer:sample(snapshot, 20, settings);
eq(tracker:view(20, utc + 15, settings).active, false, 'Disabled tracking closes active view');
return { count = count };
