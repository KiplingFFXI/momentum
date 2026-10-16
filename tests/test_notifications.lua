local engine = require('core.notifications')
local history = require('ui.history')
local count = 0
local function check(value, message)
    count = count + 1
    assert(value, message)
end
local function equal(value, expected, message)
    check(value == expected, message .. ': ' .. tostring(value) .. ' ~= ' .. tostring(expected))
end
local settings = { alerts = { events = {}, cap_headroom = 1, food_soon_seconds = 60,
    chain_soon_seconds = 10, quiet_paused = true } }
for _, id in ipairs(engine.EVENTS) do
    settings.alerts.events[id] = { visual = true, sound = true, file = 'example.wav', volume = 42, cooldown = 30 }
end
local snapshot = { valid = true, id = 1001, job = 1, zone = 100, food = true, food_seconds = 61, dedication = true }
local view = { valid = true, level = 32, merits = 8, merit_cap = 10, merits_gained = 0,
    chain = 3, chain_left = 11, chain_left_min = 11,
    chain_source = 'local', chain_estimated = true, rings = { { key = '0:1:1', name = 'Empress Band', charges = 2, recast = 1 } },
    goal = { type = 'session_exp', label = 'Session EXP goal', target = 1000, current = 900, available = true, complete = false } }
local n = engine.new()
n:observe(view, snapshot, 0, settings)
equal(#n:take(0), 0, 'Loading known state is quiet')
local next_view, next_snapshot = history.copy(view), history.copy(snapshot)
next_view.level, next_view.merits, next_view.merits_gained = 33, 9, 1
next_view.chain_left_min = 9
next_view.chain_left = 9
next_view.rings[1].recast, next_view.goal.complete = 0, true
next_snapshot.food_seconds = 59
n:observe(next_view, next_snapshot, 1, settings)
local messages = n:take(1)
equal(#messages, 7, 'Distinct observed milestones and thresholds trigger')
local found = {}
for _, message in ipairs(messages) do found[message.id] = message; equal(message.volume, 42, 'Per-event volume retained') end
for _, id in ipairs({ 'level', 'merit', 'goal', 'cap', 'food_soon', 'ring_ready', 'chain_soon' }) do
    check(found[id], 'Observed event: ' .. id)
end
-- The chain warning follows the observed local countdown.
local chain = engine.new()
chain:observe(view, snapshot, 0, settings)
local changed = history.copy(view); changed.chain_left, changed.chain_left_min = 9, 9
chain:observe(changed, snapshot, 1, settings)
messages = chain:take(1)
equal(#messages, 1, 'One chain warning')
equal(messages[1].text, 'Estimated EXP chain time is running out.', 'Chain warning identifies the estimate')
check(chain:view(1) ~= nil, 'Visual notice is available')
equal(chain:view(6), nil, 'Notice expires without changing layout')
chain:observe(changed, snapshot, 1.5, settings)
equal(#chain:take(1.5), 0, 'Steady threshold does not repeat')

local unconfirmed = history.copy(view)
unconfirmed.chain_source, unconfirmed.chain_estimated = 'unknown', true
chain = engine.new()
chain:observe(unconfirmed, snapshot, 0, settings)
unconfirmed.chain_left, unconfirmed.chain_left_min = 9, 9
chain:observe(unconfirmed, snapshot, 1, settings)
equal(#chain:take(1), 0, 'Unavailable timing cannot trigger a chain warning')
chain:observe(changed, snapshot, 2, settings)
equal(#chain:take(2), 0, 'A first local countdown below the threshold establishes a quiet baseline')
chain = engine.new()
chain:observe(view, snapshot, 0, settings)
chain:observe(unconfirmed, snapshot, 1, settings)
equal(#chain:take(1), 0, 'Losing local timing cannot trigger a chain warning')

local function fresh()
    local result = engine.new()
    result:observe(view, snapshot, 0, settings)
    return result
end
n = fresh()
n:observe(next_view, next_snapshot, 5, settings)
equal(#n:take(5), 0, 'Observation gap does not manufacture milestones')
n = fresh()
next_snapshot.zone = 101
n:observe(next_view, next_snapshot, 1, settings)
equal(#n:take(1), 0, 'Zoning is quiet')
next_snapshot.zone = 100
n = fresh()
next_snapshot.id = 1002
n:observe(next_view, next_snapshot, 1, settings)
equal(#n:take(1), 0, 'Character change is quiet')
next_snapshot.id = 1001
n = fresh()
next_snapshot.dead = true
n:observe(next_view, next_snapshot, 1, settings)
equal(#n:take(1), 0, 'Death is quiet')
next_snapshot.dead = false
n = fresh()
next_view.paused = true
n:observe(next_view, next_snapshot, 1, settings)
equal(#n:take(1), 0, 'Paused session respects quiet setting')
next_view.paused = false
n = fresh()
n:observe(next_view, next_snapshot, 1, settings, true)
equal(#n:take(1), 0, 'Cutscene quiet flag consumes rather than delays events')
n:observe(next_view, next_snapshot, 1.5, settings, false)
equal(#n:take(1.5), 0, 'Quiet event is not replayed later')

n = engine.new()
local off = history.copy(settings)
for _, row in pairs(off.alerts.events) do row.visual, row.sound = false, false end
n:observe(view, snapshot, 0, off)
n:observe(next_view, next_snapshot, 1, settings)
equal(#n:take(1), 0, 'Enabling an alert does not report an old threshold')
n = fresh()
check(n:message('no_exp', 'Too far away to gain EXP.', 1, settings, false, 'one'), 'Normal no-EXP message accepted while fresh')
check(not n:message('no_exp', 'Too far away to gain EXP.', 1, settings, false, 'one'), 'Duplicate message suppressed')
check(not n:message('no_exp', 'Too far away to gain EXP.', 1, settings, false, 'two'), 'Per-event cooldown suppresses repetition')
equal(#n:take(1), 1, 'One no-EXP reason delivered')
check(n:message('dedication_end', 'Dedication ended.', 1, settings, false, 'three'), 'Observed Dedication loss accepted')
equal(#n:take(1), 1, 'Dedication loss delivered')
check(not n:message('dedication_end', 'Dedication ended.', 1, settings, false, 'four'), 'One loss does not rearm itself')
n:discontinuity()
check(not n:message('no_exp', 'Too far away to gain EXP.', 1.1, settings, false, 'five'), 'No stale message after zone reset')
n = fresh()
n:message('no_exp', 'Too far away to gain EXP.', 1, settings, false, 'one')
equal(#n:take(4), 0, 'Delayed audio is discarded')

n = fresh()
n:preview('goal', 'Test notification', 2)
equal(n:view(2).text, 'Test notification', 'Explicit visual preview works independently of automatic alerts')

-- A new EXP session does not start a new food effect or EXP chain.
local reset_settings = history.copy(settings)
for _, row in pairs(reset_settings.alerts.events) do row.cooldown = 0 end
local function event_ids(events, expected, label)
    local received = {}
    equal(#events, #expected, label .. ': event count')
    for _, event in ipairs(events) do
        check(not received[event.id], label .. ': no duplicate ' .. event.id)
        received[event.id] = true
    end
    for _, id in ipairs(expected) do check(received[id], label .. ': ' .. id) end
end
local old_session = history.copy(view)
old_session.merits_gained, old_session.goal.complete = 5, true
local reset_view = history.copy(old_session)
reset_view.merits_gained, reset_view.goal.complete, reset_view.goal.current = 0, false, 0
local first_gain = history.copy(reset_view)
first_gain.merits_gained, first_gain.goal.complete, first_gain.goal.current = 1, true, 1000
first_gain.chain_left, first_gain.chain_left_min = 9, 9
local expiring_food = history.copy(snapshot)
expiring_food.food_seconds = 59

for _, source in ipairs({ 'local' }) do
    old_session.chain_source, reset_view.chain_source, first_gain.chain_source = source, source, source
    local reset_engine = engine.new()
    reset_engine:observe(old_session, snapshot, 100, reset_settings)
    reset_engine:reset_session(reset_view)
    equal(#reset_engine:take(100), 0, source .. ': reset alone emits no warning')
    reset_engine:observe(first_gain, expiring_food, 101, reset_settings)
    event_ids(reset_engine:take(101), { 'merit', 'goal', 'food_soon', 'chain_soon' },
        source .. ': first post-reset sample keeps thresholds and new session milestones')
    reset_engine:observe(first_gain, expiring_food, 101.25, reset_settings)
    equal(#reset_engine:take(101.25), 0, source .. ': stable readings never duplicate warnings with zero cooldown')
    local below_threshold = history.copy(first_gain)
    below_threshold.merits_gained, below_threshold.goal.complete = 0, false
    reset_engine:reset_session(below_threshold)
    reset_engine:observe(below_threshold, expiring_food, 101.5, reset_settings)
    equal(#reset_engine:take(101.5), 0, source .. ': another reset below the thresholds does not rearm warnings')
    below_threshold.chain_left, below_threshold.chain_left_min = nil, nil
    local ended_food = history.copy(expiring_food)
    ended_food.food, ended_food.food_seconds = false, nil
    reset_engine:observe(below_threshold, ended_food, 102, reset_settings)
    equal(#reset_engine:take(102), 0, source .. ': natural timer expiry does not repeat near-expiry warnings')
end

local queued = engine.new()
queued:observe(view, snapshot, 0, reset_settings)
queued:observe(next_view, next_snapshot, 1, reset_settings)
queued:reset_session(reset_view)
event_ids(queued:take(1), { 'level', 'cap', 'food_soon', 'ring_ready', 'chain_soon' },
    'Reset removes old session notices while preserving queued game alerts')
check(queued:message('dedication_end', 'Dedication ended.', 1.1, reset_settings, false, 'reset-dedication'),
    'Reset keeps Dedication loss armed')
event_ids(queued:take(1.1), { 'dedication_end' }, 'Dedication loss still delivers after reset')
queued:observe(next_view, next_snapshot, 1.25, reset_settings)
queued:take(1.25)
queued:reset_session(reset_view)
check(not queued:message('dedication_end', 'Dedication ended.', 1.3, reset_settings, false, 'reset-dedication'),
    'Reset keeps packet tokens, so a repeated Dedication message stays suppressed')

local visual = engine.new()
visual:preview('food_soon', 'Food effect is nearly over.', 0)
visual:reset_session(reset_view)
equal(visual:view(1).text, 'Food effect is nearly over.', 'Reset preserves a visible food warning')
visual:preview('chain_soon', 'EXP chain time is running out.', 1)
visual:reset_session(reset_view)
equal(visual:view(2).text, 'EXP chain time is running out.', 'Reset preserves a visible chain warning')
visual:preview('goal', 'Old session goal reached.', 2)
visual:reset_session(reset_view)
equal(visual:view(2).text, 'Old session goal reached.', 'An already displayed goal keeps its normal notice lifetime')
visual:preview('merit', 'Old session merit point gained.', 2)
visual:reset_session(reset_view)
equal(visual:view(2).text, 'Old session merit point gained.', 'An already displayed merit notice keeps its normal lifetime')
equal(visual:view(7), nil, 'Reset does not extend visible notice expiry')
local mixed_notice = engine.new()
mixed_notice:observe(reset_view, snapshot, 0, reset_settings)
mixed_notice:observe(first_gain, expiring_food, 1, reset_settings)
mixed_notice:take(1)
local mixed_text = mixed_notice:view(1).text
check(mixed_text:find('Merit point gained.', 1, true) and mixed_text:find('Food effect:', 1, true)
    and mixed_text:find('EXP chain', 1, true), 'Same-frame session and game warnings share a visible notice')
mixed_notice:reset_session(reset_view)
equal(mixed_notice:view(2).text, mixed_text, 'Reset keeps the food and chain warnings within a mixed notice')
equal(mixed_notice:view(6), nil, 'A mixed notice expires on its original deadline after reset')

local paused_reset = engine.new()
local paused_before, paused_after = history.copy(view), history.copy(first_gain)
paused_before.paused, paused_after.paused = true, true
paused_before.chain_source, paused_after.chain_source = 'local', 'local'
paused_reset:observe(paused_before, snapshot, 0, reset_settings)
paused_reset:reset_session(paused_before)
paused_reset:observe(paused_after, expiring_food, 1, reset_settings)
equal(#paused_reset:take(1), 0, 'A paused reset still respects quiet-while-paused')
paused_after.paused = false
paused_reset:observe(paused_after, expiring_food, 1.5, reset_settings)
equal(#paused_reset:take(1.5), 0, 'Unpausing does not replay consumed timer warnings')

local stale_reset = fresh()
stale_reset:reset_session(reset_view)
check(not stale_reset:message('no_exp', 'Too far away to gain EXP.', 3, reset_settings, false, 'reset-stale'),
    'Reset does not refresh an old observation timestamp')
stale_reset:discontinuity()
stale_reset:reset_session(reset_view)
stale_reset:observe(first_gain, expiring_food, 4, reset_settings)
equal(#stale_reset:take(4), 0, 'A zone or reload discontinuity remains quiet after session reset')
return count .. ' notification checks'
