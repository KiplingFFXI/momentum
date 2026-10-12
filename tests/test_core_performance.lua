local tracker = require('core.tracker')
local sessions = require('core.sessions')
local defaults = require('ui.defaults')
local rules = require('data.phoenix_rules')
local history = require('ui.history')
local count = 0
local function equal(actual, expected, label)
    count = count + 1
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function snapshot(values)
    local value = { valid = true, id = 1001, job = 1, job_name = 'WAR', level = 30,
        effective_level = 30, zone = 100, exp = 1000, exp_needed = rules.tnl[30], lp = 1000,
        merits = 1, merit_cap = 10, limit_mode = false, dead = false }
    for key, item in pairs(values or {}) do value[key] = item end
    return value
end
local settings, state = defaults.make(), tracker.new()
state:observe(snapshot(), 0)
state:award({ kind = 'exp', amount = 200, token = 'exp1' }, 1)
state:award({ kind = 'lp', amount = 100, token = 'lp1' }, 2)
state:observe(snapshot({ exp = 1200, lp = 1100 }), 2)
local sorts, rate_calls = 0, 0
local sort, rate, rates = table.sort, state._rate, state._rates
table.sort = function(...) sorts = sorts + 1; return sort(...) end
state._rates = function(self, ...) rate_calls = rate_calls + 1; return rates(self, ...) end
local first = state:view(61, settings)
equal(sorts, 4, 'First view computes only distinct default recent summaries')
equal(rate_calls, 1, 'Earned basis calculates all rates in one pass')
local stable = state:view(61, settings)
equal(sorts, 4, 'Stable view does not sort unchanged reward samples')
equal(history.equal(first, stable), true, 'Reused statistics preserve full view values')
first.exp.recent.average = -1
first.exp.recent10.total = -1
equal(state:view(61, settings).exp.recent.average, 200, 'View edits cannot corrupt cached averages')
equal(state:view(61, settings).exp.recent10.total, 200, 'View edits cannot corrupt cached totals')
settings.tracking.average_count = 5
state:view(61, settings)
equal(sorts, 6, 'New sample size computes once for each kind')
state:view(61, settings)
equal(sorts, 6, 'Repeated sample-size setting reuses its statistics')
state:award({ kind = 'exp', amount = 400, token = 'exp2' }, 62)
local changed = state:view(62, settings)
equal(sorts, 9, 'EXP award invalidates only EXP sample summaries')
equal(changed.exp.recent.average, 300, 'New reward updates mean')
equal(changed.exp.recent.median, 300, 'New reward updates median')
equal(changed.exp.recent.min, 200, 'New reward updates minimum')
equal(changed.exp.recent.max, 400, 'New reward updates maximum')
state:award({ kind = 'exp', amount = 400, token = 'exp2' }, 62)
state:view(62, settings)
equal(sorts, 9, 'Duplicate reward does not invalidate statistics')
state:pause(63, true)
state:award({ kind = 'exp', amount = 900, token = 'paused' }, 64)
state:view(64, settings)
equal(sorts, 9, 'Paused reward does not invalidate statistics')
state:pause(65, false)
for _, basis in ipairs({ 'earned', 'net' }) do
    settings.tracking.rate_basis = basis
    for _, window in ipairs({ 0, 300, 900, 1800 }) do
        settings.tracking.window = window
        local before = rate_calls
        local view = state:view(70, settings)
        equal(rate_calls - before, 1, 'All required rates share one pass for either basis and every window')
        equal(view.exp.rate, rate(state, 70, 'exp', window, basis), 'EXP rate preserves rolling arithmetic')
        equal(view.lp.rate, rate(state, 70, 'lp', window, basis), 'LP rate preserves rolling arithmetic')
    end
end
local payload = state:export(70)
state:reset(71)
equal(state:view(71, settings).exp.recent.count, 0, 'Reset invalidates populated summary cache')
equal(state:restore(payload, 100), true, 'Saved tracker restores')
equal(state:view(100, settings).exp.recent.average, 300, 'Restore rebuilds summaries from saved rewards')
equal(state:view(100, settings).lp.recent.average, 100, 'Restore rebuilds LP summaries')
for index = 1, 105 do state:award({ kind = 'exp', amount = index, token = 'bounded' .. index }, 101 + index) end
-- Restore needs a fresh coherent snapshot before collecting again.
equal(state:view(210, settings).exp.recent.average, 300, 'Invalid restored snapshot cannot collect rewards')
state:observe(snapshot(), 211)
for index = 1, 105 do state:award({ kind = 'exp', amount = index, token = 'bounded' .. index }, 211 + index) end
settings.tracking.average_count = 100
local bounded = state:view(317, settings).exp.recent
equal(bounded.count, 100, 'Recent sample history remains bounded')
equal(bounded.min, 6, 'Sliding recent sample drops oldest awards')
equal(bounded.max, 105, 'Sliding recent sample retains newest award')
equal(bounded.average, 55.5, 'Bounded cache keeps exact average')
table.sort = sort

local files, writes, failing = {}, 0, false
local manager = sessions.new('memory', {
    read = function(path) return history.copy(files[path] or {}) end,
    write = function(path, value)
        writes = writes + 1
        if failing then return false, 'Write failed.' end
        files[path] = history.copy(value)
        return true
    end,
    clock = function() return 1700000000 end,
})
local tracked = manager:select(snapshot(), 0)
equal(writes, 1, 'Initial coherent session persists immediately')
manager:checkpoint(0)
for now = 1, 29 do equal(manager:checkpoint_due(now), false, 'Idle frames skip checkpoint dispatch') end
equal(manager:checkpoint_due(30), true, 'Periodic checkpoint stays due at thirty seconds')
manager:checkpoint(30)
equal(writes, 1, 'Unused session is not rewritten')
tracked:award({ kind = 'exp', amount = 200, token = 'after-idle' }, 42)
equal(manager:checkpoint_due(42), true, 'First reward after idle retains immediately due save')
manager:checkpoint(42)
equal(writes, 2, 'First reward after idle saved')
equal(manager:checkpoint_due(43), false, 'Ordinary checkpoint waits after write')
manager:checkpoint(43, true)
equal(writes, 3, 'Explicit forced save bypasses schedule')
failing = true
equal(manager:checkpoint_due(73), true, 'Next write due from forced save time')
local ok, problem = manager:checkpoint(73)
equal(ok, false, 'Write failure remains visible')
equal(problem, 'Write failed.', 'Write failure retains reason')
equal(manager:checkpoint_due(74), false, 'Failed writes retain retry throttle')
equal(manager:checkpoint_due(103), true, 'Failed write retries at original thirty-second boundary')
failing = false
manager:checkpoint(103)
equal(writes, 5, 'Failed save retries successfully')
equal(manager:checkpoint_due(102), true, 'Clock reversal forces schedule re-evaluation')
files['memory-1001.json'].entries[1].name = 'Other client'
local before = writes
ok, problem = manager:checkpoint(133)
equal(ok, false, 'External session-file change is rejected')
equal(problem:find('Another game client', 1, true) ~= nil, true, 'Conflict reason remains explicit')
equal(writes, before, 'Conflict never overwrites another client')
equal(manager:checkpoint_due(134), false, 'Conflict checks retain retry throttle')
equal(manager:checkpoint_due(163), true, 'Conflict can be retried at due time')
return { count = count }
