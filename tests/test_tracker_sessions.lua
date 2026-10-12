local tracker = require('core.tracker')
local rules = require('data.phoenix_rules')
local checks = 0
local function equal(a, b, label)
    checks = checks + 1
    assert(a == b, label .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a))
end
local function near(a, b, label)
    checks = checks + 1
    assert(a and math.abs(a - b) < 0.001, label .. ': expected ' .. b .. ', got ' .. tostring(a))
end
local function snapshot(values)
    local s = { valid = true, id = 100, job = 1, job_name = 'WAR', level = 75, effective_level = 50,
        zone = 100, exp = 1000, exp_needed = rules.tnl[75], lp = 1000, merits = 1,
        merit_cap = 10, limit_mode = true, dead = false }
    for key, value in pairs(values or {}) do s[key] = value end
    return s
end
local state = tracker.new()
state:observe(snapshot(), 0)
local empty = state:view(0)
equal(empty.recent.count, 0, 'No reward sample yet')
equal(empty.recent.average, nil, 'Empty average is unknown')
equal(empty.recent.min, nil, 'Empty minimum is unknown')
equal(empty.recent.median, nil, 'Empty median is unknown')
for index, amount in ipairs({ 100, 500, 200, 800 }) do
    state:award({ kind = 'exp', amount = amount, source = 'item', token = index }, index)
end
state:award({ kind = 'lp', amount = 300, source = 'battle', chain = 4 }, 5)
state:observe(snapshot({ exp = 2600, lp = 1300 }), 5.1)
local view = state:view(61, { tracking = { average_count = 4, window = 0 } })
equal(view.exp.recent3.count, 3, 'Three samples exclude first reward')
near(view.exp.recent3.average, 500, 'Recent three mean')
equal(view.exp.recent3.median, 500, 'Odd median sorted by value')
equal(view.exp.recent.min, 100, 'Minimum reward')
equal(view.exp.recent.max, 800, 'Maximum reward')
equal(view.exp.recent.median, 350, 'Even median averages middle values')
equal(view.exp.recent10.count, 4, 'Short history shows actual sample size')
equal(view.exp.recent10.requested, 10, 'Requested sample count retained')
equal(view.lp.recent.count, 1, 'LP samples separate from EXP')
equal(view.recent.average, 300, 'Current-mode samples use LP')
equal(view.exp.session, 1600, 'EXP total always exposed')
equal(view.lp.session, 300, 'LP total always exposed')
equal(view.exp.current, 2600, 'Simultaneous EXP progress')
equal(view.lp.current, 1300, 'Simultaneous LP progress')
near(view.exp.rate, 96000, 'Simultaneous EXP rate')
near(view.lp.rate, 18000, 'Simultaneous LP rate')

local saved = state:export(61)
equal(saved.best_chain, 4, 'Best chain saved')
local restored = tracker.new()
equal(restored:restore(saved, 10000, { id = 100, job = 1 }), true, 'Restore matching identity')
equal(restored:view(10000).valid, false, 'Restore waits for current client progress')
restored:observe(snapshot({ exp = 30000, lp = 9000, merits = 5 }), 10000)
local resumed = restored:view(10000, { tracking = { window = 0, average_count = 4 } })
equal(resumed.net_exp, view.net_exp, 'Offline EXP changes excluded')
equal(resumed.net_lp, view.net_lp, 'Offline LP changes excluded')
equal(resumed.merits_gained, 0, 'Offline merits excluded')
equal(resumed.elapsed, 60, 'Offline time excluded')
equal(resumed.chain, nil, 'Active chain not restored across gap')
equal(resumed.best_chain, 4, 'Session best chain restored')
equal(resumed.exp.recent.median, 350, 'Recent samples restored')
near(resumed.exp.rate, view.exp.rate, 'Rate resumes on recorded elapsed time')
restored:award({ kind = 'exp', amount = 100, token = 1 }, 10001)
equal(restored:view(10001).session_exp, 1700, 'Old packet tokens do not block new connection')
restored:reset(10002)
equal(restored:award({ kind = 'exp', amount = 100, token = 1 }, 10003), false, 'Manual reset retains packet identity history')
equal(restored:view(10003).recent.count, 0, 'Manual reset clears recent samples')

local wrong = tracker.new()
equal(wrong:restore(saved, 5, { id = 200, job = 1 }), false, 'Cannot restore other character')
equal(wrong:restore(saved, 5, { id = 100, job = 2 }), false, 'Cannot restore other job')
saved.elapsed = 0 / 0
equal(wrong:restore(saved, 5), false, 'Reject nonfinite saved elapsed')
saved = state:export(61)
saved.recent_exp[1] = -10
equal(wrong:restore(saved, 5), false, 'Reject negative recent award')
equal(wrong:view(5).session_exp, 0, 'Rejected restore does not mutate tracker')
saved = state:export(61)
saved.buckets.hidden = { second = 1, exp = 100 }
equal(wrong:restore(saved, 5), false, 'Reject non-array rate history')
saved = state:export(61)
saved.recent_exp.hidden = 100
equal(wrong:restore(saved, 5), false, 'Reject non-array reward history')
saved = state:export(61)
saved.started = false
equal(wrong:restore(saved, 5), false, 'Reject elapsed time without a started session')

state:pause(71, true)
local paused = tracker.new()
equal(paused:restore(state:export(90), 20000), true, 'Restore paused session')
paused:observe(snapshot(), 20000)
equal(paused:view(20100).elapsed, 70, 'Paused reload excludes all waiting time')
paused:pause(20100, false)
paused:observe(snapshot(), 20100)
equal(paused:view(20130).elapsed, 100, 'Paused session resumes cleanly')

state = tracker.new()
state:observe(snapshot({ limit_mode = false }), 0)
for index = 1, 150 do state:award({ kind = 'exp', amount = index }, index) end
local bounded = state:view(200, { tracking = { average_count = 500 } })
equal(#state.recent_exp, 100, 'Recent history bounded')
equal(bounded.recent.count, 100, 'Custom sample count bounded')
equal(bounded.recent.min, 51, 'Oldest samples removed first')
near(bounded.recent.median, 100.5, 'Bounded median uses last hundred')
equal(bounded.exp.count, 150, 'Whole session award count retained')
local missing = snapshot()
missing.lp = nil
state:observe(missing, 201)
equal(state:view(201).lp.current, nil, 'Unknown LP never substitutes EXP')

state = tracker.new()
state:observe(snapshot(), 0)
state:observe(snapshot({ exp = 1100 }), 1)
local pending = state:export(1.1)
equal(pending.adjustment, 100, 'Unmatched saved progress remains an adjustment')
equal(state.adjustment, 0, 'Checkpoint does not expire live reconciliation window')
state:award({ kind = 'exp', amount = 100 }, 2)
equal(state:view(6).adjustment, 0, 'Reward can still match after checkpoint')
return checks .. ' assertions'
