local count = 0
local function equal(actual, expected, label)
    count = count + 1
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local store = require('core.file_store')
local read, reads = store.read, 0
store.read = function(path)
    if path:match('profiles%.json$') then reads = reads + 1 end
    return read(path)
end
require('ui.hud').draw = function() return false end
require('ui.settings_window').draw = function() return false end
dofile(ADDON_DIR .. '/momentum.lua')
MOCK.fire('load')
local app = MOMENTUM_TEST
local names = app.services.profile_names()
equal(reads, 1, 'First profile list reads the file')
for _ = 1, 120 do equal(app.services.profile_names(), names, 'Idle profile list reuses its result') end
equal(reads, 1, 'Stable frames do not reopen the profile file')
equal(app.services.save_profile('First'), true, 'Save still writes immediately')
equal(app.services.profile_names()[1], 'First', 'Save refreshes the profile list immediately')
local after_save = reads
app.services.profile_names()
equal(reads, after_save, 'Saved names also stay cached')
local path = MOCK_INSTALL_PATH .. '/config/addons/momentum/profiles.json'
equal(store.write(path, { External = require('ui.profiles').capture(app.settings()) }), true, 'External edit fixture')
equal(app.services.profile_names()[1], 'First', 'Ordinary frames retain the bounded cache')
equal(app.services.profile_names(true)[1], 'External', 'Explicit actions refresh names before replacing')
equal(store.write(path, { Later = {} }), true, 'Later external edit fixture')
MOCK.now = MOCK.now + 1
equal(app.services.profile_names()[1], 'Later', 'External profile edits appear within one second')
equal(app.services.delete_profile('Later'), true, 'Delete still writes immediately')
equal(#app.services.profile_names(), 0, 'Delete refreshes the list immediately')
equal(store.write(path, { Backward = {} }), true, 'Backward clock fixture')
MOCK.now = MOCK.now - 1
equal(app.services.profile_names()[1], 'Backward', 'Backward clock refreshes names')
local file = assert(io.open(path, 'wb')); file:write('{broken'); file:close()
MOCK.now = MOCK.now + 1
equal(#app.services.profile_names(), 0, 'Unreadable list stays empty')
equal(type(app.services.profile_error), 'string', 'Unreadable profile error remains available')
local failed_reads = reads
for _ = 1, 120 do app.services.profile_names() end
equal(reads, failed_reads, 'Unreadable profile file is not retried each frame')
equal(app.services.save_profile('Retry'), false, 'Saving cannot replace malformed data')
app.services.profile_names()
equal(reads, failed_reads + 2, 'A user action refreshes errors without waiting')
equal(store.write(path, { Repaired = {} }), true, 'Repair fixture')
MOCK.now = MOCK.now + 1
equal(app.services.profile_names()[1], 'Repaired', 'Automatic refresh recovers after repair')
equal(app.services.profile_error, nil, 'Recovered list clears its error')
MOCK.fire('unload')
equal(#MOCK.commands, 0, 'No gameplay commands')
return { count = count }
