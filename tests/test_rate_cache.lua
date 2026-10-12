local tracker = require('core.tracker')
local rules = require('data.phoenix_rules')
local count = 0
local function equal(actual, expected, label)
    count = count + 1
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function snapshot(exp, lp)
    return { valid = true, id = 1001, job = 1, level = 50, effective_level = 50, zone = 102,
        exp = exp or 1000, exp_needed = rules.tnl[50], lp = lp or 1000, merits = 1, merit_cap = 10 }
end
local state = tracker.new()
state:observe(snapshot(), 0)
state:award({ kind = 'exp', amount = 200 }, 0)
state:award({ kind = 'lp', amount = 100 }, 0)
state:observe(snapshot(1200, 1100), 0)
state:award({ kind = 'exp', amount = 300 }, 1)
state:observe(snapshot(1300, 1050), 1)
local raw_pairs = pairs
local scans = 0
pairs = function(value)
    if value == state.buckets then scans = scans + 1 end
    return raw_pairs(value)
end
local function compare(now, window, basis)
    local elapsed, exp, lp, earned = state:_elapsed(now), 0, 0, 0
    local net = basis == 'net'
    if window == 0 then
        exp, lp, earned = net and state.net_exp or state.session_exp, net and state.net_lp or state.session_lp, state.session_exp
    else
        for _, bucket in raw_pairs(state.buckets) do
            if bucket.second >= elapsed - window and bucket.second <= elapsed then
                exp = exp + (bucket[net and 'net_exp' or 'exp'] or 0)
                lp = lp + (bucket[net and 'net_lp' or 'lp'] or 0)
                earned = earned + (bucket.exp or 0)
            end
        end
    end
    local duration = window == 0 and elapsed or math.min(window, elapsed)
    local actual_exp, actual_lp, actual_earned = state:_rates(now, window, basis)
    equal(actual_exp, exp * 3600 / duration, 'EXP rate matches uncached calculation')
    equal(actual_lp, lp * 3600 / duration, 'LP rate matches uncached calculation')
    equal(actual_earned, earned * 3600 / duration, 'Earned EXP rate matches uncached calculation')
end
compare(60.01, 300, 'net')
equal(scans, 1, 'First rate view scans once')
for frame = 2, 99 do compare(60 + frame / 100, 300, 'net') end
equal(scans, 1, 'Changing fractional denominator reuses unchanged bucket sums')
compare(61, 300, 'net')
equal(scans, 2, 'New integer bucket boundary scans again')
state:award({ kind = 'exp', amount = 50 }, 61.01)
compare(61.01, 300, 'net')
equal(scans, 3, 'A reward invalidates sums within the same second')
state:observe(snapshot(1250, 1070), 61.02)
compare(61.02, 300, 'net')
equal(scans, 4, 'Observed retained gains and losses invalidate sums immediately')
for _, now in ipairs({ 300, 300.00001, 300.5, 301, 301.00001, 301.5 }) do
    for _, window in ipairs({ 0, 300, 900, 1800 }) do
        for _, basis in ipairs({ 'earned', 'net' }) do compare(now, window, basis) end
    end
end
state:pause(301.5, true)
compare(5000, 300, 'net')
local paused_scans = scans
compare(9000, 300, 'net')
equal(scans, paused_scans, 'Paused views keep sums and rates without rescanning')
state:pause(9000, false)
compare(9000.5, 300, 'net')
local saved = state:export(9000.5)
state:reset(9001)
equal(state.rate_cache, nil, 'Reset drops old sum cache')
equal(state:restore(saved, 20000), true, 'Saved session restores')
equal(state.rate_cache, nil, 'Restore starts with a fresh sum cache')
compare(20000, 300, 'net')
state:observe(snapshot(), 20000)
state:award({ kind = 'lp', amount = 80 }, 20001)
compare(20001, 300, 'earned')
pairs = raw_pairs
return count .. ' assertions'
