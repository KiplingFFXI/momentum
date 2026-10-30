"""Keep Farming records separate through real Ashita settings and session reloads."""
import json
from pathlib import Path
import tempfile
import unittest

from test_settings_client import client_runtime, load_entry, write_settings


HELPERS = """
    local generation = 100
    function farm_loot(quantity)
        local bytes = MOCK.bytes(28)
        MOCK.put(bytes,4,4,quantity); MOCK.put(bytes,16,2,4)
        MOCK.put(bytes,20,1,0); MOCK.put(bytes,24,4,generation)
        generation = generation + 1
        MOCK.fire('packet_in',MOCK.packet(0x0D2,bytes))
        bytes = MOCK.bytes(24)
        MOCK.put(bytes,4,4,MOCK.player.server_id); MOCK.put(bytes,20,1,0); MOCK.put(bytes,21,1,1)
        MOCK.fire('packet_in',MOCK.packet(0x0D3,bytes))
        MOCK.frame(.25)
    end
    function farm_total()
        return MOMENTUM_TEST.view(MOCK.now).farming.total
    end
    function farm_logout()
        local bytes=MOCK.bytes(8);MOCK.put(bytes,4,1,1)
        MOCK.fire('packet_in',MOCK.packet(0x00B,bytes))
        MOCK.login_status=0;MOCK.zoning=true;MOCK.frame(.25)
    end
    function farm_login(name,id)
        MOCK.player.name,MOCK.player.server_id=name,id
        MOCK.login_status=2;MOCK.zoning=false
        local bytes=MOCK.bytes(0xA0);MOCK.put(bytes,4,4,id);MOCK.put(bytes,48,2,102)
        for index=1,#name do bytes[0x84+index-1]=name:byte(index) end
        MOCK.fire('packet_in',MOCK.packet(0x00A,bytes))
        MOCK.fire('packet_in',MOCK.packet(0x061,MOCK.bytes(96)))
        MOCK.frame(.25)
    end
"""


class FarmingPersistenceTests(unittest.TestCase):
    def seed(self, folder):
        source = """
            local s=require('ui.defaults').make()
            s.appearance_version=2;s.style.palette_version=1
            require('ui.modes').select(s,'farming')
            s.farming.selected_item=4;s.farming.prices['4']=10
            return T(s)
        """
        write_settings(folder, source)
        write_settings(folder, source, 'Second_1002')

    def start(self, folder):
        lua = client_runtime(folder)
        load_entry(lua)
        lua.execute(HELPERS)
        return lua

    def test_current_character_job_resume_excludes_offline_time(self):
        with tempfile.TemporaryDirectory() as folder:
            self.seed(folder)
            lua = self.start(folder)
            lua.execute('farm_loot(3);for i=1,65 do MOCK.frame(1) end;assert(MOMENTUM_TEST.services.session_save())')
            elapsed = lua.eval('MOMENTUM_TEST.view(MOCK.now).farming.elapsed')
            self.assertGreaterEqual(elapsed, 60)
            self.assertEqual(lua.eval('farm_total()'), 3)
            self.assertEqual(lua.eval('MOMENTUM_TEST.view(MOCK.now).farming.estimated_value'), 30)
            lua.execute("MOMENTUM_TEST.settings().display.labels.farm_items='Saved items';MOMENTUM_TEST.state.dirty=true;MOMENTUM_TEST.services.save();MOCK.fire('unload')")
            lua = self.start(folder)
            self.assertEqual(lua.eval('farm_total()'), 3)
            self.assertAlmostEqual(lua.eval('MOMENTUM_TEST.view(MOCK.now).farming.elapsed'), elapsed, places=6)
            self.assertEqual(lua.eval('MOMENTUM_TEST.settings().modes.selected'), 'farming')
            self.assertEqual(lua.eval('MOMENTUM_TEST.settings().display.labels.farm_items'), 'Saved items')
            self.assertEqual(lua.eval('MOMENTUM_TEST.view(MOCK.now).farming.estimated_value'), 30)
            lua.execute('farm_loot(2)')
            self.assertEqual(lua.eval('farm_total()'), 5)
            self.assertEqual(lua.eval('MOMENTUM_TEST.view(MOCK.now).farming.estimated_value'), 50)
            lua.execute("MOCK.fire('unload')")

    def test_shared_layout_roundtrip_keeps_private_farming_totals(self):
        with tempfile.TemporaryDirectory() as folder:
            self.seed(folder)
            lua = self.start(folder)
            lua.execute("""
                farm_loot(3)
                assert(MOMENTUM_TEST.services.shared(true))
                local s=MOMENTUM_TEST.settings()
                s.farming.auto_layout=true;s.display.labels.farm_items='Shared items'
                MOMENTUM_TEST.state.dirty=true;MOMENTUM_TEST.services.save()
                assert(MOMENTUM_TEST.services.bar_mode('auto'));MOCK.frame(.25)
                assert(MOMENTUM_TEST.settings().modes.active=='farming')
                farm_logout();farm_login('Second',1002)
            """)
            self.assertEqual(lua.eval('farm_total()'), 0)
            self.assertEqual(lua.eval('MOMENTUM_TEST.settings().display.labels.farm_items'), 'Shared items')
            self.assertEqual(lua.eval('MOMENTUM_TEST.settings().modes.active'), 'farming')
            lua.execute("farm_loot(5);farm_logout();farm_login('Tester',1001)")
            self.assertEqual(lua.eval('farm_total()'), 3)
            self.assertEqual(lua.eval('MOMENTUM_TEST.settings().display.labels.farm_items'), 'Shared items')
            lua.execute("""
                assert(MOMENTUM_TEST.services.shared(false))
                local s=MOMENTUM_TEST.settings();s.display.labels.farm_items='Main items'
                MOMENTUM_TEST.state.dirty=true;MOMENTUM_TEST.services.save()
                farm_logout();farm_login('Second',1002)
            """)
            self.assertEqual(lua.eval('farm_total()'), 5)
            self.assertNotEqual(lua.eval('MOMENTUM_TEST.settings().display.labels.farm_items'), 'Main items')
            lua.execute("farm_logout();farm_login('Tester',1001)")
            self.assertEqual(lua.eval('farm_total()'), 3)
            self.assertEqual(lua.eval('MOMENTUM_TEST.settings().display.labels.farm_items'), 'Main items')
            self.assertFalse(lua.eval('MOMENTUM_TEST.state.broken'))
            lua.execute("MOCK.fire('unload')")

    def test_old_history_upgrades_and_malformed_farming_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            self.seed(folder)
            lua = self.start(folder)
            lua.execute("farm_loot(3);assert(MOMENTUM_TEST.services.session_save());MOCK.fire('unload')")
            path = Path(folder) / 'config/addons/momentum/sessions-1001.json'
            data = json.loads(path.read_text())
            for row in data['entries']:
                row['payload'].pop('farming', None)
            path.write_text(json.dumps(data))
            lua = self.start(folder)
            self.assertEqual(lua.eval('farm_total()'), 0)
            self.assertTrue(lua.eval('MOMENTUM_TEST.state.award_ready'))
            lua.execute("farm_loot(2);assert(MOMENTUM_TEST.services.session_save());MOCK.fire('unload')")
            data = json.loads(path.read_text())
            self.assertEqual(data['entries'][0]['payload']['farming']['total'], 2)
            data['entries'][0]['payload']['farming']['total'] = -1
            path.write_text(json.dumps(data))
            before = path.read_bytes()
            lua = self.start(folder)
            self.assertTrue(lua.eval('MOMENTUM_TEST.services.session_problem() ~= nil'))
            self.assertEqual(lua.eval('farm_total()'), 0)
            lua.execute('farm_loot(9)')
            self.assertEqual(lua.eval('farm_total()'), 9)
            lua.execute("MOCK.fire('unload')")
            self.assertEqual(path.read_bytes(), before)


if __name__ == '__main__':
    unittest.main(verbosity=2)
