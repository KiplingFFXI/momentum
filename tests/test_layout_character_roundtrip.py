"""Keep current placement across character switches using Ashita's real settings library."""
import tempfile
import unittest

from test_settings_client import client_runtime, load_entry, write_settings


class LayoutCharacterRoundtripTests(unittest.TestCase):
    def start(self, folder):
        write_settings(folder, "local s=require('ui.defaults').make();s.appearance_version=2;s.style.palette_version=1;s.bar.docked=false;s.bar.auto_width=false;s.bar.snap=false;s.bar.width=384;s.bar.x=211;s.bar.y=177;return T(s)")
        write_settings(folder, "local s=require('ui.defaults').make();s.appearance_version=2;s.style.palette_version=1;s.bar.docked=true;s.bar.auto_width=false;s.bar.width=1300;return T(s)", 'Second_1002')
        lua = client_runtime(folder)
        load_entry(lua)
        lua.execute('''
            function audit_logout()
                local data=MOCK.bytes(8);MOCK.put(data,4,1,1);
                MOCK.fire('packet_in',MOCK.packet(0x00B,data));
                MOCK.login_status=0;MOCK.zoning=true;MOCK.frame(.25);
                assert(MOMENTUM_TEST.state.last_job_id == nil);
            end
            function audit_login(name,id,job)
                MOCK.player.name,MOCK.player.server_id,MOCK.player.main_job=name,id,job;
                MOCK.login_status=2;MOCK.zoning=false;
                local data=MOCK.bytes(0xA0);MOCK.put(data,4,4,id);MOCK.put(data,48,2,102);
                for index=1,#name do data[0x84+index-1]=name:byte(index);end
                MOCK.fire('packet_in',MOCK.packet(0x00A,data));
                MOCK.fire('packet_in',MOCK.packet(0x061,MOCK.bytes(96)));MOCK.frame(.25);
            end
        ''')
        return lua

    def assert_free(self, lua, width):
        self.assertEqual(lua.execute('local b=MOMENTUM_TEST.settings().bar;return b.docked,b.width,b.x,b.y,b.auto_width'),
                         (False, width, 211, 177, False))
        self.assertFalse(lua.eval('MOMENTUM_TEST.state.broken'))

    def test_unlinked_layouts_survive_shared_and_dirty_roundtrips(self):
        for shared in (False, True):
            for dirty in (False, True):
                with self.subTest(shared=shared, dirty=dirty), tempfile.TemporaryDirectory() as folder:
                    lua = self.start(folder)
                    if shared:
                        lua.execute('assert(MOMENTUM_TEST.services.shared(true))')
                    width = 391 if dirty else 384
                    if dirty:
                        lua.execute('MOMENTUM_TEST.settings().bar.width=391;MOMENTUM_TEST.state.dirty=true')
                    lua.execute("audit_logout();audit_login('Second',1002,1);audit_logout();audit_login('Tester',1001,1)")
                    self.assert_free(lua, width)

    def test_job_link_does_not_replace_current_layout_on_login_or_return(self):
        for alt_job in (1, 2):
            with self.subTest(alt_job=alt_job), tempfile.TemporaryDirectory() as folder:
                lua = self.start(folder)
                lua.execute('''
                    local s=MOMENTUM_TEST.settings();
                    s.bar.docked=true;s.bar.width=1300;
                    assert(MOMENTUM_TEST.services.save_profile('Old WAR'));
                    assert(MOMENTUM_TEST.services.job_link(1,'Old WAR'));
                    assert(MOMENTUM_TEST.services.job_link(2,'Old WAR'));
                    s.bar.docked=false;s.bar.auto_width=false;s.bar.snap=false;s.bar.width=384;s.bar.x=211;s.bar.y=177;
                    MOMENTUM_TEST.state.dirty=true;MOMENTUM_TEST.services.save();
                    MOCK.frame(.25);
                    assert(not MOMENTUM_TEST.state.dirty);
                ''')
                lua.execute("audit_logout();audit_login('Second',1002,...);audit_logout();audit_login('Tester',1001,1)", alt_job)
                self.assert_free(lua, 384)
                self.assertTrue(lua.eval('CLIENT_SETTINGS.reload()'))
                lua.execute('MOCK.frame(.25)')
                self.assert_free(lua, 384)
                fresh = client_runtime(folder)
                load_entry(fresh)
                self.assert_free(fresh, 384)
                lua.execute('''
                    MOCK.login_status=0;MOMENTUM_TEST.sample(MOCK.now+.1);
                    MOCK.login_status=2;MOCK.player.main_job=2;MOMENTUM_TEST.sample(MOCK.now+.2);
                ''')
                self.assertEqual(lua.execute('local b=MOMENTUM_TEST.settings().bar;return b.docked,b.width'), (True, 1300))

    def test_shared_layout_still_bypasses_a_linked_job_profile(self):
        with tempfile.TemporaryDirectory() as folder:
            lua = self.start(folder)
            lua.execute('''
                local s=MOMENTUM_TEST.settings();
                s.bar.docked=true;s.bar.width=1300;
                assert(MOMENTUM_TEST.services.save_profile('Old WAR'));
                assert(MOMENTUM_TEST.services.job_link(2,'Old WAR'));
                s.bar.docked=false;s.bar.auto_width=false;s.bar.snap=false;s.bar.width=384;s.bar.x=211;s.bar.y=177;
                assert(MOMENTUM_TEST.services.shared(true));
                MOCK.player.main_job=2;MOMENTUM_TEST.sample(MOCK.now+.1);
            ''')
            self.assert_free(lua, 384)


if __name__ == '__main__':
    unittest.main()
