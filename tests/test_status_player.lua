local count = 0
local function equal(actual, expected, why)
    count = count + 1
    assert(actual == expected, (why or 'Mismatch') .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local stats = AshitaCore:GetMemoryManager():GetPlayer()
local utc = 1800000000
ashita.memory.find = function(_, _, pattern)
    return pattern == '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3' and 0x100 or 0
end
ashita.memory.read_uint32 = function(address)
    return ({ [0x100] = 0x200, [0x200] = 0x300, [0x30C] = utc })[address] or 0
end
-- The signature API returns the requested offset, so the fixture is the operand itself.
local player = require('core.player')
player.load()
equal(player.utc(), utc)
MOCK.player.buffs = { 269, 249, 251 }
local sample = player.read()
equal(sample.sync_active, true)
equal(sample.dedication, true)
equal(sample.food, true)
equal(sample.food_seconds, nil, 'No timer invented from buffs')
local icons = { [0] = 269, [1] = 249, [2] = 251 }
local ticks = (utc - 1009810800) * 60
local timers = { [1] = (ticks + 600 * 60) % 4294967296, [2] = (ticks + 1800 * 60) % 4294967296 }
stats.GetStatusIcons = function() return icons end
stats.GetStatusTimers = function() return timers end
sample = player.read()
equal(sample.dedication_seconds, 600)
equal(sample.food_seconds, 1800)
timers[2] = 0x7FFFFFFF
equal(player.read().food_seconds, nil, 'Unknown timer sentinel')
timers[2] = 0
equal(player.read().food_seconds, nil, 'Missing timer')
icons[0], icons[1], icons[2] = 255, 255, 255
sample = player.read()
equal(sample.sync_active, false)
equal(sample.food, false)
equal(sample.dedication, false)
local get_job = stats.GetMainJob
stats.GetMainJob = function() return 23 end
equal(player.read().valid, false, 'Monster jobs do not use the normal EXP curve')
equal(player.read().unsupported_job, true)
stats.GetMainJob = get_job
MOCK.zoning = true
equal(player.read().valid, false)
MOCK.zoning = false
local find = ashita.memory.find
local scans = 0
ashita.memory.find = function(...)
    scans = scans + 1
    return find(...)
end
local worker = coroutine.create(function() player.load(coroutine.yield) end)
while coroutine.status(worker) ~= 'dead' do
    local before = scans
    local ok, problem = coroutine.resume(worker)
    equal(ok, true, problem or 'Cooperative player scan completes')
    equal(scans - before <= 1, true, 'A resumed player scan finds at most one signature')
end
equal(scans, 4, 'Cooperative startup keeps all four player signatures')
equal(player.utc(), utc, 'Cooperative startup preserves the current UTC pointer')
scans = 0
player.load_clock()
equal(scans, 1, 'The server clock can be loaded before the session baseline with one signature')
equal(player.utc(), utc, 'An early clock load preserves the current server time')
worker = coroutine.create(function() player.load(coroutine.yield, true) end)
while coroutine.status(worker) ~= 'dead' do
    local before = scans
    local ok, problem = coroutine.resume(worker)
    equal(ok, true, problem or 'Remaining player scans complete')
    equal(scans - before <= 1, true, 'Remaining player searches still yield one at a time')
end
equal(scans, 4, 'A loaded clock is not searched for again during the remaining three scans')
equal(player.utc(), utc, 'Remaining player searches keep the seeded server clock')
scans = 0
ashita.memory.find = function() scans = scans + 1; return 0 end
worker = coroutine.create(function() player.load(coroutine.yield) end)
while coroutine.status(worker) ~= 'dead' do
    local before = scans
    local ok, problem = coroutine.resume(worker)
    equal(ok, true, problem or 'Missing signatures stay supported')
    equal(scans - before <= 1, true, 'Missing player signatures still yield individually')
end
equal(scans, 4, 'Missing player signatures are attempted once each')
equal(player.utc(), nil, 'Missing UTC stays unknown')
scans = 0
ashita.memory.find = function() scans = scans + 1; error('Test player scan failure') end
worker = coroutine.create(function() player.load(coroutine.yield) end)
equal(coroutine.resume(worker), true, 'A failed scan yields after its native call returns')
equal(scans, 1, 'A failed native call uses one scan step')
local ok, problem = coroutine.resume(worker)
equal(ok, false, 'Player scan errors still reach the startup handler')
equal(type(problem) == 'string' and problem:find('Test player scan failure', 1, true) ~= nil, true, 'Player scan errors keep their message')
equal(scans, 1, 'Resuming a failed scan never retries it')
equal(pcall(player.load), false, 'Synchronous player load still reports scan errors')
ashita.memory.find = find
player.load()
equal(player.utc(), utc, 'Synchronous loading remains available after a cooperative scan')
return { count = count }
