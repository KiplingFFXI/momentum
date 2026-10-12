local count = 0
local function equal(actual, expected, why)
    count = count + 1
    assert(actual == expected, (why or 'Mismatch') .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local overrides, commands, timers, messages, chain_messages = {}, {}, {}, {}, {}
local now, calls = 1800000000, 0
local vars, local_vars, effects = {}, {}, {}
local native_chain = { known = true, count = 3, server_now_ms = 123456789, deadline_ms = 123600000 }
GetMomentumChain = function() return native_chain end
xi = { objType = { PC = 1 }, effect = { LEVEL_SYNC = 269, DEDICATION = 249 },
    msg = { channel = { SYSTEM_3 = 29 } }, module = {}, job = { MON = 23 } }
function xi.module.registerCommand(name, command) commands[name] = command end
Module = { new = function() return { addOverride = function(_, path, fn) overrides[path] = fn end } end }
package.preload['modules/module_utils'] = function() return {} end
GetSystemTime = function() return math.floor(now) end
GetServerVariable = function(name) equal(name, '[SyncPenalty]RatePerLevel'); return 15 end
local player = {}
function player:getObjType() return 1 end
function player:getID() return 1001 end
function player:getZoneID() return 102 end
function player:getMainJob() return 1 end
function player:getJobLevel() return 75 end
function player:getMainLvl() return 50 end
function player:getCharVar(key) return vars[key] or 0 end
function player:setCharVar(key, value) equal(key, '[Momentum]Status', 'Only telemetry preference'); vars[key] = value end
function player:getLocalVar(key) return local_vars[key] or 0 end
function player:setLocalVar(key, value)
    equal(key:sub(1, 10), '[Momentum]', 'Only telemetry metadata')
    assert(value >= 0 and value <= 4294967295, 'Local vars must fit server uint32')
    local_vars[key] = value
end
function player:hasStatusEffect(id) return effects[id] ~= nil end
function player:getStatusEffect(id) return effects[id] end
function player:timer(delay, callback) timers[#timers + 1] = { due = now + delay / 1000, callback = callback } end
function player:printToPlayer(text, channel, sender)
    equal(channel, 29); assert(#text <= 150, 'Message must fit packet')
    local target = text:sub(1, 6) == 'MOMC1|' and chain_messages or messages
    target[#target + 1] = { text = text, sender = sender }
end
local function advance(seconds)
    now = now + seconds
    local pending = timers; timers = {}
    for _, timer in ipairs(pending) do
        if timer.due <= now then timer.callback(player) else timers[#timers + 1] = timer end
    end
end
local function invoke(name, ...)
    local result = { exp = 123 }
    super = function() calls = calls + 1; return result end
    local before = calls
    local value = overrides[name](player, ...)
    equal(calls, before + 1, 'Exactly one super call: ' .. name)
    if name == 'xi.experiencePoints.calculate' then equal(value, result, 'Original calculation result preserved') end
end
local function decode(message)
    local bytes = MOCK.bytes(24 + #message.text)
    MOCK.put(bytes, 4, 1, 29)
    MOCK.put(bytes, 6, 2, 102)
    for i = 1, #message.sender do bytes[7 + i] = message.sender:byte(i) end
    for i = 1, #message.text do bytes[22 + i] = message.text:byte(i) end
    return require('core.packets').status(MOCK.packet(0x017, bytes), 1001)
end
assert(loadfile(ADDON_DIR .. '/../server/momentum_status.lua'))()
equal(commands.momentumstatus.cmdprops.permission, 0)
invoke('xi.player.onGameIn', false, false)
equal(#messages, 0, 'No unsolicited protocol')
equal(#chain_messages, 0, 'No unsolicited chain protocol')
equal(#timers, 0, 'No timer without opt in')
effects[269] = {}; local_vars['[SyncPenalty]Amount'] = 37
effects[249] = { getSubPower = function() return 700 end, getPower = function() return 50 end,
    getTimeRemaining = function() return 599001 end }
commands.momentumstatus.onTrigger(player, 'on')
equal(vars['[Momentum]Status'], 1)
equal(#timers, 1)
local protocol = messages[1]
equal(protocol.sender, 'Momentum')
assert(protocol.text:match('^MOM1|1001|102|1|75|50|1800000000000|1800000000|1|37|15|1|700|50|600|1$'), protocol.text)
count = count + 1
local decoded = assert(decode(protocol), 'Published Lua number fields must decode')
equal(decoded.sequence, 1800000000000, 'Large sequence round trip')
equal(decoded.utc, now)
equal(decoded.sync_penalty, 37)
equal(decoded.dedication_pool, 700)
equal(decoded.dedication_seconds, 600, 'Binding milliseconds become whole seconds')
equal(decoded.enabled, true)
equal(chain_messages[1].sender, 'Momentum')
equal(chain_messages[1].text, 'MOMC1|1001|102|1|75|50|1800000000000|1800000000|1|1|3|123456789|123600000', 'Native deadline and decimal sequence')
commands.momentumstatus.onTrigger(player, 'on')
equal(#timers, 1, 'Repeated opt in does not duplicate heartbeat')
equal(decode(messages[#messages - 1]).sequence, decoded.sequence + 1, 'Same-second sequence increases')
local before = #messages
invoke('xi.effects.dedication.onEffectLose', effects[249])
equal(#messages, before, 'No snapshot inside removal callback')
effects[249] = nil
advance(0.1)
assert(messages[#messages].text:match('|0|0|0|0|1$'), 'Removal sampled after callback')
count = count + 1
invoke('xi.experiencePoints.calculate', {}, {})
invoke('xi.effects.level_sync.onEffectGain', effects[269])
invoke('xi.effects.level_sync.onEffectLose', effects[269])
invoke('xi.effects.dedication.onEffectGain', {})
invoke('xi.player.onPlayerLevelUp')
invoke('xi.player.onPlayerLevelDown')
advance(0.1)
before = #messages
advance(5)
equal(#messages, before + 1, 'One periodic snapshot')
commands.momentumstatus.onTrigger(player, 'off')
equal(vars['[Momentum]Status'], 0)
assert(messages[#messages - 1].text:match('|0$'), 'Opt out immediately clears client feed')
count = count + 1
equal(decode(messages[#messages - 1]).enabled, false, 'Opt-out frame round trip')
assert(chain_messages[#chain_messages].text:match('|0|0|0|0|0$'), 'Opt out clears native timing')
count = count + 1
before = #messages
local chain_before = #chain_messages
advance(10)
equal(#messages, before, 'No heartbeats after off')
equal(#chain_messages, chain_before, 'No chain heartbeat after off')
commands.momentumstatus.onTrigger(player, 'on')
local_vars = {}
timers = {}
invoke('xi.player.onGameIn', false, true)
advance(0.1)
equal(vars['[Momentum]Status'], 1, 'Preference survives a zone')
native_chain = { known = true, count = 0, server_now_ms = 100000, deadline_ms = 400000 }
chain_before = #chain_messages
invoke('xi.experiencePoints.calculate', {}, {})
equal(#chain_messages, chain_before, 'No chain sample inside EXP calculation')
advance(0.1)
assert(chain_messages[#chain_messages].text:match('|1|1|0|100000|400000$'), 'First eligible kill has a count-zero deadline')
count = count + 1
native_chain.server_now_ms = 105000
advance(5)
assert(chain_messages[#chain_messages].text:match('|1|1|0|105000|400000$'), 'Heartbeat retains the native absolute deadline')
count = count + 1
local zero_reward = { exp = 0, chainWindow = 120 }
super = function() calls = calls + 1; return zero_reward end
local before_calls = calls
chain_before = #chain_messages
equal(overrides['xi.experiencePoints.calculate'](player, {}, {}), zero_reward, 'Zero EXP result is unchanged')
equal(calls, before_calls + 1, 'Zero EXP calculation calls super once')
equal(#chain_messages, chain_before, 'Wait for engine deadline update after zero EXP')
native_chain = { known = true, count = 3, server_now_ms = 105100, deadline_ms = 225100 }
advance(0.1)
assert(chain_messages[#chain_messages].text:match('|1|1|3|105100|225100$'), 'Native zero-EXP deadline refresh preserves its count')
count = count + 1
native_chain = { known = true, count = 0, server_now_ms = 400000, deadline_ms = 0 }
advance(5)
assert(chain_messages[#chain_messages].text:match('|1|1|0|400000|0$'), 'Native inactive state clears the chain')
count = count + 1
native_chain = { known = true, count = 65534, server_now_ms = 9007199254440991, deadline_ms = 9007199254740991 }
advance(5)
assert(chain_messages[#chain_messages].text:match('|1|1|65534|9007199254440991|9007199254740991$'), 'Largest exact wire integers stay decimal')
count = count + 1
for _, value in ipairs({
    { known = false },
    { known = true, count = 1, server_now_ms = 1000, deadline_ms = 301001 },
    { known = true, count = 1, server_now_ms = 1000, deadline_ms = 1000 },
    { known = true, count = 1, server_now_ms = 1000, deadline_ms = 0 },
    { known = true, count = 65535, server_now_ms = 1000, deadline_ms = 2000 },
    { known = true, count = 1, server_now_ms = math.huge, deadline_ms = math.huge },
}) do
    native_chain = value
    advance(5)
    assert(chain_messages[#chain_messages].text:match('|1|0|0|0|0$'), 'Invalid native data stays unknown')
    count = count + 1
end
GetMomentumChain = nil
advance(5)
assert(chain_messages[#chain_messages].text:match('|1|0|0|0|0$'), 'Missing C++ module stays unknown')
count = count + 1
GetMomentumChain = function() error('Unavailable native provider') end
before = #messages
advance(5)
equal(#messages, before + 1, 'Native provider error preserves status feed')
assert(chain_messages[#chain_messages].text:match('|1|0|0|0|0$'), 'Native provider error stays unknown')
count = count + 1
player.getMainJob = function() return 23 end
before = #messages
chain_before = #chain_messages
advance(5)
equal(#messages, before, 'No unsupported monster-job frames')
equal(#chain_messages, chain_before, 'No unsupported monster-job chain frames')
return { count = count }
