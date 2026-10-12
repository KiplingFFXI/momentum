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
return { count = count }
