local sessions = require('core.sessions')
local rules = require('data.phoenix_rules')
local store = require('core.file_store')
local checks = 0
local function equal(a, b, label)
    checks = checks + 1
    assert(a == b, label .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a))
end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function snapshot(values)
    local s = { valid = true, id = 100, job = 1, job_name = 'WAR', level = 30, effective_level = 30,
        zone = 100, exp = 1000, exp_needed = rules.tnl[30], lp = 1000, merits = 1,
        merit_cap = 10, limit_mode = false, dead = false }
    for key, value in pairs(values or {}) do s[key] = value end
    return s
end
local disk, files, writes, wall, fail = {}, {}, 0, 1700000000, false
local options = {
    read = function(path) return copy(files[path] or {}) end,
    write = function(path, data)
        writes = writes + 1
        if fail then return false, 'Write failed.' end
        disk = copy(data)
        files[path] = copy(data)
        return true
    end,
    clock = function() return wall end,
}
local manager = sessions.new('memory', options)
equal(manager:current(), nil, 'No session before coherent character')
equal(#manager:list(), 0, 'No invented history')
local state = manager:select(snapshot(), 0)
equal(writes, 1, 'New session saved once')
equal(manager:current().name, 'WAR session', 'New session has a useful default name')
equal(manager:current().active, true, 'Current session marked active')
equal(manager:current().character_id, 100, 'Session tied to character id')
state:award({ kind = 'exp', amount = 200, token = 'first' }, 1)
state:observe(snapshot({ exp = 1200 }), 1.1)
for now = 1, 29 do manager:checkpoint(now) end
equal(writes, 1, 'Render checkpoints do not write every frame')
manager:checkpoint(30)
equal(writes, 2, 'Active session saved at thirty seconds')
equal(manager:current().session_exp, 200, 'Current summary includes rewards')
equal(disk.entries[1].payload.net_exp, 200, 'Retained EXP persisted')
local first_id = manager:current().id
equal(manager:rename(first_id, '  Evening party  '), true, 'Rename active session')
equal(manager:current().name, 'Evening party', 'Name is trimmed')
equal(manager:rename(first_id, 'bad##name'), false, 'Reject ImGui control suffix')
equal(manager:rename(first_id, ''), false, 'Reject empty name')
equal(manager:delete(first_id), false, 'Cannot delete active session')

local loaded = sessions.new('memory', options)
local resumed, did_resume = loaded:select(snapshot({ exp = 5000 }), 10000)
equal(did_resume, true, 'Reload resumes matching open session')
equal(resumed:view(10000).valid, false, 'Loaded tracker waits for a fresh snapshot')
resumed:observe(snapshot({ exp = 5000 }), 10000)
equal(resumed:view(10000).session_exp, 200, 'Reload retains reported EXP')
equal(resumed:view(10000).net_exp, 200, 'Reload does not infer unloaded progress')
equal(resumed:view(10000).elapsed, 29, 'Reload does not include offline time')
equal(loaded:current().name, 'Evening party', 'Saved name survives reload')
local before_writes = writes
local same = loaded:select(snapshot({ job = 2, exp_needed = rules.tnl[31] }), 10001)
equal(same, resumed, 'Mixed job and EXP packets do not switch session')
equal(writes, before_writes, 'Mixed snapshot does not write')
local other = loaded:select(snapshot({ job = 2, job_name = 'MNK' }), 10010)
equal(other == resumed, false, 'Coherent new job gets a separate tracker')
equal(loaded:current().job, 2, 'New job selected')
equal(#loaded:list(), 2, 'Both job sessions retained')
other:award({ kind = 'exp', amount = 500 }, 10011)
wall = wall + 60
loaded:checkpoint(10020, true)
local old = loaded:select(snapshot({ exp = 5100 }), 11000)
old:observe(snapshot({ exp = 5100 }), 11000)
equal(old:view(11000).session_exp, 200, 'Switching back resumes that job only')
equal(old:view(11000).elapsed, 39, 'Time spent on another job excluded')

local new = loaded:new_session(11010, 'Fresh start')
equal(new, old, 'New session preserves tracker packet deduplication')
equal(new:view(11010).session_exp, 0, 'New session resets reward totals')
equal(loaded:current().name, 'Fresh start', 'New named session selected')
equal(#loaded:list(), 3, 'Old session archived')
equal(loaded:delete(first_id), true, 'Archived session can be deleted')
equal(#loaded:list(), 2, 'Deleted row removed')
local active_id = loaded:current().id
local rows = loaded:list()
rows[1].name = 'Changed outside'
equal(loaded:current().name, 'Fresh start', 'History rows do not alias manager')
fail = true
equal(loaded:rename(active_id, 'Failed name'), false, 'Failed rename reported')
equal(loaded:current().name, 'Fresh start', 'Failed rename preserves in-memory name')
local inactive_id
for _, row in ipairs(loaded:list()) do if not row.active then inactive_id = row.id end end
equal(loaded:delete(inactive_id), false, 'Failed delete reported')
equal(#loaded:list(), 2, 'Failed delete preserves rows')
equal(loaded:problem(), 'Write failed.', 'Save failure visible')
fail = false
equal(loaded:checkpoint(11020, true), true, 'Explicit retry can save')
equal(loaded:problem(), nil, 'Successful retry clears problem')

new:award({ kind = 'exp', amount = 100, token = 'dup' }, 11021)
local reset = loaded:new_session(11022)
equal(reset:award({ kind = 'exp', amount = 100, token = 'dup' }, 11023), false, 'Reset does not count duplicate packet again')
local detached = loaded:detach(11024)
equal(detached:view(11024).valid, false, 'Character transition returns an empty tracker')
equal(loaded:current(), nil, 'Character transition clears active binding')
local after_detach_writes = writes
loaded:checkpoint(15000)
equal(writes, after_detach_writes, 'Waiting for character data does not extend a saved session')
local next_character = loaded:select(snapshot({ id = 200 }), 16000)
equal(next_character:view(16000).session_exp, 0, 'Other character starts its own session')
equal(#loaded:list(), 1, 'History defaults to current character only')
equal(#loaded:list(100), 3, 'Other character history retained separately')

local no_resume = sessions.new('memory', options)
local fresh, restored = no_resume:select(snapshot(), 20000, { sessions = { resume = false, retention = 2 } })
equal(restored, false, 'Resume can be disabled')
equal(fresh:view(20000).session_exp, 0, 'Disabled resume starts fresh')
equal(#disk.entries, 2, 'Retention bounds total stored rows')
equal(no_resume:current().active, true, 'Retention always keeps current session')
for i = 1, 4 do no_resume:new_session(20000 + i, 'Run ' .. i) end
equal(#disk.entries, 2, 'Repeated new sessions stay bounded')

local a, b = sessions.new('parallel.json', options), sessions.new('parallel.json', options)
local ta = a:select(snapshot(), 0)
local tb = b:select(snapshot({ id = 200 }), 0)
ta:award({ kind = 'exp', amount = 111 }, 1)
tb:award({ kind = 'exp', amount = 222 }, 1)
equal(a:checkpoint(10, true), true, 'First character writes its own file')
equal(b:checkpoint(10, true), true, 'Second character writes its own file')
equal(files['parallel-100.json'].entries[1].payload.session_exp, 111, 'First character file retained')
equal(files['parallel-200.json'].entries[1].payload.session_exp, 222, 'Second character file retained')
local c = sessions.new('parallel.json', options)
local tc = c:select(snapshot(), 100)
tc:observe(snapshot(), 100)
tc:award({ kind = 'exp', amount = 50 }, 101)
equal(c:checkpoint(110, true), true, 'New client saves a newer version of same character')
ta:award({ kind = 'exp', amount = 7 }, 11)
equal(a:checkpoint(20, true), false, 'Older client refuses an external change')
equal(files['parallel-100.json'].entries[1].payload.session_exp, 161, 'External change is not overwritten')
equal(a:current().session_exp, 118, 'Conflicting client retains its unsaved progress in memory')
equal(a:problem():find('Another game client', 1, true) ~= nil, true, 'Conflict explains why saving stopped')
equal(a:new_session(21), nil, 'Cannot reset away unsaved progress on conflict')
equal(a:current().session_exp, 118, 'Failed reset preserves conflicting session')
local old_id = a:current().id
a:select(snapshot({ id = 300 }), 30)
equal(a:problem() ~= nil, true, 'Unsaved prior-character error remains visible')
equal(a:rename(old_id, 'Wrong character'), false, 'Qualified history id prevents cross-character rename')
equal(a:list(100)[1].session_exp, 118, 'Suspended unsaved session remains available')
equal(a:checkpoint(60, true), false, 'Suspended conflict is not silently dropped')
equal(files['parallel-300.json'].entries[1].payload.session_exp, 0, 'Other character can still save independently')

local corrupt_list = sessions.new('notarray', { read = function()
    return { version = 1, entries = { surprise = files['parallel-100.json'].entries[1] } }
end })
corrupt_list:select(snapshot(), 0)
equal(corrupt_list:problem() ~= nil, true, 'Malformed non-array history is protected')
equal(sessions.coherent(snapshot({ id = 4294967296 })), false, 'Out-of-range character identity rejected')
local _, _, ready = manager:select(snapshot({ exp_needed = 0 }), 0)
equal(ready, false, 'Readiness rejects incomplete client threshold')
_, _, ready = manager:select(snapshot(), 0)
equal(ready, true, 'Readiness accepts coherent current identity')

local corrupt = sessions.new('broken', { read = function() return nil, 'Corrupt file.' end,
    write = function() error('Must not replace corrupt file') end })
corrupt:select(snapshot(), 0)
equal(corrupt:checkpoint(100, true), false, 'Corrupt file is protected from writes')
equal(corrupt:problem(), 'Corrupt file.', 'Corrupt-file error retained')
equal(corrupt:new_session(100), nil, 'Destructive session reset refused on protected file')
local newer = sessions.new('future', { read = function() return { version = 99, entries = {} } end })
newer:select(snapshot(), 0)
equal(newer:problem() ~= nil, true, 'Future schema is protected')

local path = MOCK_INSTALL_PATH .. '/config/addons/momentum/session_test.json'
local real = sessions.new(path)
local live = real:select(snapshot(), 0)
live:award({ kind = 'exp', amount = 123 }, 1)
equal(real:checkpoint(5, true), true, 'Real atomic file store writes session')
local reload = sessions.new(path)
local from_file = reload:select(snapshot(), 1000)
from_file:observe(snapshot(), 1000)
equal(from_file:view(1000).session_exp, 123, 'Real JSON file reload retains totals')
path = MOCK_INSTALL_PATH .. '/config/addons/momentum/session_test-100.json'
local file = assert(io.open(path, 'rb'))
local original = file:read('*a'); file:close()
MOCK.file_replace_error = true
equal(reload:rename(reload:current().id, 'Cannot replace'), false, 'Atomic rename failure reported')
file = assert(io.open(path, 'rb'))
equal(file:read('*a'), original, 'Atomic failure preserves previous session file'); file:close()
MOCK.file_replace_error = false
file = assert(io.open(path, 'wb')); file:write('{broken'); file:close()
local broken = sessions.new(MOCK_INSTALL_PATH .. '/config/addons/momentum/session_test.json')
broken:select(snapshot(), 1)
equal(broken:checkpoint(2, true), false, 'Malformed JSON not overwritten')
file = assert(io.open(path, 'rb'))
equal(file:read('*a'), '{broken', 'Malformed original remains intact'); file:close()
return checks .. ' assertions'
