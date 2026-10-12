local rings = require('core.rings')
local rules = require('data.phoenix_rules')
local count = 0
local function equal(actual, expected, why)
    count = count + 1
    assert(actual == expected, (why or 'Mismatch') .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function item(charges, use, equip, flags)
    local bytes = MOCK.bytes(24)
    MOCK.put(bytes, 0, 1, 1); MOCK.put(bytes, 1, 1, charges); MOCK.put(bytes, 3, 1, flags or 0x90)
    MOCK.put(bytes, 4, 4, use or 0); MOCK.put(bytes, 8, 4, equip or 0)
    local event = MOCK.packet(0, bytes)
    return { Id = 15762, Count = 1, Flags = 5, Extra = event.data }
end
local now = 1800000000
local raw = now - 1009810800
equal(rules.rings[15762].recast_delay, 57600, 'Phoenix overlay')
equal(rules.rings[15762].use_delay, 15, 'Phoenix equip delay')
equal(rules.rings[15793].max_charges, 10)
local entry = rings.decode(item(6, raw + 60, raw + 15), 0, 7, now)
equal(entry.key, '0:7:15762'); equal(entry.charges, 6)
equal(entry.recast, 60); equal(entry.equip_delay, 15); equal(entry.ready, false)
equal(entry.cap, 1000); equal(entry.bonus, 50); equal(entry.duration, 10800)
entry = rings.decode(item(6, raw - 1), 0, 7, now)
equal(entry.recast, 0); equal(entry.ready, true)
entry = rings.decode(item(0, raw + 60), 0, 7, now)
equal(entry.charges, 0); equal(entry.ready, false)
entry = rings.decode(item(7, 0, 0, 0xC0), 0, 7, nil)
equal(entry.ready, true, 'Server ready flag needs no invented clock')
entry = rings.decode(item(6, raw + 60), 0, 7, nil)
equal(entry.charges, 6); equal(entry.recast, nil); equal(entry.ready, nil)
entry = rings.decode(item(8, raw + 60), 0, 7, now)
equal(entry.charges, nil, 'Invalid charges')
for size = 0, 11 do
    local value = item(6, raw + 60); value.Extra = value.Extra:sub(1, size)
    equal(rings.decode(value, 0, 7, now).charges, nil, 'Short extra data')
end
equal(rings.decode({ Id = 1, Count = 1 }, 0, 1, now), nil)
equal(rings.decode({ Id = 15762, Count = 0 }, 0, 1, now), nil)
local inventory = { GetContainerCountMax = function(_, bag) return bag == 0 and 2 or 0 end,
    GetContainerItem = function(_, _, slot) return slot == 2 and item(6, raw + 60) or nil end }
local found = rings.read(now, inventory)
equal(found.available, true); equal(#found.entries, 1); equal(found.entries[1].slot, 2)
equal(rings.read(now).available, false, 'Missing API is unknown')
equal(rings.read(now, {}).available, false, 'Unavailable container API is not an empty ring inventory')
equal(rings.read(now, { GetContainerCountMax = function() error('not loaded') end }).available, false, 'Failed container reads remain unavailable')
equal(rings.read(now, { GetContainerCountMax = function() return 0 end }).available, true, 'Valid empty containers are still readable')
local reads = 0
found = rings.read(now, { GetContainerCountMax = function() return 0.5 end,
    GetContainerItem = function() reads = reads + 1 end })
equal(found.available, false, 'Fractional container capacity is invalid')
equal(reads, 0, 'Invalid capacity never scans slots')
local failed_slots = { GetContainerCountMax = function(_, bag) return bag == 0 and 2 or 0 end,
    GetContainerItem = function() error('slot unavailable') end }
found = rings.read(now, failed_slots)
equal(found.available, false, 'Readable capacity cannot prove no rings when slot reads fail')
equal(found.incomplete, true, 'Failed slots mark the scan incomplete')
equal(#found.entries, 0)
failed_slots.GetContainerItem = function(_, _, slot)
    if slot == 1 then error('slot unavailable') end
end
found = rings.read(now, failed_slots)
equal(found.available, false, 'A readable empty slot cannot rule out rings in failed slots')
equal(found.incomplete, true)
failed_slots.GetContainerItem = function(_, _, slot)
    if slot == 1 then error('slot unavailable') end
    return item(6, raw + 60)
end
found = rings.read(now, failed_slots)
equal(found.available, true, 'Confirmed rings remain available during a partial scan')
equal(found.incomplete, true)
equal(#found.entries, 1)
equal(found.entries[1].slot, 2)
failed_slots.GetContainerItem = function() return nil end
found = rings.read(now, failed_slots)
equal(found.available, true, 'A fully readable empty scan is known')
equal(found.incomplete, nil, 'Recovered scans clear the incomplete state')
return { count = count }
