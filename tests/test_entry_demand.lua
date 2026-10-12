local count = 0
local function equal(actual, expected, why)
    count = count + 1
    assert(actual == expected, why .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function command(text) MOCK.fire('command', { command = text }) end
local function frames(total)
    for _ = 1, total do MOCK.imgui_calls = {}; MOCK.frame(1 / 60) end
end
local function battle(amount)
    local bytes = MOCK.bytes(28)
    MOCK.put(bytes, 4, 4, MOCK.player.server_id); MOCK.put(bytes, 8, 4, MOCK.player.server_id)
    MOCK.put(bytes, 16, 4, amount); MOCK.put(bytes, 24, 2, 8)
    return MOCK.packet(0x02D, bytes)
end
local player, tracker, rings = require('core.player'), require('core.tracker'), require('core.rings')
local file_store, rules = require('core.file_store'), require('data.phoenix_rules')
local reads, views, scans, writes, hud_draws, window_draws = 0, 0, 0, 0, 0, 0
local read, new, write = player.read, tracker.new, file_store.write
player.read = function(...) reads = reads + 1; return read(...) end
player.utc = function() return 1800000000 + math.floor(MOCK.now) end
tracker.new = function(...)
    local instance = new(...)
    local view = instance.view
    instance.view = function(...) views = views + 1; return view(...) end
    return instance
end
file_store.write = function(...) writes = writes + 1; return write(...) end
local ready_at, last_ring_utc = 0, nil
rings.read = function(utc)
    scans, last_ring_utc = scans + 1, utc
    local remaining = math.max(0, ready_at - MOCK.now)
    return { available = true, entries = { { id = 15762, key = '0:1:15762', name = 'Empress Band',
        charges = 3, max_charges = 7, recast = remaining, ready = remaining == 0 } } }
end
local details_open, shown_rings = false, nil
require('ui.hud').draw = function() hud_draws = hud_draws + 1; return false end
require('ui.settings_window').draw = function(s, view, services)
    window_draws = window_draws + 1
    if s.window.tab == 'Details' then shown_rings = services.rings_visible(details_open) end
    return false
end
dofile(ADDON_DIR .. '/momentum.lua'); MOCK.fire('load')
local app, settings = MOMENTUM_TEST, MOMENTUM_TEST.settings()
equal(scans, 0, 'Default unused rings do not scan inventory at load')
MOCK.frame(0)
local function hidden_frames(label)
    local before_reads, before_views, before_hud = reads, views, hud_draws
    MOCK.chat_reads = 0
    frames(120)
    equal(reads > before_reads, true, label .. ': player polling continues')
    equal(views - before_views, reads - before_reads, label .. ': only notification samples build views')
    equal(hud_draws, before_hud, label .. ': no HUD draw')
    equal(MOCK.chat_reads, 0, label .. ': native chat is not read')
    equal(app.state.broken, false, label .. ': render remains healthy')
end
command('/momentum hide'); hidden_frames('Manually hidden')
command('/momentum show'); MOCK.player.status = 4; hidden_frames('Event hidden')
MOCK.player.status = 0; MOCK.typing = true; hidden_frames('Typing hidden')
MOCK.typing = false; settings.tracking.hide_idle = true; hidden_frames('Idle hidden')
settings.tracking.hide_idle = false
command('/momentum hide')
local previous_reads = reads
MOCK.fire('packet_in', battle(123))
equal(reads, previous_reads + 1, 'Own reward takes an immediate snapshot while hidden')
equal(app.tracker().session_exp, 123, 'Hidden collection retains reward')
local previous_writes = writes
MOCK.frame(31)
equal(writes > previous_writes, true, 'Scheduled session save continues while hidden')
settings.alerts.events.level.visual = true
MOCK.frame(0.25)
MOCK.player.main_level, MOCK.player.exp_needed = 51, rules.tnl[51]
MOCK.frame(0.25)
equal(app.notifications:view(MOCK.now).id, 'level', 'Enabled notification still fires while hidden')
local sound, plays = require('core.sound'), 0
local play = sound.play
sound.play = function() plays = plays + 1; return true end
settings.alerts.food_enabled, MOCK.player.buffs = true, { 251 }
app.sample(MOCK.now)
local food_end = MOCK.bytes(28)
MOCK.put(food_end, 4, 4, MOCK.player.server_id); MOCK.put(food_end, 8, 4, MOCK.player.server_id)
MOCK.put(food_end, 12, 4, 251); MOCK.put(food_end, 24, 2, 206)
MOCK.fire('packet_in', MOCK.packet(0x029, food_end)); MOCK.frame(0.01)
equal(plays, 1, 'Food-end sound still plays while the HUD is hidden')
sound.play = play
settings.alerts.food_enabled, MOCK.player.buffs = false, {}
app.sample(MOCK.now)
settings.window.open = true
local before = window_draws
MOCK.frame(0.01)
equal(window_draws, before + 1, 'Settings still draw while HUD is manually hidden')
equal(MOCK.chat_reads > 0, true, 'Open settings retain native preview context')
settings.window.open = false; settings.preview.show = true
before = hud_draws; MOCK.frame(0.01)
equal(hud_draws, before + 1, 'Explicit sample preview still overrides manual hiding')
settings.preview.show = false; command('/momentum show')
equal(scans, 0, 'No ring scans during unrelated tracking and hidden UI work')

MOCK.now = math.floor(MOCK.now) + 0.95
app.sample(MOCK.now); app.state.sampled = MOCK.now
local snapshot_utc = app.state.snapshot.utc
settings.display.enabled.ring = true
ready_at = MOCK.now + 10
previous_reads = reads
MOCK.frame(0.1)
equal(reads, previous_reads, 'Activation fixture stays between player samples')
equal(scans, 1, 'Enabling ring readout requests an immediate inventory read')
equal(last_ring_utc, snapshot_utc + 1, 'Activation uses current client UTC rather than stale snapshot time')
local previous_scans = scans
MOCK.frame(0.01)
equal(scans, previous_scans, 'Visible ring readout keeps one-second cadence')
settings.display.enabled.ring = false
MOCK.frame(0.01)
equal(app.state.rings, nil, 'Unused ring snapshot is discarded')
frames(90)
equal(scans, previous_scans, 'Disabled ring readout stops optional inventory work')
settings.display.enabled.ring = true
MOCK.frame(0.01)
equal(scans, previous_scans + 1, 'Readout reactivation gets fresh inventory')
settings.display.enabled.ring = false; MOCK.frame(0.01)
settings.window.open, settings.window.tab, details_open = true, 'Details', false
previous_scans = scans
MOCK.frame(0.01)
equal(scans, previous_scans, 'Collapsed ring details do not request inventory')
details_open = true; MOCK.frame(0.01)
equal(scans, previous_scans + 1, 'Opening ring details requests inventory immediately')
equal(shown_rings.available, true, 'Opening details receives fresh data in the same draw')
MOCK.frame(0.01)
equal(scans, previous_scans + 1, 'Open details do not rescan every frame')
details_open = false; MOCK.frame(0.01)
frames(90)
equal(scans, previous_scans + 1, 'Closing ring details stops optional scans')
details_open = true; MOCK.frame(0.01)
previous_scans = scans
settings.window.tab = 'Display'; frames(90)
equal(scans, previous_scans, 'Leaving Details clears its transient ring demand')
settings.window.open = false

command('/momentum hide')
local alert = settings.alerts.events.ring_ready
alert.visual, alert.cooldown = true, 0
ready_at = MOCK.now
MOCK.frame(0.25)
equal(scans, previous_scans + 1, 'Ring-ready alert monitors inventory even with hidden HUD')
local notice = app.notifications:view(MOCK.now)
equal(notice and notice.id == 'ring_ready' or false, false, 'Initial already-ready ring baseline is silent')
ready_at = MOCK.now + 2
MOCK.frame(1.1)
MOCK.frame(1.1)
equal(app.notifications:view(MOCK.now).id, 'ring_ready', 'Observed cooldown-to-ready transition alerts while hidden')
alert.visual = false; MOCK.frame(0.25)
previous_scans = scans
frames(90)
equal(scans, previous_scans, 'Disabling last ring consumer stops scans even while hidden')
alert.visual = true; MOCK.frame(0.25)
equal(scans, previous_scans + 1, 'Alert reactivation reads current inventory')
equal(#app.notifications.queue, 0, 'Alert reactivation does not queue a stale ready transition')

ready_at = MOCK.now + 2
MOCK.frame(1.1)
local zone = MOCK.bytes(12); MOCK.put(zone, 4, 4, MOCK.player.server_id)
MOCK.fire('packet_in', MOCK.packet(0x00A, zone))
previous_scans = scans
MOCK.frame(0.25)
equal(scans, previous_scans, 'Zoning does not read rings from an invalid snapshot')
MOCK.player.zone = 103
ready_at = MOCK.now
MOCK.fire('packet_in', MOCK.packet(0x061, MOCK.bytes(96)))
MOCK.frame(0.25)
equal(scans, previous_scans + 1, 'Returning from zoning refreshes ring inventory immediately')
notice = app.notifications:view(MOCK.now)
equal(notice and notice.id == 'ring_ready' or false, false, 'New-zone first ring baseline is silent')
previous_scans = scans
MOCK.player.server_id = 2002
MOCK.frame(0.25)
equal(scans, previous_scans + 1, 'Character identity change refreshes inventory')
notice = app.notifications:view(MOCK.now)
equal(notice and notice.id == 'ring_ready' or false, false, 'New-character first ring baseline is silent')
local fresh = require('ui.defaults').make()
MOCK.settings.switch_character(fresh)
equal(app.state.rings_details, nil, 'Settings reload clears old details demand')
previous_scans = scans
MOCK.frame(0.25)
equal(scans, previous_scans, 'New defaults do not inherit previous character ring demand')
MOCK.fire('unload')
equal(#MOCK.commands, 0, 'Demand optimizations send no gameplay commands')
return { count = count }
