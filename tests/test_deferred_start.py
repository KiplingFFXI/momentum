"""Exercise startup without preloading Momentum's runtime dependencies."""
from pathlib import Path
import tempfile
import unittest
import run

ZONE_HELPER = """
    local function zone_event(id, zone, utc)
        local bytes = MOCK.bytes(140)
        MOCK.put(bytes, 4, 4, id or MOCK.player.server_id)
        MOCK.put(bytes, 48, 2, zone or MOCK.player.zone)
        MOCK.put(bytes, 56, 4, utc or 1730000000)
        return MOCK.packet(0x00A, bytes)
    end
"""

class DeferredStartTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='momentum_deferred_')
        self.lua = run.runtime(self.work.name)

    def tearDown(self):
        self.work.cleanup()

    def execute(self, text):
        self.lua.execute(text)

    def test_manual_load_waits_then_starts_once(self):
        self.execute("""
            dofile(ADDON_DIR .. '/momentum.lua')
            assert(MOMENTUM_TEST == nil)
            assert(package.loaded.settings == nil)
            MOCK.fire('load')
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 2.75
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST == nil)
            MOCK.now = 3
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST.state.resources_ready)
            local app = MOMENTUM_TEST
            local settings = app.settings()
            MOCK.fire('load')
            MOCK.now = 10
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST == app and app.settings() == settings)
        """)

    def test_render_and_offscreen_callbacks_cannot_activate(self):
        self.execute("""
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            for i = 1, 30 do
                MOCK.now = i
                MOCK.fire('d3d_beginscene', false)
                MOCK.fire('d3d_present')
            end
            assert(MOMENTUM_TEST == nil)
            assert(package.loaded['ui.fonts'] == nil)
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 33
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST.state.resources_ready)
        """)

    def test_identity_and_zone_changes_restart_delay(self):
        self.execute("""
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 2.5
            MOCK.player.server_id = 1002
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 3
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST == nil)
            MOCK.now = 5
            MOCK.player.zone = 103
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 7.75
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST == nil)
            MOCK.now = 8
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST.state.resources_ready)
        """)

    def test_clock_rollback_restarts_delay(self):
        self.execute("""
            MOCK.now = 20
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 1
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 3.75
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST == nil)
            MOCK.now = 4
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST.state.resources_ready)
        """)

    def test_invalid_character_data_waits(self):
        self.execute("""
            local get_entity = GetPlayerEntity
            GetPlayerEntity = function() return { ServerId = 9999 } end
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 10
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST == nil)
            GetPlayerEntity = get_entity
            MOCK.player.main_level = 0
            MOCK.now = 11
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST == nil)
            MOCK.player.main_level = 50
            MOCK.player.zone = 0
            MOCK.now = 12
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST == nil)
            MOCK.player.zone = 102
            MOCK.now = 13
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 16
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST.state.resources_ready)
        """)

    def test_locked_atlas_waits_without_losing_commands(self):
        self.execute("""
            local imgui = require('imgui')
            local old = imgui.GetIO
            local atlas = { Locked = true }
            imgui.GetIO = function()
                local result = old()
                result.Fonts = atlas
                return result
            end
            local registrations = 0
            imgui.AddFontFromFileTTF = function() registrations = registrations + 1; return 'face' end
            local exists = ashita.fs.exists
            ashita.fs.exists = function(path) return path:match('%.ttf$') ~= nil or exists(path) end
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            MOCK.fire('command', {command='/momentum hide'})
            MOCK.fire('command', {command='/momentum free'})
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 3
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST ~= nil and not MOMENTUM_TEST.state.resources_ready)
            assert(registrations == 0)
            atlas.Locked = false
            for i = 1, 4 do
                MOCK.now = MOCK.now + 0.25
                MOCK.fire('d3d_beginscene', true)
            end
            assert(MOMENTUM_TEST.state.resources_ready)
            assert(registrations == 6)
            MOCK.fire('d3d_present')
            assert(MOMENTUM_TEST.state.hidden)
            assert(not MOMENTUM_TEST.settings().bar.docked)
            for i = 1, 10 do MOCK.fire('d3d_beginscene', true) end
            assert(registrations == 6)
        """)

    def test_zone_clock_keeps_original_receipt_time_without_status_packet(self):
        self.execute("""
            MOCK.login_status = 0
            MOCK.player.zone = 185
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            local bytes = MOCK.bytes(140)
            MOCK.put(bytes, 4, 4, MOCK.player.server_id)
            MOCK.put(bytes, 48, 2, MOCK.player.zone)
            MOCK.put(bytes, 56, 4, 1730000000)
            local event = MOCK.packet(0x00A, bytes)
            MOCK.fire('packet_in', event)
            event.data = 'changed receive event'
            event.data_raw = nil
            MOCK.login_status = 2
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 3
            MOCK.fire('d3d_beginscene', true)
            local app = MOMENTUM_TEST
            assert(app.state.resources_ready and app.state.snapshot.valid)
            assert(app.dynamis.observer:utc(MOCK.now) == 1730000003)
            assert(app.settings().style.font == 'Segoe UI')
        """)

    def test_polling_is_bounded_and_stops_after_activation(self):
        self.execute("""
            local original = AshitaCore.GetMemoryManager
            local reads = 0
            AshitaCore.GetMemoryManager = function(...)
                reads = reads + 1
                return original(...)
            end
            MOCK.login_status = 0
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            for i = 0, 999 do
                MOCK.now = i / 1000
                MOCK.fire('d3d_beginscene', true)
            end
            assert(reads <= 5)
            MOCK.login_status = 2
            MOCK.now = 1
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 4
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST.state.resources_ready)
            local loaded_reads = reads
            for i = 1, 100 do
                MOCK.now = MOCK.now + 0.25
                MOCK.fire('d3d_beginscene', true)
            end
            assert(reads == loaded_reads)
        """)

    def test_pending_commands_keep_order_and_execute_once(self):
        self.execute("""
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            for _, text in ipairs({
                '/momentum hide', '/momentum show', '/momentum free',
                '/momentum dock top', '/momentum dock bottom',
                '/momentum unlock', '/momentum lock',
                '/momentum divider first', '/momentum divider second', '/momentum preview',
            }) do
                local event = { command = text }
                MOCK.fire('command', event)
                assert(event.blocked)
            end
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 10)
            assert(package.loaded.settings == nil and MOMENTUM_TEST == nil)
            MOCK.finish_startup()
            local app = MOMENTUM_TEST
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 10)
            MOCK.fire('d3d_present')
            assert(not app.state.hidden)
            assert(app.settings().bar.docked and app.settings().bar.anchor == 'bottom')
            assert(app.settings().bar.locked)
            assert(app.settings().display.divider == 'second')
            assert(app.settings().preview.show)
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 0)
            for i = 1, 10 do MOCK.fire('d3d_beginscene', true) end
            assert(app.settings().preview.show, 'Queued preview must not run twice')
            assert(#MOCK.commands == 0)
        """)

    def test_new_commands_wait_behind_older_commands_while_atlas_is_locked(self):
        self.execute("""
            local imgui = require('imgui')
            local get_io = imgui.GetIO
            local atlas = { Locked = true }
            imgui.GetIO = function()
                local result = get_io()
                result.Fonts = atlas
                return result
            end
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            MOCK.fire('command', { command = '/momentum hide' })
            MOCK.finish_startup()
            assert(MOMENTUM_TEST ~= nil and not MOMENTUM_TEST.state.resources_ready)
            MOCK.fire('command', { command = '/momentum show' })
            MOCK.fire('command', { command = '/momentum preview' })
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 3)
            assert(not MOMENTUM_TEST.settings().preview.show)
            atlas.Locked = false
            for i = 1, 4 do
                MOCK.now = MOCK.now + 0.25
                MOCK.fire('d3d_beginscene', true)
            end
            assert(MOMENTUM_TEST.state.resources_ready)
            MOCK.fire('d3d_present')
            assert(not MOMENTUM_TEST.state.hidden, 'The newer show command must follow the older hide command')
            assert(MOMENTUM_TEST.settings().preview.show)
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 0)
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST.settings().preview.show, 'Queued commands execute once')
        """)

    def test_resource_retry_keeps_pending_commands(self):
        self.execute("""
            local fonts = require('ui.fonts')
            local load_fonts, fail = fonts.load, true
            fonts.load = function()
                if fail then error('Test font startup failure') end
                return load_fonts()
            end
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            MOCK.fire('command', { command = '/momentum hide' })
            MOCK.fire('command', { command = '/momentum free' })
            MOCK.fire('command', { command = '/momentum preview' })
            MOCK.finish_startup()
            local app = MOMENTUM_TEST
            assert(not app.state.resources_ready and app.state.startup_failed)
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 3)
            assert(not app.settings().preview.show)
            fail = false
            MOCK.fire('command', { command = '/momentum' })
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 4)
            assert(not app.state.resources_ready)
            for i = 1, 4 do
                MOCK.now = MOCK.now + 0.25
                MOCK.fire('d3d_beginscene', true)
            end
            assert(app.state.resources_ready)
            MOCK.fire('d3d_present')
            assert(app.state.hidden and not app.settings().bar.docked)
            assert(app.settings().preview.show and app.settings().window.open)
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 0)
            MOCK.fire('d3d_beginscene', true)
            assert(app.settings().preview.show and app.settings().window.open)
        """)

    def test_pending_command_count_and_size_are_bounded(self):
        self.execute("""
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            for _, value in ipairs({ '/momentumx hide', '/other momentum', 123 }) do
                local event = { command = value }
                MOCK.fire('command', event)
                assert(not event.blocked)
            end
            local prefix = '/momentum hide'
            local oversized = { command = prefix .. string.rep(' ', 1025 - #prefix) }
            MOCK.fire('command', oversized)
            assert(oversized.blocked)
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 0)
            local limit = { command = prefix .. string.rep(' ', 1024 - #prefix) }
            MOCK.fire('command', limit)
            assert(limit.blocked)
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 1)
            for i = 1, 31 do MOCK.fire('command', { command = '/momentum preview' }) end
            local overflow = { command = '/momentum show' }
            MOCK.fire('command', overflow)
            assert(overflow.blocked)
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 32)
            MOCK.finish_startup()
            MOCK.fire('d3d_present')
            assert(MOMENTUM_TEST.state.hidden, 'The overflow command must not replace accepted commands')
            assert(MOMENTUM_TEST.settings().preview.show, 'All 31 accepted toggles must execute')
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 0)
        """)

    def test_blocked_or_injected_packets_cannot_replace_zone_or_reset_wait(self):
        self.execute(ZONE_HELPER + """
            MOCK.player.zone = 185
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            MOCK.fire('packet_in', zone_event())
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 2
            for _, flag in ipairs({ 'blocked', 'blocked_original', 'injected', 'is_injected' }) do
                for _, id in ipairs({ 0x00A, 0x00B }) do
                    local event = zone_event(9999, 186, 1740000000)
                    event.id, event[flag] = id, true
                    MOCK.fire('packet_in', event)
                    local boot = MOMENTUM_BOOTSTRAP_TEST.inspect()
                    assert(boot.has_zone_packet and boot.stable_since == 0)
                end
            end
            MOCK.now = 3
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST.state.snapshot.valid)
            assert(MOMENTUM_TEST.dynamis.observer:utc(MOCK.now) == 1730000003)
        """)

    def test_malformed_zone_packets_cannot_seed_a_server_clock(self):
        self.execute(ZONE_HELPER + """
            MOCK.player.zone = 185
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            local malformed = {
                function(event) event.data = nil end,
                function(event) event.size = nil end,
                function(event) event.size = 0 / 0 end,
                function(event) event.size = math.huge end,
                function(event) event.size = 59 end,
                function(event) event.size = 60.5 end,
                function(event) event.size = 513; event.data = string.rep('x', 513) end,
                function(event) event.size = #event.data + 1 end,
                function(event) event.data = event.data:sub(1, 59) end,
                function(event) event.data = zone_event(0).data end,
                function(event) event.data = zone_event(nil, 0).data end,
            }
            for _, corrupt in ipairs(malformed) do
                MOCK.fire('packet_in', zone_event())
                assert(MOMENTUM_BOOTSTRAP_TEST.inspect().has_zone_packet)
                local event = zone_event()
                corrupt(event)
                MOCK.fire('packet_in', event)
                assert(not MOMENTUM_BOOTSTRAP_TEST.inspect().has_zone_packet)
            end
            MOCK.finish_startup()
            assert(MOMENTUM_TEST.state.snapshot.valid)
            assert(MOMENTUM_TEST.dynamis.observer.server_utc == nil)
        """)

    def test_logout_clears_captured_zone_and_restarts_full_wait(self):
        self.execute(ZONE_HELPER + """
            MOCK.player.zone = 185
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            MOCK.fire('packet_in', zone_event())
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 2.75
            MOCK.login_status = 0
            local logout = MOCK.bytes(8)
            MOCK.put(logout, 4, 1, 1)
            MOCK.fire('packet_in', MOCK.packet(0x00B, logout))
            local boot = MOMENTUM_BOOTSTRAP_TEST.inspect()
            assert(not boot.has_zone_packet and boot.stable_since == nil)
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 50
            MOCK.login_status = 2
            MOCK.fire('d3d_beginscene', true)
            MOCK.now = 52.75
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST == nil)
            MOCK.now = 53
            MOCK.fire('d3d_beginscene', true)
            assert(MOMENTUM_TEST.state.snapshot.valid)
            assert(MOMENTUM_TEST.dynamis.observer.server_utc == nil)
        """)

    def test_placement_commands_only_measure_fonts_during_present(self):
        self.execute("""
            MOCK.chat = nil
            local imgui = require('imgui')
            local push_font, in_ui, pushes = imgui.PushFont, false, 0
            imgui.PushFont = function(...)
                assert(in_ui, 'Placement must wait for the UI frame before pushing fonts')
                pushes = pushes + 1
                return push_font(...)
            end
            local function present()
                in_ui = true
                MOCK.fire('d3d_present')
                in_ui = false
                assert(not MOMENTUM_TEST.state.broken)
            end
            dofile(ADDON_DIR .. '/momentum.lua')
            MOCK.fire('load')
            MOCK.fire('command', { command = '/momentum free' })
            MOCK.fire('command', { command = '/momentum dock top' })
            MOCK.finish_startup()
            local app = MOMENTUM_TEST
            assert(app.state.resources_ready and pushes == 0)
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 2)
            present()
            assert(pushes > 0 and app.settings().bar.anchor == 'top')
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 0)
            app.settings().bar.auto_width = true
            local previous = pushes
            MOCK.fire('command', { command = '/momentum "free"' })
            MOCK.fire('command', { command = '/momentum dock bottom' })
            MOCK.fire('d3d_beginscene', true)
            assert(pushes == previous and app.settings().bar.anchor == 'top')
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 2)
            present()
            assert(app.settings().bar.docked and app.settings().bar.anchor == 'bottom')
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 0)
        """)

    def test_unload_discards_ready_commands_before_present(self):
        self.execute("""
            MOCK.load_addon()
            local app = MOMENTUM_TEST
            MOCK.fire('command', { command = '/momentum free' })
            MOCK.fire('command', { command = '/momentum preview' })
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 2)
            MOCK.fire('unload')
            MOCK.fire('d3d_beginscene', true)
            MOCK.fire('d3d_present')
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 0)
            assert(app.settings().bar.docked and not app.settings().preview.show)
        """)

    def test_failed_queued_command_does_not_drop_following_commands(self):
        self.execute("""
            MOCK.load_addon()
            local app = MOMENTUM_TEST
            local hud = require('ui.hud')
            local place = hud.place
            hud.place = function() error('Test queued placement failure') end
            MOCK.fire('command', { command = '/momentum free' })
            MOCK.fire('command', { command = '/momentum divider next' })
            MOCK.fire('d3d_present')
            assert(app.state.broken)
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 1)
            hud.place = place
            MOCK.fire('d3d_present')
            assert(app.settings().display.divider == 'next')
            assert(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 0)
        """)

    def test_stale_zone_context_is_rejected_for_current_character(self):
        for player_id, zone in ((9999, 185), (1001, 186)):
            with self.subTest(player_id=player_id, zone=zone):
                self.lua = run.runtime(self.work.name)
                self.lua.globals().STALE_PLAYER_ID = player_id
                self.lua.globals().STALE_ZONE_ID = zone
                self.execute(ZONE_HELPER + """
                    MOCK.player.zone = 185
                    dofile(ADDON_DIR .. '/momentum.lua')
                    MOCK.fire('load')
                    MOCK.fire('packet_in', zone_event(STALE_PLAYER_ID, STALE_ZONE_ID))
                    assert(MOMENTUM_BOOTSTRAP_TEST.inspect().has_zone_packet)
                    MOCK.finish_startup()
                    assert(MOMENTUM_TEST.state.snapshot.valid)
                    assert(MOMENTUM_TEST.dynamis.observer.server_utc == nil)
                    assert(not MOMENTUM_BOOTSTRAP_TEST.inspect().has_zone_packet)
                """)

if __name__ == '__main__':
    unittest.main(verbosity=2)
