local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function near(actual, expected, label)
    checks = checks + 1
    assert(actual and math.abs(actual - expected) < 0.0001, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function packet(id, bytes) MOCK.fire('packet_in', MOCK.packet(id, bytes)) end
local function loot(item, slot, count)
    local found = MOCK.bytes(28)
    MOCK.put(found, 4, 4, count or 1)
    MOCK.put(found, 16, 2, item)
    MOCK.put(found, 20, 1, slot or 0)
    MOCK.put(found, 24, 4, math.floor(MOCK.now * 1000))
    packet(0x0D2, found)
    local won = MOCK.bytes(24)
    MOCK.put(won, 4, 4, MOCK.player.server_id)
    MOCK.put(won, 20, 1, slot or 0)
    MOCK.put(won, 21, 1, 1)
    packet(0x0D3, won)
end
local function mob_gil(amount)
    local bytes = MOCK.bytes(28)
    MOCK.put(bytes, 4, 4, MOCK.player.server_id)
    MOCK.put(bytes, 8, 4, MOCK.player.server_id)
    MOCK.put(bytes, 12, 4, amount)
    MOCK.put(bytes, 24, 2, 565)
    packet(0x029, bytes)
end
MOCK.load_addon()
local app = MOMENTUM_TEST
loot(100, 0, 2)
equal(app.view(MOCK.now).farming.total, 2, 'Initial loot belongs to the active job session')
MOCK.frame(10)
local elapsed = app.view(MOCK.now).farming.elapsed
near(elapsed, 10, 'Farming clock advances before zoning')
packet(0x00B, MOCK.bytes(8))
MOCK.now = MOCK.now + 60
near(app.view(MOCK.now).farming.elapsed, elapsed, 'A zone-leave packet stops time even without intermediate render callbacks')
MOCK.player.zone = 103
local entered = MOCK.bytes(140)
MOCK.put(entered, 4, 4, MOCK.player.server_id)
MOCK.put(entered, 48, 2, MOCK.player.zone)
MOCK.put(entered, 56, 4, os.time())
packet(0x00A, entered)
packet(0x061, MOCK.bytes(96))
loot(101, 1)
equal(app.view(MOCK.now).farming.total, 3, 'Loot after the new zone uses the preserved session')
near(app.view(MOCK.now).farming.elapsed, elapsed, 'The unavailable zone interval is excluded on return')
MOCK.frame(1)
near(app.view(MOCK.now).farming.elapsed, elapsed + 1, 'The clock resumes once the new character state is available')
local first_job = MOCK.player.main_job
MOCK.player.main_job = 2
packet(0x061, MOCK.bytes(96))
loot(102, 2, 4)
mob_gil(77)
equal(app.tracker().identity.job, 2, 'Farming packets select the new job before the next UI frame')
equal(app.view(MOCK.now).farming.total, 4, 'Immediate new-job loot cannot enter the previous job session')
equal(app.view(MOCK.now).farming.mob_gil, 77, 'Immediate new-job monster gil belongs to the new job')
local previous
for _, row in ipairs(app.sessions:history(MOCK.player.server_id)) do
    if row.job == first_job then previous = row end
end
equal(previous ~= nil, true, 'The previous job session remains archived')
equal(previous.farming.total, 3, 'The previous job keeps only its own loot')
equal(previous.farming.mob_gil, 0, 'The previous job did not receive the new job gil')
MOCK.player.main_job = first_job
packet(0x061, MOCK.bytes(96))
loot(103, 3)
equal(app.tracker().identity.job, first_job, 'Returning job packets restore that job without waiting for rendering')
equal(app.view(MOCK.now).farming.total, 4, 'Returning job resumes its own saved item totals')
equal(app.view(MOCK.now).farming.mob_gil, 0, 'Returning job never imports another job\'s gil')
equal(app.state.broken, false, 'Lifecycle transitions leave rendering healthy')
equal(#MOCK.commands, 0, 'Lifecycle handling sends no gameplay commands')
MOCK.fire('unload')
return { count = checks }
