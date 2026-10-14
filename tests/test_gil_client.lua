local count = 0
local function equal(actual, expected, why)
    count = count + 1
    assert(actual == expected, why .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local packets = require('core.packets')
local function balance(id, amount, bag, slot, item)
    local bytes = MOCK.bytes(20)
    MOCK.put(bytes, 4, 4, amount)
    if id == 0x01E then
        MOCK.put(bytes, 8, 1, bag or 0); MOCK.put(bytes, 9, 1, slot or 0)
    elseif id == 0x01F then
        MOCK.put(bytes, 8, 2, item or 65535)
        MOCK.put(bytes, 10, 1, bag or 0); MOCK.put(bytes, 11, 1, slot or 0)
    else
        MOCK.put(bytes, 12, 2, item or 65535)
        MOCK.put(bytes, 14, 1, bag or 0); MOCK.put(bytes, 15, 1, slot or 0)
    end
    return MOCK.packet(id, bytes)
end
local function sync(state, flags)
    local bytes = MOCK.bytes(12)
    MOCK.put(bytes, 4, 1, state); MOCK.put(bytes, 8, 4, flags)
    return MOCK.packet(0x01D, bytes)
end
for _, id in ipairs({ 0x01E, 0x01F, 0x020 }) do
    equal(packets.inventory(balance(id, 0)).balance, 0, 'Zero balance is known')
    equal(packets.inventory(balance(id, 999999999)).balance, 999999999, 'Phoenix cap')
    equal(packets.inventory(balance(id, 1000000000)), nil, 'Reject above cap')
    equal(packets.inventory(balance(id, 50, 1)), nil, 'Reject other containers')
    equal(packets.inventory(balance(id, 50, 0, 1)), nil, 'Reject other slots')
    local event = balance(id, 100); event.blocked = true
    equal(packets.inventory(event), nil, 'Ignore blocked packet')
    event = balance(id, 100); event.injected = true
    equal(packets.inventory(event), nil, 'Ignore injected packet')
    event = balance(id, 100); event.data = event.data:sub(1, 8)
    equal(packets.inventory(event), nil, 'Reject truncated packet')
end
equal(packets.inventory(balance(0x01F, 50, 0, 0, 1)), nil, 'Require gil item')
equal(packets.inventory(balance(0x020, 50)).baseline, true, 'Full inventory establishes baseline')
equal(packets.inventory(sync(0, 0)).ready, false, 'Inventory loading')
equal(packets.inventory(sync(0, 1)).ready, true, 'Inventory bag loaded')
equal(packets.inventory(sync(1, 0)).ready, true, 'All inventory loaded')
equal(packets.inventory(sync(2, 1)), nil, 'Reject unknown state')

local memory, reads, stored = AshitaCore:GetMemoryManager(), 0, { Id = 65535, Count = 1000 }
AshitaCore.GetMemoryManager = function() return memory end
memory.GetInventory = function() return { GetContainerItem = function(_, bag, slot)
    equal(bag, 0, 'Read inventory only'); equal(slot, 0, 'Read gil slot only')
    reads = reads + 1; return stored
end } end
local player = require('core.player')
equal(player.read().gil_current, 1000, 'Memory seeds current gil')
for _ = 1, 10 do player.read() end
equal(reads, 1, 'Known balance avoids repeat inventory reads')
player.inventory(packets.inventory(balance(0x01E, 1200)))
equal(player.read().gil_current, 1200, 'Packet wins over stale memory')
MOCK.player.exp_needed = 0
equal(player.read().valid, false, 'Job stats can be temporarily incomplete')
player.inventory(packets.inventory(balance(0x01E, 1300)))
MOCK.player.exp_needed = 7800
player.on_status()
equal(player.read().gil_current, 1300, 'A job stats gap does not require an inventory reload')
player.on_zone(MOCK.player.server_id)
player.on_status()
equal(player.read().gil_current, nil, 'Old inventory hidden while zoning')
player.inventory(packets.inventory(balance(0x020, 700)))
equal(player.read().gil_current, nil, 'Pending full inventory stays unknown')
player.inventory(packets.inventory(sync(0, 1)))
equal(player.read().gil_current, 700, 'New full inventory becomes baseline when ready')
MOCK.login_status = 0
equal(player.read().gil_current, nil, 'Logout clears balance')
player.inventory(packets.inventory(balance(0x020, 800)))
player.inventory(packets.inventory(sync(1, 1)))
player.read()
MOCK.login_status = 2
equal(player.read().gil_current, 800, 'Loading frames keep the new inventory stream')
player.inventory({ ready = false }); player.inventory({ ready = true })
stored = { Id = 1, Count = 500 }
equal(player.read().gil_current, nil, 'Reject wrong memory item')
stored = { Id = 65535, Count = 0 }
equal(player.read().gil_current, 0, 'Zero memory balance remains available')
return { count = count }
