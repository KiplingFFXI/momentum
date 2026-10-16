local packets = require('core.packets')
local status = require('core.phoenix_status')
local count = 0
local function equal(actual, expected, why)
    count = count + 1
    assert(actual == expected, (why or 'Mismatch') .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function snapshot()
    return { valid = true, id = 1001, zone = 102, job = 1, level = 75, effective_level = 50,
        utc = 1800000000, sync_active = true, dedication = true, dedication_seconds = 600,
        food = false, food_known = true }
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
local view = state:view(0)
equal(view.sync_active, true, 'Client sync status is retained')
equal(view.sync_level, 50, 'Client sync level is retained')
equal(view.sync_gap, 25, 'Sync gap is calculated from client levels')
equal(view.dedication, true, 'Dedication status comes from the client')
equal(state:view(1).dedication_seconds, 599, 'Client duration counts down between samples')
sample.dedication, sample.dedication_seconds = false, nil
state:observe(sample, 2)
equal(state:view(2).dedication, false, 'Client reports Dedication ending')
equal(state:view(2).dedication_seconds, nil, 'Ended Dedication has no timer')
equal(state:view(6).dedication, nil, 'Stale snapshots do not report old effects')
state:observe(snapshot(), 6)
equal(state:view(6).dedication_seconds, 600, 'A new snapshot restores the observed duration')
state:reason({ actor_id = 1001, target_id = 1001, reason = 'sync_target' }, 6)
equal(state:view(6).no_exp_reason, 'sync_target')
state:award(); equal(state:view(6).no_exp_reason, nil)
equal(state:reason({ actor_id = 1002, target_id = 1001, reason = 'distance' }, 6), false)
equal(state:reason({ actor_id = 1001, target_id = 1002, reason = 'distance' }, 6), false)
equal(state:reason({ actor_id = 1001, target_id = 1001, reason = 'other' }, 6), false)
equal(state:item({ id = 1001, item_id = 4381 }, 6, 'Meat Mithkabob'), true)
sample = snapshot(); sample.food, sample.food_seconds = true, 1800; state:observe(sample, 7)
equal(state:view(7).food_name, 'Meat Mithkabob')
equal(state:view(8).food_seconds, 1799)
sample.food = false; state:observe(sample, 8)
equal(state:view(8).food_name, nil)
sample.food = true; state:observe(sample, 9)
equal(state:view(9).food_name, nil, 'Unobserved food is unknown')
sample.food_known = false; state:observe(sample, 10)
equal(state:view(10).food_name, nil, 'Unknown effects clear the observed food name')
state:discontinuity(); state:observe(snapshot(), 11)
equal(state:view(11).no_exp_reason, nil, 'A discontinuity clears the last no-EXP reason')
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

for _, source in ipairs({ 'battle', 'item' }) do
    state = status.new(); sample = snapshot(); state:observe(sample, 0)
    local award = { source = source, token = 'same-' .. source, chain = 1 }
    state:award(award, 0)
    state:reason({ actor_id = sample.id, target_id = sample.id, reason = 'distance' }, 0)
    state:award(award, 0.1)
    equal(state:view(0.1).no_exp_reason, 'distance', 'Duplicate reward preserves later no-EXP reason')
    state:award({ source = source, token = 'new-' .. source, chain = 1 }, 0.2)
    equal(state:view(0.2).no_exp_reason, nil, 'New reward clears the no-EXP reason')
end
for index = 1, 300 do state:award({ source = 'item', token = index }, 1) end
equal(#state.chain_token_order, 256, 'Reward identity history stays bounded')
state:reason({ actor_id = sample.id, target_id = sample.id, reason = 'distance' }, 1)
for now = 2, 16 do state:observe(sample, now) end
equal(state:view(16).no_exp_reason, nil, 'The no-EXP reason clears after fifteen seconds')
return { count = count }
