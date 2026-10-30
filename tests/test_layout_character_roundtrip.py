"""Keep current placement across character switches using Ashita's real settings library."""
from pathlib import Path
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

    def test_subjob_choices_survive_character_switches_and_real_settings_reload(self):
        with tempfile.TemporaryDirectory() as folder:
            lua = self.start(folder)
            lua.execute('''
                local app=MOMENTUM_TEST;
                assert(app.services.bar_mode('exp'));
                app.settings().display.show_subjob=true;
                assert(app.services.bar_mode('merits'));
                app.settings().display.enabled.job=true;
                app.settings().display.show_subjob=false;
                assert(app.services.bar_mode('exp'));
                assert(app.services.bar_mode('auto'));
                app.settings().display.auto_layout=true;
                app.state.dirty=true;MOCK.frame(.25);
                assert(app.settings().display.show_subjob);
                assert(app.state.snapshot.subjob_name=='NIN' and app.state.snapshot.subjob_level==25);
                audit_logout();
                MOCK.player.sub_job,MOCK.player.sub_level=6,15;
                audit_login('Second',1002,2);
                assert(not app.settings().display.show_subjob);
                assert(app.state.snapshot.subjob==nil);
                app.settings().display.show_subjob=true;
                app.state.dirty=true;MOCK.frame(.25);
                assert(app.state.snapshot.subjob_name=='THF' and app.state.snapshot.subjob_level==15);
                audit_logout();
                MOCK.player.sub_job,MOCK.player.sub_level=13,25;
                audit_login('Tester',1001,1);
                assert(app.settings().display.show_subjob);
                assert(app.state.snapshot.subjob_name=='NIN' and app.state.snapshot.subjob_level==25);
                assert(app.services.bar_mode('merits'));
                assert(not app.settings().display.show_subjob);
                assert(app.services.bar_mode('exp'));
                assert(app.settings().display.show_subjob);
                assert(CLIENT_SETTINGS.reload());MOCK.frame(.25);
                assert(app.settings().display.show_subjob);
                assert(not app.state.broken);
            ''')
            fresh = client_runtime(folder)
            load_entry(fresh)
            self.assertTrue(fresh.eval('MOMENTUM_TEST.settings().display.show_subjob'))
            fresh.execute("assert(MOMENTUM_TEST.services.bar_mode('merits'))")
            self.assertFalse(fresh.eval('MOMENTUM_TEST.settings().display.show_subjob'))
            self.assertFalse(fresh.eval('MOMENTUM_TEST.state.broken'))

    def test_shared_layout_follows_sequential_characters_modes_and_reload(self):
        with tempfile.TemporaryDirectory() as folder:
            lua = self.start(folder)
            lua.execute('''
                local app=MOMENTUM_TEST;
                local rules=require('data.phoenix_rules');
                MOCK.player.main_level,MOCK.player.exp_needed,MOCK.player.exp=75,rules.tnl[75],1000;
                MOCK.frame(.25);
                assert(app.services.shared(true));
                assert(app.services.bar_mode('exp'));
                app.settings().display.show_subjob=true;
                app.settings().display.labels.progress='Main shared EXP';
                assert(app.services.bar_mode('merits'));
                app.settings().display.enabled.job=true;
                app.settings().display.show_subjob=false;
                app.settings().display.labels.lp_rate='Shared LP';
                assert(app.services.bar_mode('auto'));
                app.settings().display.auto_layout=true;
                app.state.dirty=true;MOCK.frame(.25);
                assert(app.settings().modes.active=='exp' and app.settings().display.show_subjob);
                MOCK.player.mode='lp';MOCK.frame(.25);
                assert(app.settings().modes.active=='merits' and not app.settings().display.show_subjob);
                MOCK.player.mode='exp';MOCK.frame(.25);MOCK.frame(.25);
                assert(app.settings().modes.active=='exp' and app.settings().display.show_subjob);
                app.settings().display.labels.progress='Main callback edit';
                app.state.dirty=true;
                audit_logout();
                MOCK.player.sub_job,MOCK.player.sub_level=6,15;
                audit_login('Second',1002,2);
                assert(app.settings().shared);
                assert(app.settings().display.labels.progress=='Main callback edit',
                    'Shared callback edit became '..app.settings().display.labels.progress..' in '..app.settings().modes.active);
                assert(app.settings().display.show_subjob);
                assert(app.state.snapshot.subjob_name=='THF' and app.state.snapshot.subjob_level==15);
                assert(app.services.bar_mode('exp'));
                app.settings().display.show_subjob=false;
                app.settings().display.labels.progress='Alt shared EXP';
                assert(app.services.bar_mode('merits'));
                app.settings().display.enabled.job=true;
                app.settings().display.show_subjob=true;
                assert(app.services.bar_mode('auto'));
                MOCK.frame(.25);
                assert(not app.settings().display.show_subjob);
                app.settings().display.labels.progress='Alt callback edit';
                app.state.dirty=true;
                audit_logout();
                MOCK.player.sub_job,MOCK.player.sub_level=13,25;
                audit_login('Tester',1001,1);
                assert(app.settings().shared and not app.settings().display.show_subjob);
                assert(app.settings().display.labels.progress=='Alt callback edit');
                assert(app.services.bar_mode('merits'));
                assert(app.settings().display.show_subjob);
                assert(app.services.bar_mode('exp'));
                assert(not app.settings().display.show_subjob);
                assert(CLIENT_SETTINGS.reload());MOCK.frame(.25);
                assert(app.settings().shared and not app.settings().display.show_subjob);
                assert(app.settings().display.labels.progress=='Alt callback edit');
                assert(not app.state.broken);
            ''')
            fresh = client_runtime(folder)
            load_entry(fresh)
            self.assertTrue(fresh.eval('MOMENTUM_TEST.settings().shared'))
            self.assertEqual(fresh.eval('MOMENTUM_TEST.settings().display.labels.progress'), 'Alt callback edit')
            self.assertFalse(fresh.eval('MOMENTUM_TEST.settings().display.show_subjob'))
            fresh.execute("assert(MOMENTUM_TEST.services.bar_mode('merits'))")
            self.assertTrue(fresh.eval('MOMENTUM_TEST.settings().display.show_subjob'))
            lua.execute('''
                local app=MOMENTUM_TEST;
                assert(app.services.shared(false));
                app.settings().display.show_subjob=true;
                app.settings().display.labels.progress='Solo main';
                app.state.dirty=true;MOCK.frame(.25);
                audit_logout();audit_login('Second',1002,2);
                assert(not app.settings().shared);
                assert(app.settings().display.labels.progress~='Solo main');
                assert(app.settings().bar.width==1300);
                app.settings().display.labels.progress='Solo alt';
                app.settings().display.show_subjob=false;
                app.state.dirty=true;MOCK.frame(.25);
                audit_logout();audit_login('Tester',1001,1);
                assert(not app.settings().shared);
                assert(app.settings().display.labels.progress=='Solo main' and app.settings().display.show_subjob);
                assert(CLIENT_SETTINGS.reload());MOCK.frame(.25);
                assert(not app.settings().shared and app.settings().display.labels.progress=='Solo main');
                assert(not app.state.broken);
            ''')

    def test_shared_save_and_undo_preserve_session_chain_and_event_timers(self):
        with tempfile.TemporaryDirectory() as folder:
            lua = self.start(folder)
            lua.execute('''
                local app=MOMENTUM_TEST;
                local rules=require('data.event_rules');
                assert(app.services.bar_mode('exp'));
                MOCK.player.zone,MOCK.player.buffs=144,{249,251};
                app.sample(MOCK.now);
                local index;
                for key,row in pairs(rules.areas[144].battles) do if row.kind=='bcnm' then index=key;break;end end
                local utc=app.events.observer:utc(MOCK.now);
                assert(app.events.core:begin(144,index,MOCK.now,utc,false));
                assert(app.events.core:timer(600,MOCK.now,utc,false));
                assert(app.tracker():award({kind='exp',amount=100,source='battle',chain=2},MOCK.now));
                app.services.session_pause(true);
                local before=app.view(MOCK.now);
                local deadline=app.events.core.current.ends_at;
                assert(before.chain==2 and before.chain_left>0 and before.food and before.dedication);
                assert(app.services.shared(true));
                local height=app.settings().bar.height;
                app.settings().window.open=true;
                local pending=true;
                require('ui.settings_window').draw=function(settings)
                    if not pending then return false;end
                    pending=false;settings.bar.height=height+4;return true;
                end;
                MOCK.frame(.25);
                assert(app.settings().bar.height==height+4);
                app.services.undo();
                assert(app.settings().bar.height==height);
                assert(app.services.shared(false));
                local after=app.view(MOCK.now);
                assert(after.session_exp==100 and after.paused);
                assert(after.chain==2 and after.chain_left>0 and after.chain_left<=before.chain_left);
                assert(after.food and after.dedication);
                assert(app.events.core.current.ends_at==deadline and after.events.active);
                assert(after.events.zone_elapsed>=before.events.zone_elapsed);
                assert(not app.state.broken and #MOCK.commands==0);
            ''')

    def test_shared_invalid_json_and_failed_write_keep_pending_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            lua = self.start(folder)
            shared = Path(folder) / 'config/addons/momentum/shared_layout.json'
            own = Path(folder) / 'config/addons/momentum/Tester_1001/settings.lua'
            original_own = own.read_bytes()
            shared.write_text('{bad json', encoding='ascii')
            self.assertFalse(lua.execute('local ok=MOMENTUM_TEST.services.shared(true);return ok'))
            self.assertEqual(shared.read_text(encoding='ascii'), '{bad json')
            self.assertEqual(own.read_bytes(), original_own)
            self.assertFalse(lua.eval('MOMENTUM_TEST.settings().shared'))
            shared.unlink()
            lua.execute('''
                local app=MOMENTUM_TEST;
                assert(app.services.shared(true));
                local store=require('core.file_store');
                local write=store.write;
                local path=MOCK_INSTALL_PATH..'/config/addons/momentum/shared_layout.json';
                local old_height=app.settings().bar.height;
                store.write=function(destination,...)
                    if destination:gsub('\\\\','/')==path then return false,'Test write failure';end
                    return write(destination,...);
                end;
                app.settings().bar.height=old_height+3;
                app.state.dirty=true;MOCK.frame(.25);
                assert(app.state.dirty and app.settings().bar.height==old_height+3);
                assert(store.read(path).layout.bar.height==old_height);
                assert(app.settings().shared and not app.state.broken);
                store.write=write;MOCK.frame(11);
                assert(not app.state.dirty);
                assert(store.read(path).layout.bar.height==old_height+3);
                assert(CLIENT_SETTINGS.reload());MOCK.frame(.25);
                assert(app.settings().shared and app.settings().bar.height==old_height+3);
                assert(not app.state.broken and #MOCK.commands==0);
            ''')


if __name__ == '__main__':
    unittest.main()
