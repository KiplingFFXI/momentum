local rules = require('data.phoenix_rules')
local defaults = require('ui.defaults')
local copy = require('ui.history').copy
local checks = 0
local function equal(a, b, label)
    checks = checks + 1
    assert(a == b, label .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a))
end
local function reward(amount)
    local bytes = MOCK.bytes(28)
    MOCK.put(bytes, 4, 4, MOCK.player.server_id)
    MOCK.put(bytes, 8, 4, MOCK.player.server_id)
    MOCK.put(bytes, 16, 4, amount)
    MOCK.put(bytes, 24, 2, 8)
    return MOCK.packet(0x02D, bytes)
end
local function feed(sequence, penalty, pool)
    local message = table.concat({ 'MOM1', MOCK.player.server_id, MOCK.player.zone, MOCK.player.main_job,
        75, 50, sequence, 1800000000, 1, penalty, 15, 1, pool, 50, 600, 1 }, '|')
    local bytes = MOCK.bytes(23 + #message + 1)
    MOCK.put(bytes, 4, 1, 29)
    MOCK.put(bytes, 6, 2, MOCK.player.zone)
    for index, byte in ipairs({ string.byte('Momentum', 1, -1) }) do bytes[7 + index] = byte end
    for index = 1, #message do bytes[22 + index] = message:byte(index) end
    return MOCK.packet(0x017, bytes)
end
local function effect(effect_id, message)
    local bytes = MOCK.bytes(28)
    MOCK.put(bytes, 4, 4, MOCK.player.server_id)
    MOCK.put(bytes, 8, 4, MOCK.player.server_id)
    MOCK.put(bytes, 12, 4, effect_id)
    MOCK.put(bytes, 24, 2, message)
    return MOCK.packet(0x029, bytes)
end
local function plays()
    local count = 0
    for _, command in ipairs(MOCK.mci or {}) do if command:match('^play ') then count = count + 1 end end
    return count
end
local function load()
    MOCK.load_addon()
    MOCK.fire('load')
    return MOMENTUM_TEST
end
local app = load()
local started_at = MOCK.now
equal(app.state.award_ready, true, 'Initial coherent client state accepts rewards')
MOCK.now = started_at + 1
local received = reward(200)
MOCK.fire('packet_in', received)
MOCK.fire('packet_in', received)
equal(app.view(started_at + 1).session_exp, 200, 'Duplicate receive buffer counted once')
equal(app.view(started_at + 1).exp.recent3.count, 1, 'Recent samples exclude duplicate packet')
MOCK.player.exp = MOCK.player.exp + 200
MOCK.now = started_at + 2
app.sample(started_at + 2)
equal(app.view(started_at + 2).net_exp, 200, 'Reported award paired with retained progress')
equal(app.services.session_save('Evening session'), true, 'Named active session saved')
local initial_id = app.services.session_current().id
local path = MOCK_INSTALL_PATH .. '/config/addons/momentum/sessions-1001.json'
local file = assert(io.open(path, 'rb'))
equal(file:read('*a'):find('Evening session', 1, true) ~= nil, true, 'Per-character session file contains name')
file:close()

MOCK.now = started_at + 31
MOCK.fire('unload')
MOCK.settings_file = copy(app.settings())
MOCK.player.exp = MOCK.player.exp + 1000
MOCK.now = started_at + 10000
app = load()
started_at = MOCK.now - 10000
equal(app.services.session_current().id, initial_id, 'Reload resumes same saved session')
equal(app.services.session_current().resumed, true, 'Resume status exposed')
equal(app.view(MOCK.now).elapsed, 30, 'Reload excludes offline elapsed time')
equal(app.view(MOCK.now).session_exp, 200, 'Reload preserves reported rewards')
equal(app.view(MOCK.now).net_exp, 200, 'Reload does not infer missing EXP')
local post_reload = reward(75)
MOCK.fire('packet_in', post_reload)
MOCK.fire('packet_in', post_reload)
equal(app.view(MOCK.now).session_exp, 275, 'Fresh receive counted once after reload')

app.settings().alerts.events.level.visual = true
app.settings().alerts.events.level.cooldown = 0
app.sample(MOCK.now)
MOCK.player.main_job = 2
MOCK.player.main_level = 51
MOCK.player.exp_needed = rules.tnl[50]
MOCK.now = started_at + 10000.1
MOCK.fire('packet_in', reward(500))
equal(app.state.award_ready, false, 'Mixed job and EXP memory rejects reward assignment')
equal(app.view(MOCK.now).session_exp, 275, 'Mixed snapshot does not alter former job rewards')
equal(app.services.session_current().job, 1, 'Mixed snapshot retains former job session')
MOCK.player.exp_needed = rules.tnl[51]
MOCK.player.exp = 100
MOCK.now = started_at + 10000.2
MOCK.fire('packet_in', reward(100))
equal(app.state.award_ready, true, 'Coherent new job accepts reward')
equal(app.services.session_current().job, 2, 'New reward follows current coherent job')
equal(app.view(MOCK.now).session_exp, 100, 'New job excludes ambiguous transition reward')
equal(#app.notifications:take(MOCK.now), 0, 'Job transition does not create a level-up notification')
MOCK.player.main_job, MOCK.player.main_level = 1, 50
MOCK.player.exp_needed, MOCK.player.exp = rules.tnl[50], 7000
MOCK.now = started_at + 10001
app.sample(MOCK.now)
equal(app.view(MOCK.now).session_exp, 275, 'Returning job restores its own saved totals')
equal(app.view(MOCK.now).net_exp, 200, 'Returning job establishes a fresh EXP baseline')
equal(#app.services.session_list(), 2, 'History includes both jobs')

MOCK.file_replace_error = true
MOCK.now = started_at + 10002
equal(app.services.session_save('Cannot save'), false, 'Session save failure reaches entry service')
equal(app.services.session_current().name, 'Evening session', 'Failed rename preserves current name')
equal(app.services.session_problem() ~= nil, true, 'Session page can show save failure')
equal(app.services.session_new('Would lose progress'), false, 'Failed checkpoint blocks new session')
equal(app.view(MOCK.now).session_exp, 275, 'Failed new session keeps rewards')
MOCK.file_replace_error = false
local retried, retry_problem = app.services.session_save()
equal(retried, true, 'Explicit retry succeeds: ' .. tostring(retry_problem))
equal(app.services.session_problem(), nil, 'Successful retry clears error')

MOCK.now = started_at + 10003
MOCK.settings.switch_character(defaults.make())
equal(app.view(MOCK.now).valid, false, 'Character callback clears old progress immediately')
equal(app.services.session_current(), nil, 'Character callback detaches old session')
MOCK.player.server_id = 2002
MOCK.player.main_job, MOCK.player.main_level = 2, 30
MOCK.player.exp_needed, MOCK.player.exp = rules.tnl[30], 500
MOCK.now = started_at + 20000
app.sample(MOCK.now)
equal(app.view(MOCK.now).session_exp, 0, 'Another character starts independent totals')
equal(#app.services.session_list(), 1, 'History shows current character only')
equal(app.services.session_rename(initial_id, 'Wrong character'), false, 'Old selection cannot rename another character')
MOCK.settings.switch_character(defaults.make())
MOCK.player.server_id = 1001
MOCK.player.main_job, MOCK.player.main_level = 1, 50
MOCK.player.exp_needed, MOCK.player.exp = rules.tnl[50], 7000
MOCK.now = started_at + 30000
app.sample(MOCK.now)
equal(app.view(MOCK.now).session_exp, 275, 'First character resumes its own job')

local stats = AshitaCore:GetMemoryManager():GetPlayer()
-- The fixture's server reports and fallback clock share the same UTC second.
local original_time = os.time
os.time = function() return 1800000000 end
stats.GetJobLevel = function(_, id) return id == MOCK.player.main_job and 75 or 1 end
MOCK.player.main_level, MOCK.player.exp_needed = 50, rules.tnl[75]
MOCK.player.exp, MOCK.player.buffs = 20000, { 269, 249 }
for _, id in ipairs({ 'sync_change', 'dedication_low' }) do
    app.settings().alerts.events[id].visual = true
    app.settings().alerts.events[id].cooldown = 0
end
MOCK.now = started_at + 30001
app.sample(MOCK.now)
local first = feed(11, 37, 200)
MOCK.fire('packet_in', first)
equal(first.blocked, true, 'Accepted server status stays out of player chat')
equal(app.view(MOCK.now).sync_penalty, 37, 'Accepted status appears in combined view')
equal(app.view(MOCK.now).dedication_pool, 200, 'Server-only budget appears when confirmed')
app.notifications:take(MOCK.now)
MOCK.now = started_at + 30001.1
local second = feed(12, 50, 90)
MOCK.fire('packet_in', second)
local notices = app.notifications:take(MOCK.now)
equal(#notices, 2, 'Confirmed changes produce one notice each')
MOCK.now = started_at + 30001.3
app.sample(MOCK.now)
equal(#app.notifications:take(MOCK.now), 0, 'Next sample does not duplicate confirmed changes with zero cooldown')
local duplicate = feed(12, 50, 90)
MOCK.fire('packet_in', duplicate)
equal(duplicate.blocked, false, 'Replayed server status is not accepted')
equal(#app.notifications:take(MOCK.now), 0, 'Replayed status creates no notice')
MOCK.fire('packet_in', reward(50))
equal(app.view(MOCK.now).dedication_pool, nil, 'New reward invalidates stale bonus budget')
os.time = original_time
app.settings().alerts.food_enabled = true
app.settings().alerts.events.no_exp.sound = true
app.settings().alerts.events.no_exp.visual = true
app.settings().alerts.events.no_exp.file = 'FF VII Save.mp3'
app.settings().alerts.events.no_exp.cooldown = 0
MOCK.player.buffs = { 269, 249, 251 }
MOCK.now = started_at + 31000
app.sample(MOCK.now)
MOCK.fire('packet_in', effect(251, 206))
MOCK.fire('packet_in', effect(0, 37))
local played = plays()
MOCK.fire('d3d_present')
equal(plays() - played, 1, 'Food and event sounds share one automatic playback budget')
MOCK.player.buffs = { 269, 249 }
MOCK.now = started_at + 31001
app.sample(MOCK.now)
MOCK.player.buffs = { 269, 249, 251 }
MOCK.now = started_at + 31001.1
app.sample(MOCK.now)
MOCK.now = started_at + 31002
MOCK.fire('packet_in', effect(0, 37))
played = plays()
MOCK.fire('d3d_present')
equal(plays() - played, 1, 'New event can play after the shared interval')
MOCK.now = started_at + 31002.2
MOCK.fire('packet_in', effect(251, 206))
played = plays()
MOCK.fire('d3d_present')
equal(plays() - played, 0, 'Food cannot interrupt an event inside the shared interval')
MOCK.now = started_at + 31004
app.sample(MOCK.now)
MOCK.fire('packet_in', effect(0, 37))
app.services.session_pause(true)
played = plays()
MOCK.fire('d3d_present')
equal(plays() - played, 0, 'Quiet pause suppresses a sound queued just before pausing')
equal(app.view(MOCK.now).notice, nil, 'Quiet pause consumes the queued visual notice too')
app.services.session_pause(false)
MOCK.now = started_at + 31006
app.sample(MOCK.now)
MOCK.fire('packet_in', effect(0, 37))
MOCK.player.status = 4
played = plays()
MOCK.fire('d3d_present')
equal(plays() - played, 0, 'Entering an event suppresses a queued sound')
equal(app.view(MOCK.now).notice, nil, 'Entering an event consumes a queued visual notice')
MOCK.player.status = 0
MOCK.now = started_at + 31006.2
MOCK.fire('d3d_present')
equal(app.view(MOCK.now).notice, nil, 'Quiet notice is not replayed when the event ends')
app.services.session_pause(true)
played = plays()
equal(app.services.notification_test('no_exp'), true, 'Explicit notification test works while paused')
equal(plays() - played, 1, 'Explicit test sound bypasses the automatic quiet rule')
MOCK.fire('d3d_present')
equal(app.view(MOCK.now).notice.preview, true, 'Explicit visual preview survives quiet playback filtering')
equal(app.view(MOCK.now + 5).notice, nil, 'Explicit preview still expires')
equal(#MOCK.commands, 0, 'Integration issues no game commands')
MOCK.fire('d3d_present')
equal(app.state.broken, false, 'Integrated render remains valid')
return checks .. ' round-one entry checks'
