local packets = require('core.packets')
local status = require('core.phoenix_status')
local count = 0
local function equal(actual, expected, why)
    count = count + 1
    assert(actual == expected, (why or 'Mismatch') .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function frame(message, channel, sender, zone)
    local bytes = MOCK.bytes(23 + #message + 1)
    MOCK.put(bytes, 4, 1, channel or 29)
    MOCK.put(bytes, 6, 2, zone or 102)
    sender = sender or 'Momentum'
    for i = 1, #sender do bytes[7 + i] = sender:byte(i) end
    for i = 1, #message do bytes[22 + i] = message:byte(i) end
    return MOCK.packet(0x017, bytes)
end
local function payload(sequence, active, pool)
    return table.concat({ 'MOM1', 1001, 102, 1, 75, 50, sequence or 1000001, 1800000000, 1, 37, 15,
        active == false and 0 or 1, pool or (active == false and 0 or 700), active == false and 0 or 50,
        active == false and 0 or 600, 1 }, '|')
end
local function snapshot()
    return { valid = true, id = 1001, zone = 102, job = 1, level = 75, effective_level = 50,
        utc = 1800000000, sync_active = true, dedication = true, dedication_seconds = 600,
        food = false, food_known = true }
end
local valid = payload()
local feed = packets.status(frame(valid), 1001)
equal(feed.sync_penalty, 37)
equal(feed.dedication_pool, 700)
for _, channel in ipairs({ 0, 1, 6, 26, 200 }) do equal(packets.status(frame(valid, channel), 1001), nil, 'Non-system channel') end
equal(packets.status(frame(valid, 29, 'Tester'), 1001), nil, 'Sender')
equal(packets.status(frame(valid, 29, 'Momentum', 101), 1001), nil, 'Envelope zone')
equal(packets.status(frame(valid), 1002), nil, 'Recipient')
for _, bad in ipairs({ valid .. '|0', valid .. '|', valid:gsub('MOM1', 'MOM2'), valid:gsub('|37|', '|51|'),
    valid:gsub('|15|', '|10|'), valid:gsub('|700|', '|-1|'), valid:gsub('|700|', '|0.1|'), valid:gsub('|700|', '||'),
    valid:gsub('|75|50|', '|50|75|'), (valid:gsub('|700|', '|99999999999999999999|')) }) do
    equal(packets.status(frame(bad), 1001), nil, 'Malformed feed')
end
for _, flag in ipairs({ 'blocked', 'blocked_original', 'injected', 'is_injected' }) do
    local event = frame(valid); event[flag] = true
    equal(packets.status(event, 1001), nil, 'Blocked feed')
end
for length = 0, 23 do
    local event = frame(valid); event.data, event.size = event.data:sub(1, length), length
    equal(packets.status(event, 1001), nil, 'Short feed')
end
equal(status.plan(75, 65, 2000), 0)
equal(status.plan(75, 64, 499), 0)
equal(status.plan(75, 64, 500), 16)
equal(status.plan(75, 64, 999), 16)
equal(status.plan(75, 64, 1000), 22)
equal(status.plan(75, 64, 2000), 27)
equal(status.plan(75, 10, 2000), 50)
equal(status.plan(75, 9, 2000), nil)
equal(status.plan(50, 60, 1000), nil)
equal(status.plan(50, 25, -1), nil)
local state = status.new()
local sample = snapshot()
state:observe(sample, 0)
equal(state:view(0).sync_penalty, nil, 'No inferred applied penalty')
equal(state:message(feed, 0), true)
equal(state:view(1).dedication_seconds, 599)
equal(state:view(1).sync_age, 1)
equal(state:message(feed, 1), false, 'Replay')
state:award()
equal(state:view(1).dedication_pool, nil, 'Award invalidates old budget')
feed.sequence = feed.sequence + 1
equal(state:message(feed, 1), true)
equal(state:view(1).dedication_pool, 700)
sample.effective_level = 51; state:observe(sample, 2)
equal(state:view(2).sync_penalty, nil, 'Level context changed')
equal(state:message(feed, 2), false, 'Old effective level')
sample = snapshot(); state:observe(sample, 3)
feed.sequence = feed.sequence + 1; feed.utc = sample.utc - 13
equal(state:message(feed, 3), false, 'Old server time')
feed.utc = sample.utc + 6
equal(state:message(feed, 3), false, 'Future server time')
feed.utc = sample.utc
equal(state:message(feed, 3), true)
for time = 4, 16 do state:observe(sample, time) end
equal(state:view(16).sync_penalty, nil, 'Heartbeat timeout')
state:reason({ actor_id = 1001, target_id = 1001, reason = 'sync_target' }, 16)
equal(state:view(16).no_exp_reason, 'sync_target')
state:award(); equal(state:view(16).no_exp_reason, nil)
equal(state:reason({ actor_id = 1002, target_id = 1001, reason = 'distance' }, 16), false)
equal(state:item({ id = 1001, item_id = 4381 }, 16, 'Meat Mithkabob'), true)
sample.food, sample.food_seconds = true, 1800; state:observe(sample, 17)
equal(state:view(17).food_name, 'Meat Mithkabob')
equal(state:view(18).food_seconds, 1799)
sample.food = false; state:observe(sample, 18)
equal(state:view(18).food_name, nil)
sample.food = true; state:observe(sample, 19)
equal(state:view(19).food_name, nil, 'Unobserved food is unknown')
state:discontinuity(); state:observe(snapshot(), 20)
equal(state:message(feed, 20), false, 'Replay after zone')
feed.sequence = feed.sequence + 1; feed.enabled = false
equal(state:message(feed, 20), true)
equal(state:view(20).sync_penalty, nil, 'Opt out')
local function effect(effect_id, message, actor, target)
    local bytes = MOCK.bytes(28)
    MOCK.put(bytes, 4, 4, actor or 1001); MOCK.put(bytes, 8, 4, target or 1001)
    MOCK.put(bytes, 12, 4, effect_id); MOCK.put(bytes, 24, 2, message)
    return MOCK.packet(0x029, bytes)
end
equal(packets.no_exp(effect(0, 545), 1001).reason, 'sync_target')
equal(packets.no_exp(effect(0, 37), 1001).reason, 'distance')
equal(packets.no_exp(effect(0, 545, 1002), 1001), nil)
equal(packets.no_exp(effect(0, 545, 1001, 1002), 1001), nil)
equal(packets.no_exp(effect(0, 8), 1001), nil)
equal(packets.dedication_end(effect(249, 206), 1001).effect, 249)
equal(packets.dedication_end(effect(251, 206), 1001), nil)
equal(packets.dedication_end(effect(249, 206, 1002), 1001), nil)
local function put_bits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local byte, bit = math.floor((offset + i) / 8), (offset + i) % 8
        local old = math.floor(bytes[byte] / 2 ^ bit) % 2
        local next_bit = math.floor(value / 2 ^ i) % 2
        bytes[byte] = bytes[byte] + (next_bit - old) * 2 ^ bit
    end
end
local function item_use(message, actor, target, category, resolution)
    local bytes = MOCK.bytes(35)
    put_bits(bytes, 40, 32, actor or 1001)
    put_bits(bytes, 72, 6, 1)
    put_bits(bytes, 82, 4, category or 5)
    put_bits(bytes, 86, 32, 4381)
    put_bits(bytes, 150, 32, target or 1001)
    put_bits(bytes, 182, 4, 1)
    put_bits(bytes, 186, 3, resolution or 0)
    put_bits(bytes, 230, 10, message)
    return MOCK.packet(0x028, bytes)
end
equal(packets.item_use(item_use(0), 1001).item_id, 4381, 'Normal food completion has no message')
equal(packets.item_use(item_use(28), 1001).item_id, 4381, 'Generic item completion')
equal(packets.item_use(item_use(56), 1001), nil, 'Failed item')
equal(packets.item_use(item_use(0, 1002), 1001), nil, 'Other user')
equal(packets.item_use(item_use(0, 1001, 1002), 1001), nil, 'Other target')
equal(packets.item_use(item_use(0, 1001, 1001, 9), 1001), nil, 'Item start is not completion')
equal(packets.item_use(item_use(0, 1001, 1001, 5, 1), 1001), nil, 'Non-hit result')
local short = item_use(0); short.size, short.data = 34, short.data:sub(1, 34)
equal(packets.item_use(short, 1001), nil, 'Truncated item completion')

state = status.new(); sample = snapshot(); state:observe(sample, 0)
feed = packets.status(frame(payload()), 1001)
feed.utc, feed.dedication_seconds = sample.utc - 10, 20
equal(state:message(feed, 0), true, 'Recent delayed status is accepted')
equal(state:view(0).sync_age, 10, 'Known transit age counts toward status freshness')
equal(state:view(0).dedication_seconds, 10, 'Transit age does not restart Dedication duration')
sample.utc = sample.utc + 2; state:observe(sample, 2)
equal(state:view(2).sync_penalty, 37, 'Delayed status remains available at exact freshness boundary')
sample.utc = sample.utc + 1; state:observe(sample, 3)
equal(state:view(3).sync_penalty, nil, 'Delayed status expires based on source age')

state = status.new(); sample = snapshot(); state:observe(sample, 0)
feed = packets.status(frame(payload()), 1001)
feed.utc = sample.utc - 10
equal(state:message(feed, 3), false, 'Unsampled elapsed time also counts toward report age')
sample.utc = nil; state:observe(sample, 4)
local old_time = os.time
os.time = function() return 1800000013 end
equal(state:message(feed, 4), false, 'Wall clock rejects stale status when client UTC is unavailable')
os.time = function() return 1800000010 end
feed.utc, feed.dedication_seconds = 1800000000, 20
equal(state:message(feed, 4), true, 'Wall-clock fallback accepts a fresh-enough report')
equal(state:view(4).dedication_seconds, 10, 'Wall-clock fallback subtracts transit age')
os.time = old_time

for _, source in ipairs({ 'battle', 'item' }) do
    state = status.new(); sample = snapshot(); state:observe(sample, 0)
    local award = { source = source, token = 'same-' .. source, chain = 1 }
    state:award(award, 0)
    feed = packets.status(frame(payload()), 1001)
    equal(state:message(feed, 0), true, 'Fresh report follows genuine reward')
    state:reason({ actor_id = sample.id, target_id = sample.id, reason = 'distance' }, 0)
    state:award(award, 0.1)
    equal(state:view(0.1).dedication_pool, 700, 'Duplicate reward preserves fresh Dedication budget')
    equal(state:view(0.1).no_exp_reason, 'distance', 'Duplicate reward preserves later no-EXP reason')
    state:award({ source = source, token = 'new-' .. source, chain = 1 }, 0.2)
    equal(state:view(0.2).dedication_pool, nil, 'New reward still invalidates old Dedication budget')
    equal(state:view(0.2).no_exp_reason, nil, 'New reward still clears no-EXP reason')
end
return { count = count }
