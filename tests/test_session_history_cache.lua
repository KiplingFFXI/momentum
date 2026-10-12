local sessions = require('core.sessions')
local rules = require('data.phoenix_rules')
local copy = require('ui.history').copy
local count, files, fail = 0, {}, false
local function equal(actual, expected, label)
    count = count + 1
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local s = { valid = true, id = 100, job = 1, job_name = 'WAR', level = 30, effective_level = 30,
    zone = 100, exp = 1000, exp_needed = rules.tnl[30], lp = 1000, merits = 1,
    merit_cap = 10, limit_mode = false, dead = false }
local manager = sessions.new('history.json', {
    read = function(path) return copy(files[path] or {}) end,
    write = function(path, value)
        if fail then return false, 'Write failed' end
        files[path] = copy(value)
        return true
    end,
    clock = function() return 1800000000 end,
})
local empty = manager:history()
equal(manager:history(), empty, 'No-character empty history is reusable')
local tracker = manager:select(s, 0)
local first = manager:current().id
equal(#manager:history(), 0, 'Current session stays out of archived history')
tracker:award({ kind = 'exp', amount = 200 }, 1)
manager:new_session(2, 'Second')
local rows = manager:history()
equal(#rows, 1, 'Reset archives the old session immediately')
equal(rows[1].id, first, 'Archived id stays qualified')
equal(rows[1].session_exp, 200, 'Archive retains its totals')
tracker:award({ kind = 'exp', amount = 300 }, 3)
equal(manager:history(), rows, 'Current rewards do not rebuild archived rows')
equal(manager:current().session_exp, 300, 'Current totals remain live')
for _ = 1, 120 do equal(manager:history(), rows, 'Idle history stays reusable') end
equal(manager:rename(first, 'Renamed'), true, 'Archived rename succeeds')
equal(manager:history()[1].name, 'Renamed', 'Rename refreshes history immediately')
rows = manager:history()
fail = true
equal(manager:rename(first, 'Failed'), false, 'Rename failure reported')
equal(manager:history(), rows, 'Failed rename keeps prior history')
equal(rows[1].name, 'Renamed', 'Failed rename cannot change cached rows')
equal(manager:delete(first), false, 'Delete failure reported')
equal(manager:history(), rows, 'Failed delete keeps prior history')
fail = false
equal(manager:delete(first), true, 'Retry delete succeeds')
equal(#manager:history(), 0, 'Delete refreshes immediately')
manager:new_session(4, 'Third')
manager:new_session(5, 'Fourth')
rows = manager:history()
equal(rows[1].name, 'Third', 'Equal timestamps sort by newest numeric record id')
equal(rows[2].name, 'Second', 'Older numeric record follows')
local list = manager:list()
list[2].name = 'Outside mutation'
equal(manager:history()[1].name, 'Third', 'Legacy mutable list cannot change cached rows')
local other = copy(s); other.job, other.job_name = 2, 'MNK'
manager:select(other, 6)
equal(#manager:history(), 3, 'Job change archives the previous active session')
manager:select(s, 7)
equal(manager:current().name, 'Fourth', 'Original job resumes')
equal(manager:history()[1].name, 'MNK session', 'Resumed session is excluded; former job is included')
manager:detach(8)
equal(#manager:history(100), 4, 'Detach includes all saved sessions for that character')
other.id = 200
manager:select(other, 9)
equal(#manager:history(), 0, 'Other character has separate archived history')
equal(#manager:history(100), 4, 'Prior character history stays available')
manager:select(s, 10, { retention = 2 })
equal(#manager:history(), 1, 'Retention changes refresh archived rows')
return { count = count }
