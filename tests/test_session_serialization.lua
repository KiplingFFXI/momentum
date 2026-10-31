local sessions = require('core.sessions')
local tracker = require('core.tracker')
local rules = require('data.phoenix_rules')
local json = require('json')
local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local snapshot = { valid = true, id = 100, job = 1, job_name = 'WAR', level = 30,
    zone = 100, exp = 1000, exp_needed = rules.tnl[30], lp = 500, merits = 1,
    merit_cap = 10, limit_mode = false, dead = false }
local seed = tracker.new()
seed:observe(snapshot, 0)
seed:award({ kind = 'exp', amount = 50 }, 1)
for id = 1, 20 do seed.farming:received(id, 2, 1, {}) end
local fixture = { version = 1, next_id = 6, entries = {} }
for id = 1, 5 do
    fixture.entries[id] = { id = tostring(id), name = 'Saved ' .. id, job_name = 'WAR',
        created = id, saved = id, closed = true, payload = seed:export(60) }
end
local path = 'serialized-100.json'
local files = { [path] = json.encode(fixture) }
local reads, writes, fail, wall = 0, 0, false, 1800000000
local options = {
    read_text = function(key) reads = reads + 1; return files[key] end,
    write_text = function(key, value)
        writes = writes + 1
        if fail then return false, 'Write failed' end
        files[key] = value
        return true
    end,
    clock = function() return wall end,
}
local manager = sessions.new('serialized.json', options)
local current = manager:select(snapshot, 100, { retention = 10 })
local archived_id = '100:5'
equal(#manager:list(), 6, 'Version-one history loads without a migration or sidecar')
equal(manager:history()[1].session_exp, 50, 'Archived EXP remains available')
equal(manager:history()[1].farming.total, 40, 'Archived farming totals remain available')
equal(files['serialized-100.json.active'], nil, 'Saving does not create an alternate current-session file')

local encode, decode, encodes, decodes = json.encode, json.decode, 0, 0
json.encode = function(value) encodes = encodes + 1; return encode(value) end
json.decode = function(value) decodes = decodes + 1; return decode(value) end
current:award({ kind = 'exp', amount = 200 }, 101)
current.farming:received(1, 3, 101, {})
wall = wall + 30
local before_reads, before_writes = reads, writes
equal(manager:checkpoint(130), true, 'Due checkpoint saves live totals')
equal(encodes, 1, 'Checkpoint encodes only its changed current record')
equal(decodes, 0, 'Unchanged disk bytes do not decode the archive or written baseline')
equal(reads, before_reads + 1, 'Checkpoint still checks the original file for external edits')
equal(writes, before_writes + 1, 'Checkpoint performs one atomic write')
local written = decode(files[path])
equal(written.version, 1, 'JSON schema remains version one')
equal(written.entries[1].payload.session_exp, 200, 'Current EXP reaches the file')
equal(written.entries[1].payload.farming.total, 3, 'Current farming totals reach the file')
equal(#written.entries, 6, 'Unchanged archived records remain in the same file')

-- A formatting-only outside edit must retain the previous semantic equality rule.
files[path] = '\n  ' .. files[path] .. '\n'
equal(manager:checkpoint(160, true), true, 'Formatting-only outside changes remain saveable')
equal(decodes, 2, 'Only changed disk bytes invoke semantic comparison')
equal(encodes, 2, 'Formatting comparison does not re-encode archived records')

equal(manager:rename(archived_id, 'Renamed archive'), true, 'Renaming a cached archived record succeeds')
equal(encodes, 3, 'Rename invalidates only that archived fragment')
equal(manager:history()[1].name, 'Renamed archive', 'History reflects the renamed record')
fail = true
local durable = files[path]
equal(manager:rename(archived_id, 'Failed rename'), false, 'Failed archived rename is reported')
equal(files[path], durable, 'Failed write keeps the entire original JSON')
equal(manager:history()[1].name, 'Renamed archive', 'Failed rename rolls the in-memory name back')
fail = false
equal(manager:checkpoint(190, true), true, 'A checkpoint can retry after failed rename')
written = decode(files[path])
for _, entry in ipairs(written.entries) do
    if entry.id == '5' then equal(entry.name, 'Renamed archive', 'Retry cannot persist the rolled-back name') end
end

local original_count = #manager:list()
fail = true
equal(manager:delete(archived_id), false, 'Failed archived delete is reported')
equal(#manager:list(), original_count, 'Failed delete keeps archived rows')
fail = false
equal(manager:checkpoint(220, true), true, 'A checkpoint restores the cached deleted fragment after failure')
equal(#decode(files[path]).entries, original_count, 'Retry preserves the failed deletion in the file')

-- A valid outside edit must still stop writes and leave new progress recoverable.
written = decode(files[path])
written.next_id = written.next_id + 1
files[path] = encode(written)
durable = files[path]
local before_encodes = encodes
current:award({ kind = 'exp', amount = 7 }, 221)
equal(manager:checkpoint(250, true), false, 'Changed data stops the optimized checkpoint')
equal(files[path], durable, 'A conflicting file is never overwritten')
equal(encodes, before_encodes, 'Conflict detection does not encode an unsaveable session')
equal(manager:current().session_exp, 207, 'Unsaved current totals remain in memory')
equal(manager:new_session(251), nil, 'Reset cannot discard an unsaved conflicting session')

json.encode, json.decode = encode, decode
local reloaded = sessions.new('serialized.json', options)
current = reloaded:select(snapshot, 10000, { retention = 10 })
current:observe(snapshot, 10000)
equal(current:view(10000).session_exp, 200, 'Reload resumes the durable EXP without offline gains')
equal(current:view(10000).farming.total, 3, 'Reload resumes the durable farming totals')
local reset = assert(reloaded:new_session(10001))
equal(reset:view(10001).session_exp, 0, 'Reset still starts a fresh EXP session')
equal(reset:view(10001).farming.total, 0, 'Reset still starts a fresh farming session')
local reloaded_again = sessions.new('serialized.json', options)
current = reloaded_again:select(snapshot, 20000, { retention = 2 })
equal(#reloaded_again:list(), 2, 'Retention still trims archived records')
equal(reloaded_again:current().active, true, 'Retention keeps the resumed current record')

files[path] = '{broken'
durable = files[path]
equal(reloaded_again:checkpoint(20030, true), false, 'Malformed outside changes stop the fast path')
equal(files[path], durable, 'Malformed data is kept unchanged')
return { count = checks }
