local tracker = require('core.tracker')
local rules = require('data.phoenix_rules')
local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function near(actual, expected, label)
    checks = checks + 1
    assert(actual and math.abs(actual - expected) < 0.001, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function snapshot(values)
    local result = {
        valid = true, id = 100, job = 1, job_name = 'WAR', level = 30, effective_level = 30,
        zone = 100, exp = 1000, exp_needed = rules.tnl[30], lp = 1000, merits = 0,
        merit_cap = 10, limit_mode = false, limit_breaker = false, exp_locked = false,
        dead = false, dedication = false,
    }
    for key, value in pairs(values or {}) do
        result[key] = value
    end
    if values and values.level and not values.exp_needed then
        result.exp_needed = rules.tnl[values.level]
    end
    return result
end
local function reward(state, amount, now, values)
    local event = { kind = 'exp', amount = amount, chain = 0, source = 'battle' }
    for key, value in pairs(values or {}) do
        event[key] = value
    end
    return state:award(event, now)
end

local state = tracker.new()
equal(state:view(0).valid, false, 'Empty tracker waits for client state')
state:observe(snapshot(), 1)
equal(state:view(1).current, 1000, 'Initial snapshot sets current EXP')
equal(state:view(1).session_exp, 0, 'Initial EXP is no session gain')
equal(state:view(1).net_exp, 0, 'Initial EXP is a baseline')
equal(state:view(1).elapsed, 0, 'Session waits for the first gain')
equal(reward(state, 200, 10, { token = 'first' }), true, 'First award accepted')
equal(reward(state, 200, 10, { token = 'first' }), false, 'Duplicate packet token rejected')
equal(reward(state, 200, 10, { token = 'second' }), true, 'Equal consecutive reward is distinct')
state:observe(snapshot({ exp = 1400 }), 10.5)
equal(state:view(20).adjustment, 0, 'Awards pair with later client progress')
equal(state:view(20).session_exp, 400, 'Reported rewards summed')
equal(state:view(20).net_exp, 400, 'Retained progress summed separately')
equal(state:view(20).average, 200, 'Average uses rewards, not snapshots')
equal(state:view(69).rate, nil, 'Rate waits for sixty seconds')
near(state:view(70).rate, 24000, 'Rate after warmup')
near(state:view(130).rate, 12000, 'Normal downtime lowers session pace')
equal(state:view(911).rate, 0, 'Old rewards age out of the recent pace')
near(state:view(1010, { tracking = { window = 0 } }).rate, 1440, 'Whole-session rate retains rewards')

state = tracker.new()
state:observe(snapshot(), 0)
state:observe(snapshot({ exp = 1250 }), 1)
reward(state, 250, 2)
equal(state:view(6).adjustment, 0, 'Snapshot can arrive before its reward')
state:observe(snapshot({ exp = 1350 }), 7)
equal(state:view(11).adjustment, 100, 'Unreported positive progress stays an adjustment')
equal(state:view(11).session_exp, 250, 'Unknown progress does not inflate earned rewards')
equal(state:view(11).net_exp, 350, 'Unknown progress remains in retained totals')
state:observe(snapshot({ exp = 1300 }), 12)
equal(state:view(16).lost, 0, 'Unexplained loss is not automatically death')
equal(state:view(16).adjustment, 50, 'Unexplained loss remains an adjustment')

state = tracker.new()
state:observe(snapshot({ exp = 5700 }), 0)
reward(state, 300, 1)
state:observe(snapshot({ level = 31, exp = 200 }), 1.5)
equal(state:view(5).net_exp, 300, 'Level-up normalized using source TNL')
equal(state:view(5).lost, 0, 'Level-up is not a death')
state:observe(snapshot({ level = 30, exp = 5600, dead = true }), 6)
equal(state:view(6).lost, 400, 'Delevel loss normalized using source TNL')
equal(state:view(6).net_exp, -100, 'Death reduces net progress')
state:observe(snapshot({ level = 30, exp = 5800 - 50, dead = false }), 10)
equal(state:view(14).recovered, 150, 'Revival restores only observed death loss')
equal(state:view(14).session_exp, 300, 'Raise does not count as earned EXP')

state = tracker.new()
state:observe(snapshot({ exp = 5700 }), 0)
reward(state, 300, 1)
state:observe(snapshot({ exp = 200, exp_needed = rules.tnl[31] }), 1.1)
equal(state:view(1.1).current, 5700, 'Mixed job and EXP packets hold the previous progress')
state:observe(snapshot({ level = 31, exp = 200 }), 1.2)
equal(state:view(5).net_exp, 300, 'Coherent level-up resumes without a synthetic loss')
equal(state:view(5).lost, 0, 'Mixed packets create no death loss')
equal(state:view(5).adjustment, 0, 'Mixed packets create no artificial adjustment')

state = tracker.new()
state:observe(snapshot(), 0)
reward(state, 100, 1)
state:observe(snapshot({ exp = 1100 }), 1.1)
state:pause(31, true)
state:observe(snapshot({ exp = 2000, dedication = true }), 40)
reward(state, 900, 40)
equal(state:view(60).current, 2000, 'Paused current progress still refreshes')
equal(state:view(60).dedication, true, 'Paused passive status still refreshes')
equal(state:view(60).session_exp, 100, 'Paused rewards excluded')
equal(state:view(60).elapsed, 30, 'Paused time excluded')
state:pause(91, false)
state:observe(snapshot({ exp = 2000 }), 91.1)
equal(state:view(121).elapsed, 60, 'Session resumes from active elapsed time')
near(state:view(121).rate, 6000, 'Pause does not dilute the active-time rate')
equal(state:view(121).net_exp, 100, 'Paused progress excluded from retained total')

state = tracker.new()
state:observe(snapshot({ level = 75, exp = 43900 }), 0)
reward(state, 500, 1, { source = 'item' })
state:observe(snapshot({ level = 75, exp = 43999 }), 1.1)
local view = state:view(5, { display = { mode = 'exp' } })
equal(view.session_exp, 500, 'Capped reported reward stays reported')
equal(view.net_exp, 99, 'Cap truncation uses retained client progress')
equal(view.capped, true, 'EXP buffer cap recognized')
equal(view.remaining, 0, 'Full buffer has no remaining progress')
equal(view.eta, nil, 'No level76 ETA on the server profile')
equal(state:view(5).mode, 'lp', 'Auto view follows full75 EXP into LP')

state = tracker.new()
state:observe(snapshot({ level = 75, limit_mode = true, lp = 9500, merits = 2 }), 0)
reward(state, 1000, 1, { kind = 'lp' })
state:observe(snapshot({ level = 75, limit_mode = true, lp = 500, merits = 3 }), 1.1)
equal(state:view(5).net_lp, 1000, 'Merit rollover retains the full LP gain')
equal(state:view(5).merits_gained, 1, 'Observed merit gain recorded')
equal(state:view(5).session_exp, 0, 'LP never becomes EXP')
equal(state:view(5).session_lp, 1000, 'LP award retained separately')
equal(state:view(5).goal_remaining, 19500, 'Goal counts stored merits and current LP')
state:observe(snapshot({ level = 75, limit_mode = true, lp = 500, merits = 1 }), 6)
equal(state:view(10).net_lp, 1000, 'Merit spending is no negative LP gain')
equal(state:view(10).adjustment, 0, 'Merit spending is no adjustment')
state:observe(snapshot({ level = 75, limit_mode = true, lp = 400, merits = 1 }), 10.1)
equal(state:view(10.2).net_lp, 900, 'An actual LP drop remains in net progress')
equal(state:view(10.2).adjustment, -100, 'An unexplained LP drop stays an adjustment')
state:observe(snapshot({ level = 74, limit_mode = true, exp = 40000, lp = 500, merits = 1, dead = true }), 11)
equal(state:view(11).mode, 'exp', 'Delevel below75 leaves LP view in auto')

state = tracker.new()
state:observe(snapshot({ level = 75, limit_mode = true, lp = 9900, merits = 10 }), 0)
reward(state, 400, 1, { kind = 'lp' })
state:observe(snapshot({ level = 75, limit_mode = true, lp = 9999, merits = 10 }), 1.1)
equal(state:view(5).session_lp, 400, 'Full-merit reward uses the message amount')
equal(state:view(5).net_lp, 99, 'Full-merit retained LP uses the client delta')
equal(state:view(5).capped, true, 'Full-merit LP cap recognized')
equal(state:view(5).eta, nil, 'Full merits have no next-merit ETA')

state = tracker.new()
local unknown = snapshot()
unknown.lp = nil
unknown.merits = nil
unknown.merit_cap = nil
state:observe(unknown, 0)
view = state:view(0, { display = { mode = 'lp' } })
equal(view.current, nil, 'Unknown LP does not fall back to EXP')
equal(view.merit_cap, nil, 'Unknown cap stays unknown')
equal(view.goal_remaining, nil, 'Unknown merit total leaves goal unknown')

state = tracker.new()
state:observe(snapshot(), 0)
reward(state, 200, 1, { chain = 3 })
state:observe(snapshot({ exp = 1200 }), 1.1)
state:discontinuity(2)
state:observe(snapshot({ exp = 4000, zone = 101 }), 3)
equal(state:view(3).net_exp, 200, 'Zoning rebaseline does not invent missed gains')
equal(state:view(3).chain, nil, 'Zoning clears active chain')
equal(state:view(3).best_chain, 3, 'Zoning preserves session best')
state:observe(snapshot({ id = 200, exp = 5000 }), 4)
equal(state:view(4).session_exp, 0, 'Character switch starts a separate session')
equal(state:view(4).net_exp, 0, 'Character switch creates no progress delta')
reward(state, 100, 5)
state:observe(snapshot({ id = 200, job = 2, exp = 100 }), 6)
equal(state:view(6).session_exp, 0, 'Job switch starts a separate session')
state:observe({ valid = false }, 7)
equal(state:view(7).valid, false, 'Invalid client state hides progress')
state:observe(snapshot({ id = 200, job = 2, exp = 500 }), 8)
equal(state:view(8).net_exp, 0, 'Login baseline excludes missed progress')

state = tracker.new()
state:observe(snapshot(), 0)
for index = 1, 3000 do
    reward(state, 1, index, { token = tostring(index) })
end
equal(#state.token_order, 2048, 'Packet identity history is bounded')
local bucket_count = 0
for _ in pairs(state.buckets) do
    bucket_count = bucket_count + 1
end
equal(bucket_count, 1801, 'Rate buckets are bounded')
equal(state:view(3000).session_exp, 3000, 'Bounded recent history preserves whole-session totals')
state:reset(3001)
equal(state:view(3001).elapsed, 0, 'Reset waits for a new first gain')
equal(state:view(3001).session_exp, 0, 'Reset clears session totals')
equal(state:view(3001).current, 1000, 'Reset preserves current client progress')

return tostring(checks) .. ' assertions'
