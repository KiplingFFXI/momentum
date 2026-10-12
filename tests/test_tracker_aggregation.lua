local tracker, defaults, rules = require('core.tracker'), require('ui.defaults'), require('data.phoenix_rules')
local count = 0
local function equal(actual, expected, why)
    count = count + 1
    assert(actual == expected, why .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function snapshot(exp, lp)
    return { valid = true, id = 1001, job = 1, level = 50, effective_level = 50, zone = 102,
        exp = exp or 1000, exp_needed = rules.tnl[50], lp = lp or 1000, merits = 1, merit_cap = 10 }
end
local t, settings = tracker.new(), defaults.make()
t:observe(snapshot(), 0)
t:award({ kind = 'exp', amount = 200, token = 'exp0' }, 0)
t:award({ kind = 'lp', amount = 100, token = 'lp0' }, 0)
t:observe(snapshot(1200, 1100), 0)
t:award({ kind = 'exp', amount = 300, token = 'exp1' }, 1)
t:observe(snapshot(1300, 1050), 1)
local exp, lp, earned = t:_rates(59.999, 300, 'net')
equal(exp, nil, 'EXP pace remains unavailable before sixty seconds')
equal(lp, nil, 'LP pace remains unavailable before sixty seconds')
equal(earned, nil, 'Earned pace remains unavailable before sixty seconds')
exp, lp, earned = t:_rates(60, 300, 'net')
equal(exp, 18000, 'Net EXP pace uses retained gains')
equal(lp, 3000, 'Net LP pace includes observed losses')
equal(earned, 30000, 'Earned EXP pace remains distinct under Net mode')
exp, lp, earned = t:_rates(300, 300, 'net')
equal(exp, 3600, 'Oldest bucket remains included at exact cutoff')
equal(lp, 600, 'LP exact cutoff includes both buckets')
equal(earned, 6000, 'Earned exact cutoff includes both buckets')
exp, lp, earned = t:_rates(300.001, 300, 'net')
equal(exp, 1200, 'Fractional cutoff expires oldest EXP bucket immediately')
equal(lp, -600, 'Fractional cutoff preserves negative LP rate')
equal(earned, 3600, 'Earned EXP uses the same fractional cutoff')
settings.tracking.window, settings.tracking.rate_basis = 300, 'net'
settings.tracking.goal_type, settings.tracking.goal_exp = 'session_exp', 1000
local view = t:view(300.001, settings)
equal(view.exp.rate, 1200, 'View receives combined net EXP rate')
equal(view.lp.rate, -600, 'View receives combined net LP rate')
equal(view.goal.rate, 3600, 'Session EXP goal still uses earned rate in Net mode')
equal(view.goal.eta, 500, 'Session EXP ETA uses earned rate')
exp, lp, earned = t:_rates(301, 300, 'earned')
equal(exp, 3600, 'Second bucket survives its exact cutoff')
equal(lp, 0, 'Expired earned LP bucket is excluded')
equal(earned, exp, 'Earned basis shares its EXP result')
exp, lp, earned = t:_rates(301.001, 300, 'net')
equal(exp, 0, 'Second bucket expires after fractional boundary')
equal(lp, 0, 'Negative LP bucket expires after fractional boundary')
equal(earned, 0, 'Earned second bucket expires at same boundary')
for _, basis in ipairs({ 'earned', 'net' }) do
    for _, window in ipairs({ 0, 900, 1800 }) do
        exp, lp, earned = t:_rates(300.001, window, basis)
        equal(exp, (basis == 'net' and 300 or 500) * 3600 / 300.001, 'Larger/session window EXP keeps fractional denominator')
        equal(lp, (basis == 'net' and 50 or 100) * 3600 / 300.001, 'Larger/session window LP keeps fractional denominator')
        equal(earned, 500 * 3600 / 300.001, 'Larger/session window earned EXP keeps fractional denominator')
    end
end
t:pause(300.5, true)
exp, lp, earned = t:_rates(5000, 300, 'net')
equal(exp, 1200, 'Paused rate window does not expire while real time passes')
equal(lp, -600, 'Paused negative LP rate remains fixed')
equal(earned, 3600, 'Paused earned rate remains fixed')
t:pause(5100, false)
exp = t:_rates(5100, 300, 'net')
equal(exp, 1200, 'Resume keeps recorded elapsed time')
exp = t:_rates(5100.501, 300, 'net')
equal(exp, 0, 'Post-resume fractional boundary expires normally')
local previous_pairs, scans = pairs, 0
pairs = function(value)
    if value == t.buckets then scans = scans + 1 end
    return previous_pairs(value)
end
t:view(5101, settings)
pairs = previous_pairs
equal(scans, 0, 'Net view reuses sums inside unchanged integer bucket boundaries')
local gains, awards = t.pending_gains, t.pending_awards
t:_reconcile(5102)
equal(t.pending_gains, gains, 'Empty reconciliation keeps existing gain queue')
equal(t.pending_awards, awards, 'Empty reconciliation keeps existing award queue')
local pending = tracker.new()
pending:observe(snapshot(), 0)
pending:observe(snapshot(1123), 1)
pending:_reconcile(4)
equal(pending.adjustment, 0, 'Unmatched gain stays pending at exact match boundary')
pending:_reconcile(4.001)
equal(pending.adjustment, 123, 'Gain-only queue is still reconciled after boundary')
equal(#pending.pending_gains, 0, 'Expired gain queue drains')
pending:award({ kind = 'exp', amount = 77, token = 'unmatched' }, 5)
pending:_reconcile(8)
equal(#pending.pending_awards, 1, 'Award-only queue stays pending at exact match boundary')
pending:_reconcile(8.001)
equal(#pending.pending_awards, 0, 'Award-only queue still expires normally')
return { count = count }
