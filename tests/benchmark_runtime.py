"""Compare bounded offline work counts; these are not live FPS measurements."""
import argparse
import json
from pathlib import Path
import tempfile
import zipfile

import run


COUNTERS = r'''
local metrics = { readout_builds = 0, text_measurements = 0, layout_arrangements = 0, player_reads = 0,
    tracker_views = 0, rate_calls = 0, bucket_scans = 0, bucket_visits = 0, ring_scans = 0, inventory_slot_reads = 0,
    chat_reads = 0, sorts = 0, directory_checks = 0, table_copies = 0, file_reads = 0, date_formats = 0 }
local memory = AshitaCore:GetMemoryManager()
local inventory = {
    GetContainerCountMax = function() return 80 end,
    GetContainerItem = function(_, bag, slot)
        metrics.inventory_slot_reads = metrics.inventory_slot_reads + 1
        if bag == 0 and slot == 0 then return { Id = 65535, Count = 100000 } end
        return { Id = 0, Count = 0 }
    end,
}
memory.GetInventory = function() return inventory end
AshitaCore.GetMemoryManager = function() return memory end
local imgui = require('imgui')
local readouts = require('ui.readouts')
local player = require('core.player')
local tracker = require('core.tracker')
local history = require('ui.history')
local rings, chat = require('core.rings'), require('core.chat')
local store, date = require('core.file_store'), os.date
local file_read = store.read
store.read = function(...) metrics.file_reads = metrics.file_reads + 1; return file_read(...) end
os.date = function(...) metrics.date_formats = metrics.date_formats + 1; return date(...) end
local ring_read, chat_read = rings.read, chat.read
rings.read = function(...) metrics.ring_scans = metrics.ring_scans + 1; return ring_read(...) end
chat.read = function(...) metrics.chat_reads = metrics.chat_reads + 1; return chat_read(...) end
local bucket_tables, original_pairs = setmetatable({}, { __mode = 'k' }), pairs
pairs = function(value)
    if not bucket_tables[value] then return original_pairs(value) end
    metrics.bucket_scans = metrics.bucket_scans + 1
    local iterator, state, key = original_pairs(value)
    return function(source, previous)
        local next_key, entry = iterator(source, previous)
        if next_key ~= nil then metrics.bucket_visits = metrics.bucket_visits + 1 end
        return next_key, entry
    end, state, key
end
local layout = require('ui.layout')
local arrange = layout.arrange
layout.arrange = function(...) metrics.layout_arrangements = metrics.layout_arrangements + 1; return arrange(...) end
local measure, build, read, new = imgui.CalcTextSize, readouts.build, player.read, tracker.new
imgui.CalcTextSize = function(...) metrics.text_measurements = metrics.text_measurements + 1; return measure(...) end
readouts.build = function(...) metrics.readout_builds = metrics.readout_builds + 1; return build(...) end
player.read = function(...) metrics.player_reads = metrics.player_reads + 1; return read(...) end
tracker.new = function(...)
    local value = new(...)
    local view, rate = value.view, value._rate
    value.view = function(...) bucket_tables[value.buckets] = true; metrics.tracker_views = metrics.tracker_views + 1; return view(...) end
    value._rate = function(...) metrics.rate_calls = metrics.rate_calls + 1; return rate(...) end
    return value
end
local sort, mkdir, copy = table.sort, ashita.fs.create_dir, history.copy
table.sort = function(...) metrics.sorts = metrics.sorts + 1; return sort(...) end
ashita.fs.create_dir = function(...) metrics.directory_checks = metrics.directory_checks + 1; return mkdir(...) end
history.copy = function(value)
    if type(value) == 'table' then metrics.table_copies = metrics.table_copies + 1 end
    return copy(value)
end
local function reset()
    for key in pairs(metrics) do metrics[key] = 0 end
end
'''

HUD = r'''
local defaults, hud = require('ui.defaults'), require('ui.hud')
local settings, view = defaults.make(), readouts.sample()
settings.bar.docked = CASE == 'docked-default'
settings.bar.auto_width = false
if CASE == 'narrow-grouped' then
    settings.bar.width, settings.display.groups_enabled = 300, true
    for id in pairs(settings.display.enabled) do settings.display.enabled[id] = true end
elseif CASE == 'countdown' or CASE == 'active-rates' then
    settings.display.enabled.chain_time = true
end
reset()
for frame = 1, 100 do
    MOCK.imgui_calls = {}
    if CASE == 'countdown' or CASE == 'active-rates' then view.chain_left = 11 - frame / 60 end
    if CASE == 'active-rates' then view.rate = 8500 * 2700 / (2700 + frame / 60) end
    hud.draw(settings, view, { now = frame / 60, chat = { x = 0, y = 500, width = 1070, height = 150 } })
end
metrics.frames = 100
assert(#MOCK.commands == 0, 'Benchmark sent a gameplay command')
return metrics
'''

ENTRY = r'''
MOCK.load_addon()
MOCK.fire('load')
local settings = MOMENTUM_TEST.settings()
local gil_case = CASE:find('entry-gil-', 1, true) == 1
if gil_case and not MOMENTUM_TEST.tracker().gil then return { unsupported = 1 } end
if gil_case then
    settings.display.order = { 'gil', 'gil_gained', 'gil_spent', 'gil_net', 'gil_rate' }
    for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true end
end
if CASE == 'entry-gil-active' then
    local bytes = MOCK.bytes(12)
    MOCK.put(bytes, 4, 4, 101000)
    MOCK.fire('packet_in', MOCK.packet(0x01E, bytes))
    MOCK.now = MOCK.now + 600
end
if CASE == 'entry-gil-paused' then MOCK.fire('command', { command = '/momentum pause' }) end
if CASE == 'entry-auto-layout-idle' then settings.display.auto_layout = true end
if CASE == 'entry-settings-idle' then settings.window.open = true end
if CASE == 'entry-profiles-idle' then settings.window.open, settings.window.tab = true, 'Profiles' end
if CASE == 'entry-history-idle' then settings.window.open, settings.window.tab = true, 'Session' end
if CASE == 'entry-hidden' then MOMENTUM_TEST.state.hidden = true end
if CASE == 'entry-event-hidden' then MOCK.player.status = 4 end
if CASE == 'entry-chat-hidden' or CASE == 'entry-chat-kept' or CASE == 'entry-chat-always' or CASE == 'entry-chat-free' then
    settings.visibility.mode = CASE == 'entry-chat-hidden' and 'chat' or CASE == 'entry-chat-always' and 'always' or 'keep'
    settings.bar.docked = CASE ~= 'entry-chat-free'
    MOCK.chat_retained, MOCK.chat, MOCK.chat_visible = MOCK.chat, nil, false
end
if CASE == 'entry-ring-alert' then settings.alerts.events.ring_ready.visual = true end
if CASE == 'entry-mature' or CASE == 'entry-hidden' or CASE == 'entry-event-hidden' then
    local current = MOMENTUM_TEST.tracker()
    MOCK.now, current.started = 4000, 2200
    current.buckets = {}
    for second = 0, 1800 do current.buckets[second + 1] = { second = second, exp = 10, lp = 5, net_exp = 8, net_lp = 5 } end
end
MOCK.frame(1 / 60)
if CASE == 'entry-history-idle' then
    for index = 1, 29 do assert(MOMENTUM_TEST.services.session_new('Session ' .. index)) end
    MOCK.frame(1 / 60)
end
reset()
if CASE == 'entry-gil-packets' or CASE == 'entry-gil-paused' or CASE == 'unrelated-inventory' then
    local bytes = MOCK.bytes(12)
    if CASE == 'unrelated-inventory' then MOCK.put(bytes, 9, 1, 1) end
    for index = 1, 100 do
        MOCK.put(bytes, 4, 4, 100000 + index)
        MOCK.fire('packet_in', MOCK.packet(0x01E, bytes))
    end
    metrics.packets = 100
    assert(metrics.player_reads == 0 and metrics.inventory_slot_reads == 0, 'Inventory packets triggered extra sampling')
    assert(metrics.table_copies == 0 and metrics.directory_checks == 0, 'Inventory packets copied settings or scanned folders')
    if gil_case then
        local wallet = MOMENTUM_TEST.tracker().gil:view(MOCK.now)
        assert(wallet.current == 100100, 'Latest packet balance was lost')
        assert(wallet.gained == (CASE == 'entry-gil-paused' and 0 or 100), 'Packet gain accounting changed')
    end
elseif CASE == 'unrelated-combat' then
    local bytes = MOCK.bytes(40)
    local function bits(offset, length, value)
        for index = 0, length - 1 do
            local key = math.floor((offset + index) / 8)
            bytes[key] = bytes[key] + math.floor(value / 2 ^ index) % 2 * 2 ^ ((offset + index) % 8)
        end
    end
    bits(40, 32, 2002)
    bits(72, 6, 1)
    bits(82, 4, 1)
    for index = 1, 100 do MOCK.fire('packet_in', MOCK.packet(0x028, bytes)) end
    metrics.packets = 100
else
    for frame = 1, 120 do
        MOCK.imgui_calls = {}
        MOCK.frame(1 / 60)
    end
    metrics.frames = 120
    if gil_case or CASE == 'entry-auto-layout-idle' then
        assert(metrics.inventory_slot_reads == 0, 'Known gil balance was polled again')
        assert(metrics.table_copies == 0 and metrics.directory_checks == 0, 'Idle tracking repeated setup work')
    end
end
for _, line in ipairs(MOCK.printed) do assert(not line:find('The bar stopped drawing', 1, true), line) end
assert(#MOCK.commands == 0, 'Benchmark sent a gameplay command')
return metrics
'''


def measure(addon):
    original = run.ADDON
    run.ADDON = addon
    rows = {}
    try:
        for case in ('docked-default', 'free-fixed-default', 'narrow-grouped', 'countdown', 'active-rates',
                     'entry-idle', 'entry-settings-idle', 'entry-profiles-idle', 'entry-history-idle',
                     'entry-mature', 'entry-hidden', 'entry-event-hidden',
                     'entry-chat-hidden', 'entry-chat-kept', 'entry-chat-always', 'entry-chat-free',
                     'entry-rings-unused', 'entry-ring-alert', 'unrelated-combat', 'unrelated-inventory',
                     'entry-gil-idle', 'entry-gil-active', 'entry-gil-paused', 'entry-gil-packets', 'entry-auto-layout-idle'):
            with tempfile.TemporaryDirectory(prefix='momentum_benchmark_') as folder:
                lua = run.runtime(folder)
                lua.globals().CASE = case
                fixture = ENTRY if case.startswith(('entry-', 'unrelated-')) else HUD
                rows[case] = dict(lua.execute(COUNTERS + fixture).items())
    finally:
        run.ADDON = original
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, help='Previously built Momentum ZIP')
    parser.add_argument('--out', type=Path, help='Optional JSON result file')
    args = parser.parse_args()
    result = {'kind': 'offline operation counts', 'current': measure(run.ADDON)}
    if args.baseline:
        with tempfile.TemporaryDirectory(prefix='momentum_baseline_') as folder:
            destination = Path(folder)
            with zipfile.ZipFile(args.baseline) as archive:
                for member in archive.infolist():
                    path = destination / member.filename
                    if not path.resolve().is_relative_to(destination) or not member.filename.startswith('momentum/'):
                        raise ValueError('Unexpected baseline archive path: ' + member.filename)
                archive.extractall(destination)
            result['baseline'] = measure(destination / 'momentum')
    text = json.dumps(result, indent=2, sort_keys=True)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    print(text)


if __name__ == '__main__':
    main()
