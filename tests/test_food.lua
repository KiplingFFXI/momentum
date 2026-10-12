local food = require('core.food')
local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function snapshot(present, changes)
    local result = { valid = true, id = 100, zone = 101, food_known = true, food = present }
    for key, value in pairs(changes or {}) do
        result[key] = value
    end
    return result
end
local function message(changes)
    local result = { actor_id = 100, target_id = 100, effect = 251, message = 206 }
    for key, value in pairs(changes or {}) do
        result[key] = value
    end
    return result
end

local state = food.new()
equal(state:message(message(), 0, true), false, 'No initial sound without observed food')
equal(state:observe(snapshot(false), 1, true), false, 'Loading without food stays quiet')
equal(state:message(message(), 1.1, true), false, 'Unarmed loss message stays quiet')
equal(state:observe(snapshot(true), 2, true), false, 'Food observation itself stays quiet')
equal(state:message(message({ effect = 249 }), 2.1, true), false, 'Dedication loss is not food')
equal(state:message(message({ message = 204 }), 2.1, true), false, 'Different loss message is ignored')
equal(state:message(message({ target_id = 200 }), 2.1, true), false, 'Another target is ignored')
equal(state:message(message({ actor_id = 200 }), 2.1, true), false, 'Another actor is ignored')
equal(state:message(message({ token = 'first' }), 2.2, true), true, 'Server food loss after observed food notifies')
equal(state:message(message({ token = 'first' }), 2.2, true), false, 'Duplicate packet does not notify twice')
equal(state:observe(snapshot(true), 2.3, true), false, 'Stale icon after the message stays quiet')
equal(state:message(message({ token = 'different' }), 2.4, true), false, 'Stale icon cannot rearm a consumed alert')
state:observe(snapshot(false), 2.5, true)
state:observe(snapshot(true), 3, true)
equal(state:message(message(), 3.1, true), true, 'New food cycle can notify again')

state = food.new()
state:observe(snapshot(true), 0, true)
equal(state:observe(snapshot(false), 1, true), false, 'Memory-only disappearance stays quiet')
equal(state:message(message(), 2.9, true), true, 'Loss message can follow a status update')
state = food.new()
state:observe(snapshot(true), 0, true)
state:observe(snapshot(false), 1, true)
state:observe(snapshot(false), 2, true)
equal(state:message(message(), 3.1, true), false, 'Old disappeared food is no longer armed')
state:observe(snapshot(true), 4, true)
equal(state:message(message(), 6.1, true), false, 'Stale observations do not notify')

state = food.new()
state:observe(snapshot(true), 0, false)
equal(state:message(message(), 0.1, false), false, 'Disabled notifications stay quiet')
equal(state:message(message(), 0.2, true), false, 'Turning on cannot reuse a disabled baseline')
equal(state:observe(snapshot(true), 1, true), false, 'Turning on with food does not play')
equal(state:message(message(), 1.1, true), true, 'Enabled observation arms a later genuine loss')
state:observe(snapshot(true), 1.2, false)
equal(state:message(message(), 1.3, true), false, 'Disable and enable clears a consumed old state')
state:observe(snapshot(false), 2, true)
equal(state:message(message(), 2.1, true), false, 'Enabling without food stays unarmed')

state = food.new()
state:observe(snapshot(true), 0, true)
state:discontinuity()
equal(state:message(message(), 0.1, true), false, 'Explicit zoning gap disarms the alert')
state:observe(snapshot(false, { zone = 102 }), 1, true)
equal(state:message(message(), 1.1, true), false, 'Arriving without food stays quiet')
state:observe(snapshot(true), 2, true)
state:observe(snapshot(false, { id = 200 }), 2.1, true)
equal(state:message(message({ actor_id = 200, target_id = 200 }), 2.2, true), false, 'Character switch never counts as food loss')
state:observe(snapshot(true), 3, true)
state:observe(snapshot(false, { zone = 102 }), 3.1, true)
equal(state:message(message(), 3.2, true), false, 'Zone switch never counts as food loss')
state:observe(snapshot(true), 4, true)
state:observe(snapshot(false, { food_known = false }), 4.1, true)
equal(state:message(message(), 4.2, true), false, 'Unknown food state disarms the alert')
state:observe(snapshot(true), 5, true)
state:observe({ valid = false }, 5.1, true)
equal(state:message(message(), 5.2, true), false, 'Invalid player state disarms the alert')
state:observe(snapshot(true), 6, true)
state:observe(snapshot(false), 10, true)
equal(state:message(message(), 10.1, true), false, 'A sampling gap cannot manufacture a food transition')

state = food.new()
state:observe(snapshot(true), 0, true)
state:observe(snapshot(false, { dead = true }), 1, true)
equal(state:observe(snapshot(false, { dead = true }), 2, true), false, 'Silent death removal does not notify')
equal(state:observe(snapshot(false, { dead = false }), 3, true), false, 'Revival without food does not notify')
equal(state:message(message(), 3.1, true), false, 'Late removal message cannot reuse silent death loss')

state = food.new()
state:observe(snapshot(true), 0, true)
equal(state:message(message(), 0 / 0, true), false, 'Invalid time does not notify')
equal(state:message(message(), -1, true), false, 'Backward time does not notify')
equal(state:message({}, 0.1, true), false, 'Incomplete messages are ignored')
for index = 1, 300 do
    state:message(message({ token = tostring(index) }), 0.1, false)
end
equal(#state.token_order, 256, 'Duplicate history is bounded')

return tostring(checks) .. ' assertions'
