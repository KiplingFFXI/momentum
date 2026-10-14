local count = 0
local function equal(actual, expected, why)
    count = count + 1
    assert(actual == expected, why .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local memory, reads = AshitaCore:GetMemoryManager(), 0
AshitaCore.GetMemoryManager = function() return memory end
memory.GetInventory = function() return { GetContainerItem = function()
    reads = reads + 1; return { Id = 65535, Count = 1000 }
end } end
local function money(value, id)
    id = id or 0x01E
    local bytes = MOCK.bytes(20)
    MOCK.put(bytes, 4, 4, value)
    if id == 0x020 then MOCK.put(bytes, 12, 2, 65535) end
    MOCK.fire('packet_in', MOCK.packet(id, bytes))
end
local function sync(ready)
    local bytes = MOCK.bytes(12)
    MOCK.put(bytes, 4, 1, ready and 1 or 0)
    MOCK.put(bytes, 8, 4, ready and 1 or 0)
    MOCK.fire('packet_in', MOCK.packet(0x01D, bytes))
end
MOCK.load_addon(); MOCK.frame(0)
local app = MOMENTUM_TEST
local function wallet() return app.tracker():view(MOCK.now, app.settings()).gil end
equal(wallet().current, 1000, 'Load seeds gil')
equal(wallet().gained, 0, 'Loaded balance is not income')
money(1200); money(1100)
equal(wallet().gained, 200, 'Same-frame received gil counted')
equal(wallet().spent, 100, 'Same-frame spent gil counted')
equal(wallet().net, 100, 'Net change after spending')
equal(app.tracker().started, nil, 'Gil does not start EXP clock')
money(1100)
MOCK.frame(0.25)
equal(wallet().current, 1100, 'Stale inventory memory cannot undo packet changes')
equal(wallet().spent, 100, 'Repeated snapshot does not double count')
equal(reads, 1, 'Gil needs only one native slot read')
MOCK.now = MOCK.now + 61
equal(wallet().rate ~= nil, true, 'Gil has independent rate')
MOCK.fire('command', { command = '/momentum pause' })
money(900)
equal(wallet().current, 900, 'Pause keeps current balance live')
equal(wallet().spent, 100, 'Pause does not count spending')
MOCK.fire('command', { command = '/momentum resume' })
money(950)
equal(wallet().gained, 250, 'Resume compares with last paused balance')
MOCK.fire('command', { command = '/momentum reset' })
equal(wallet().current, 950, 'Reset keeps current gil')
equal(wallet().gained, 0, 'Reset clears gains')
equal(wallet().spent, 0, 'Reset clears spending')
equal(wallet().rate, nil, 'Reset clears rate')
sync(false)
equal(wallet().current, nil, 'Inventory reload suspends wallet')
money(50000, 0x020)
equal(wallet().current, nil, 'Loading balance stays pending')
sync(true)
equal(wallet().current, 50000, 'Completed inventory provides fresh baseline')
equal(wallet().gained, 0, 'Inventory reload does not invent income')
money(49900)
equal(wallet().spent, 100, 'Normal tracking resumes after inventory reload')
MOCK.frame(0.25)
MOCK.player.exp_needed = 0; MOCK.frame(0.25)
equal(wallet().current, nil, 'Temporary job stats gap suspends the session baseline')
MOCK.player.exp_needed = 7800; MOCK.frame(0.25)
equal(wallet().current, 49900, 'Job stats recover without an inventory sync')
money(49850)
equal(wallet().spent, 150, 'Gil changes still count after the job stats gap')
MOCK.zoning = true
money(99900)
equal(wallet().gained, 0, 'Zoning cannot count a packet for a stale character')
MOCK.frame(0.25)
equal(wallet().current, nil, 'Zoning clears old live balance')
MOCK.zoning = false
MOCK.player.server_id = 2002
money(70000, 0x020); sync(true); MOCK.frame(0.25)
equal(wallet().current, 70000, 'New character baseline')
equal(wallet().gained, 0, 'New character cannot inherit gains')
equal(wallet().spent, 0, 'New character cannot inherit spending')
return { count = count }
