local count = 0
local function equal(actual, expected, label)
    count = count + 1
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function command(text) MOCK.fire('command', { command = text }) end
local function battle(amount, actor, target, message)
    local bytes = MOCK.bytes(28)
    MOCK.put(bytes, 4, 4, actor or MOCK.player.server_id)
    MOCK.put(bytes, 8, 4, target or actor or MOCK.player.server_id)
    MOCK.put(bytes, 16, 4, amount)
    MOCK.put(bytes, 24, 2, message or 8)
    return MOCK.packet(0x02D, bytes)
end
local function action(actor, category, message, amount)
    local bytes = MOCK.bytes(40)
    local function bits(offset, length, value)
        for i = 0, length - 1 do
            local at = math.floor((offset + i) / 8)
            bytes[at] = bytes[at] + math.floor(value / 2 ^ i) % 2 * 2 ^ ((offset + i) % 8)
        end
    end
    bits(40, 32, actor or MOCK.player.server_id); bits(72, 6, 1); bits(82, 4, category or 5)
    bits(86, 32, 4096); bits(150, 32, actor or MOCK.player.server_id); bits(182, 4, 1)
    bits(213, 17, amount or 0); bits(230, 10, message or 105)
    return MOCK.packet(0x028, bytes)
end
local player = require('core.player')
local read, reads = player.read, 0
player.read = function() reads = reads + 1; return read() end
local mkdir, directories = ashita.fs.create_dir, 0
ashita.fs.create_dir = function(...) directories = directories + 1; return mkdir(...) end
local draw_settings
require('ui.hud').draw = function() return false end
require('ui.settings_window').draw = function(settings, view, services)
    if draw_settings then return draw_settings(settings, view, services) end
    return false
end
AshitaCore.GetResourceManager = function() return { GetItemById = function() return { Name = { 'Test food' } } end } end
MOCK.load_addon()
MOCK.fire('load')
local app = MOMENTUM_TEST
reads, directories = 0, 0
for _ = 1, 100 do MOCK.fire('packet_in', action(2002)) end
equal(reads, 0, 'Other players item packets do not trigger a snapshot')
for _ = 1, 100 do MOCK.fire('packet_in', action(1001, 1)) end
equal(reads, 0, 'Own non-item combat actions do not trigger a snapshot')
for _, event in ipairs({ battle(200, 2002), battle(200, 1001, 2002), battle(0), battle(200, nil, nil, 999) }) do
    MOCK.fire('packet_in', event)
end
equal(reads, 0, 'Unrelated reward messages do not trigger a snapshot')
for size = 0, 27 do
    local event = battle(200)
    event.data, event.size = event.data:sub(1, size), size
    MOCK.fire('packet_in', event)
end
equal(reads, 0, 'Truncated battle rewards do not trigger a snapshot')
local event = battle(200)
MOCK.fire('packet_in', event)
equal(reads, 1, 'Own reward still samples before collection')
equal(app.tracker().session_exp, 200, 'Own reward counted')
MOCK.fire('packet_in', event)
equal(app.tracker().session_exp, 200, 'Reward identity remains deduplicated')
MOCK.fire('packet_in', action(1001, 5, 105, 750))
equal(app.tracker().session_exp, 950, 'Own EXP item remains collected')
MOCK.fire('packet_in', action(1001, 5, 28, 0))
equal(app.phoenix.pending_food, 'Test food', 'Own completed item use still reaches buff-name observation')
equal(directories, 0, 'Ordinary rewards and samples do not check the directory')
local before = reads
MOCK.player.server_id = 2002
MOCK.fire('packet_in', battle(100, 2002))
equal(reads, before + 1, 'Fresh client identity is used before stale cached identity')
equal(app.tracker().identity.id, 2002, 'Reward snapshot switches to current character session')
equal(app.tracker().session_exp, 100, 'First reward for a new coherent character is retained')
MOCK.fire('packet_in', battle(999, 1001))
equal(app.tracker().session_exp, 100, 'Previous character packets cannot add rewards')
MOCK.player.exp_needed = 900
MOCK.fire('packet_in', battle(200, 2002))
equal(app.tracker().session_exp, 100, 'Mixed level and TNL snapshot does not collect reward')
MOCK.player.exp_needed = 7800
MOCK.fire('packet_in', battle(200, 2002))
equal(app.tracker().session_exp, 300, 'Coherent snapshot resumes collection')
local dispatched = 0
local checkpoint = app.sessions.checkpoint
app.sessions.checkpoint = function(self, ...) dispatched = dispatched + 1; return checkpoint(self, ...) end
directories = 0
for _ = 1, 120 do MOCK.frame(1 / 60) end
equal(dispatched, 1, 'Stable frames dispatch checkpoint once to establish the schedule')
equal(directories, 0, 'Stable frames do not check session directories')
equal(app.state.broken, false, 'Optimized idle entry remains drawable')
MOCK.now = app.sessions.checkpoint_at
MOCK.frame(0)
equal(dispatched, 2, 'Due frame dispatches the scheduled checkpoint')
equal(directories > 0, true, 'Actual session writes still ensure the directory exists')

local history = require('ui.history')
local copy, root_copies = history.copy, 0
history.copy = function(value)
    if value == app.settings() then root_copies = root_copies + 1 end
    return copy(value)
end
app.settings().window.open = true
for _ = 1, 30 do MOCK.frame(1 / 60) end
equal(root_copies, 1, 'Idle open settings reuse one pre-edit snapshot')
local original = app.settings().display.divider
MOCK.mouse_down = true
draw_settings = function(s) s.display.divider = 'one'; return true end
MOCK.frame()
draw_settings = function(s) s.display.divider = 'two'; return true end
MOCK.frame()
draw_settings = function(s) s.display.divider = 'three'; return true end
MOCK.frame()
equal(root_copies, 1, 'Active gesture reuses its original undo snapshot')
draw_settings, MOCK.mouse_down = nil, false
MOCK.frame()
equal(app.state.before, nil, 'Released gesture completes')
app.services.undo()
equal(app.settings().display.divider, original, 'One undo restores the whole multi-frame gesture')
equal(app.services.can_undo(), false, 'Gesture creates only one undo entry')
MOCK.frame()
local baseline = app.state.edit_baseline
command('/momentum divider command')
equal(app.state.edit_baseline, nil, 'Programmatic edit invalidates reusable snapshot')
MOCK.frame()
equal(app.state.edit_baseline ~= baseline, true, 'Next frame seeds a new snapshot after command')
draw_settings = function(s) s.display.divider = 'widget'; return false end
MOCK.frame()
draw_settings = nil
app.services.undo()
equal(app.settings().display.divider, 'command', 'Equality fallback catches a widget that omitted changed flag')
app.services.undo()
equal(app.settings().display.divider, original, 'Previous programmatic edit remains independently undoable')
local save = MOCK.settings.save
MOCK.settings.save = function() error('Test save failure') end
draw_settings = function(s) s.display.divider = 'unsaved'; return true end
MOCK.frame()
draw_settings = nil
equal(app.state.dirty, true, 'Failed save keeps pending settings')
equal(app.services.can_undo(), true, 'Failed save retains original undo history')
MOCK.settings.save = save
app.services.undo()
equal(app.settings().display.divider, original, 'Failed saved edit can still be undone')
MOCK.frame(11)
equal(app.state.dirty, false, 'Failed settings save retries after delay')
MOCK.settings.save = function() return false end
command('/momentum divider rejected')
equal(app.state.dirty, true, 'Explicit save rejection keeps pending settings')
MOCK.settings.save = save
MOCK.frame(11)
equal(app.state.dirty, false, 'Explicit save rejection retries after delay')
app.settings().window.open = true
MOCK.frame()
app.services.shared(true)
equal(app.state.edit_baseline, nil, 'Shared layout change invalidates pre-edit snapshot')
app.services.shared(false)
MOCK.settings.switch_character(require('ui.defaults').make())
equal(app.state.edit_baseline, nil, 'Character settings reload invalidates pre-edit snapshot')
equal(app.services.can_undo(), false, 'Character settings reload clears old character history')
for i = 1, 10 do command('/momentum divider v' .. i) end
for _ = 1, 8 do app.services.undo() end
equal(app.settings().display.divider, 'v2', 'Eight latest undo entries remain available')
equal(app.services.can_undo(), false, 'Undo remains capped at eight entries')
MOCK.fire('unload')
equal(#MOCK.commands, 0, 'Performance changes send no gameplay commands')
return { count = count }
