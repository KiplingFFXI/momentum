"""Exercise the installed Ashita settings library with temporary settings files."""
from pathlib import Path
import tempfile
import unittest

from lupa import luajit21

import run

ENTRY = run.ADDON / 'momentum.lua'


def client_runtime(folder, login_status=2):
    root = Path(folder).resolve()
    lua = run.runtime(root)

    def mkdir(path):
        target = Path(path).resolve()
        if not target.is_relative_to(root):
            raise AssertionError('Settings attempted to create a folder outside the test directory.')
        target.mkdir(parents=True, exist_ok=True)
        return True

    lua.globals().CLIENT_TEST_MKDIR = mkdir
    lua.globals().CLIENT_TEST_EXISTS = lambda path: Path(path).exists()
    lua.globals().MOCK.login_status = login_status
    lua.execute("""
        ashita.fs.create_dir = function(path) return CLIENT_TEST_MKDIR(path) end
        ashita.fs.exists = function(path) return CLIENT_TEST_EXISTS(path) end
        for _, name in ipairs({'common', 'settings', 'chat'}) do
            package.preload[name] = nil
            package.loaded[name] = nil
        end
        require('common')
        CLIENT_SETTINGS = require('settings')
    """)
    return lua


def settings_file(folder, character='Tester_1001'):
    return Path(folder) / 'config/addons/momentum' / character / 'settings.lua'


def write_settings(folder, text, character='Tester_1001'):
    path = settings_file(folder, character)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='ascii')
    return path


def load_entry(lua, broken=False):
    source = ENTRY.read_text(encoding='ascii')
    if broken:
        needle = 'settings.load(T(defaults.make()))'
        if source.count(needle) != 1:
            raise AssertionError('Expected exactly one current settings-load call for the regression fixture.')
        source = source.replace(needle, 'settings.load(defaults.make())')
    lua.execute(source)


class ClientSettingsTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='momentum_client_settings_')
        self.folder = Path(self.work.name)

    def tearDown(self):
        self.work.cleanup()

    def assert_current_root(self, lua):
        self.assertTrue(lua.eval("rawequal(MOMENTUM_TEST.settings(), CLIENT_SETTINGS.get())"))
        self.assertEqual(lua.eval("type(MOMENTUM_TEST.settings().copy)"), 'function')

    def test_unwrapped_fresh_load_reproduces_client_failure(self):
        lua = client_runtime(self.folder)
        with self.assertRaisesRegex(luajit21.LuaError, r"settings\.lua:\d+:.*nil value"):
            load_entry(lua, broken=True)

    def test_unwrapped_corrupt_fallback_reproduces_client_failure(self):
        write_settings(self.folder, 'this is not a settings table')
        lua = client_runtime(self.folder)
        with self.assertRaisesRegex(luajit21.LuaError, r"settings\.lua:\d+:.*copy"):
            load_entry(lua, broken=True)

    def test_existing_valid_file_hides_the_unwrapped_load_defect(self):
        write_settings(self.folder, "return T{display = T{divider = ' / '}}")
        lua = client_runtime(self.folder)
        load_entry(lua, broken=True)
        self.assertEqual(lua.eval('MOMENTUM_TEST.settings().display.divider'), ' / ')
        self.assert_current_root(lua)

    def test_fixed_fresh_load_draw_and_unload_save(self):
        lua = client_runtime(self.folder)
        load_entry(lua)
        lua.execute("MOCK.fire('load'); MOCK.frame(0.25)")
        self.assertFalse(lua.eval('MOMENTUM_TEST.state.broken'))
        self.assertTrue(settings_file(self.folder).is_file())
        self.assert_current_root(lua)
        lua.execute("MOMENTUM_TEST.settings().display.divider = ' * '; MOMENTUM_TEST.state.dirty = true; MOCK.fire('unload')")
        saved = lua.execute("return assert(loadfile(...))()", settings_file(self.folder).as_posix())
        self.assertEqual(saved.display.divider, ' * ')
        self.assert_current_root(lua)

    def test_fixed_logged_out_load_uses_defaults_folder(self):
        lua = client_runtime(self.folder, login_status=0)
        load_entry(lua)
        self.assertTrue(settings_file(self.folder, 'defaults').is_file())
        self.assert_current_root(lua)

    def test_fixed_existing_partial_file_detaches_nested_defaults(self):
        write_settings(self.folder, "return T{display = T{divider = ' / '}}")
        lua = client_runtime(self.folder)
        load_entry(lua)
        self.assert_current_root(lua)
        lua.execute("""
            assert(MOMENTUM_TEST.settings().display.divider == ' / ')
            assert(not rawequal(MOMENTUM_TEST.settings().bar, CLIENT_SETTINGS.cache.settings.defaults.bar))
            MOCK.fire('command', {command='/momentum free'})
            MOCK.fire('command', {command='/momentum divider +'})
            assert(CLIENT_SETTINGS.cache.settings.defaults.bar.docked)
            assert(CLIENT_SETTINGS.cache.settings.defaults.display.divider == require('ui.defaults').make().display.divider)
        """)
        saved = lua.execute("return assert(loadfile(...))()", settings_file(self.folder).as_posix())
        self.assertFalse(saved.bar.docked)
        self.assertEqual(saved.display.divider, '+')

    def test_fixed_corrupt_file_falls_back_to_defaults(self):
        write_settings(self.folder, 'this is not a settings table')
        lua = client_runtime(self.folder)
        load_entry(lua)
        self.assert_current_root(lua)
        self.assertEqual(lua.eval('MOMENTUM_TEST.settings().display.divider'), lua.eval("require('ui.defaults').make().display.divider"))
        self.assertTrue(any('reverted to default' in str(line) for line in lua.globals().MOCK.printed.values()))
        saved = lua.execute("return assert(loadfile(...))()", settings_file(self.folder).as_posix())
        self.assertEqual(saved.display.divider, lua.eval("require('ui.defaults').make().display.divider"))

    def test_reload_and_reset_keep_cached_root_and_defaults_isolated(self):
        lua = client_runtime(self.folder)
        load_entry(lua)
        write_settings(self.folder, "return T{display=T{divider=' . '}}")
        self.assertTrue(lua.eval('CLIENT_SETTINGS.reload()'))
        self.assert_current_root(lua)
        lua.execute("""
            assert(MOMENTUM_TEST.settings().display.divider == ' . ')
            MOCK.fire('command', {command='/momentum free'})
            assert(CLIENT_SETTINGS.cache.settings.defaults.bar.docked)
            assert(CLIENT_SETTINGS.reset())
            assert(MOMENTUM_TEST.settings().bar.docked)
            assert(MOMENTUM_TEST.settings().display.divider == require('ui.defaults').make().display.divider)
            MOCK.fire('load')
            MOCK.frame(0.25)
            assert(not MOMENTUM_TEST.state.broken)
        """)
        self.assert_current_root(lua)

    def test_character_callbacks_save_old_and_isolate_new_character(self):
        lua = client_runtime(self.folder)
        load_entry(lua)
        lua.execute("""
            MOCK.fire('command', {command='/momentum divider *'})
            local logout = MOCK.bytes(8)
            MOCK.put(logout,4,1,1)
            MOCK.fire('packet_in',MOCK.packet(0x00B,logout))
            assert(MOMENTUM_TEST.settings().display.divider == require('ui.defaults').make().display.divider)
            MOCK.player.name, MOCK.player.server_id = 'Second',1002
            local login=MOCK.bytes(0xA0)
            MOCK.put(login,4,4,1002)
            for i=1,#MOCK.player.name do login[0x84+i-1]=MOCK.player.name:byte(i) end
            MOCK.fire('packet_in',MOCK.packet(0x00A,login))
            assert(MOMENTUM_TEST.settings().display.divider == require('ui.defaults').make().display.divider)
            MOCK.fire('command',{command='/momentum divider /'})
            assert(CLIENT_SETTINGS.cache.settings.defaults.display.divider == require('ui.defaults').make().display.divider)
        """)
        self.assert_current_root(lua)
        first = lua.execute("return assert(loadfile(...))()", settings_file(self.folder).as_posix())
        second = lua.execute("return assert(loadfile(...))()", settings_file(self.folder, 'Second_1002').as_posix())
        self.assertEqual(first.display.divider, '*')
        self.assertEqual(second.display.divider, '/')

    def test_legacy_defaults_migrate_after_real_library_merge(self):
        write_settings(self.folder, """return T{
            bar=T{full_width=true,width=900,height=36,x=100,padding=10},
            style=T{font='Ashita',font_size=16,rounding=0,opacity=0.9,border=true,text_shadow=true},
            display=T{spacing=4,labels=T{remaining='To go'}}
        }""")
        lua = client_runtime(self.folder)
        load_entry(lua)
        self.assert_current_root(lua)
        lua.execute("""
            local s=MOMENTUM_TEST.settings()
            local fresh=require('ui.defaults').make()
            assert(s.appearance_version==2)
            assert(s.bar.width==fresh.bar.width and s.bar.height==fresh.bar.height and s.bar.x==fresh.bar.x)
            assert(s.bar.auto_width)
            assert(s.style.font==fresh.style.font and s.style.font_size==fresh.style.font_size and s.style.rounding==fresh.style.rounding)
            assert(not s.style.border and not s.style.text_shadow)
            assert(s.display.labels.remaining=='TNL' and s.display.spacing==fresh.display.spacing)
            assert(CLIENT_SETTINGS.cache.settings.defaults.appearance_version==0)
            MOCK.fire('load'); MOCK.frame(0.25); MOCK.fire('unload')
            assert(not MOMENTUM_TEST.state.broken)
        """)
        saved = lua.execute("return assert(loadfile(...))()", settings_file(self.folder).as_posix())
        self.assertEqual(saved.appearance_version, 2)
        self.assertEqual(saved.bar.width, 640)

    def test_custom_legacy_layout_survives_real_library_merge(self):
        write_settings(self.folder, """return T{
            bar=T{docked=false,full_width=false,width=523,height=29,x=212,y=176,padding=4},
            style=T{font='Arial',font_size=19,rounding=5,opacity=0.75,border=false,text_shadow=false},
            display=T{spacing=3,divider=' / ',labels=T{remaining='Needed'},order=T{'rate','job'}}
        }""")
        lua = client_runtime(self.folder)
        load_entry(lua)
        self.assert_current_root(lua)
        lua.execute("""
            local s=MOMENTUM_TEST.settings()
            assert(s.appearance_version==2)
            assert(s.bar.width==523 and s.bar.height==29 and s.bar.x==212 and s.bar.y==176)
            assert(not s.bar.docked)
            assert(s.style.font=='Arial' and s.style.font_size==19 and s.style.rounding==5)
            assert(s.style.opacity==0.75)
            assert(s.display.labels.remaining=='Needed' and s.display.divider==' / ' and s.display.spacing==3)
            assert(s.display.order[1]=='rate' and s.display.order[2]=='job')
            assert(CLIENT_SETTINGS.cache.settings.defaults.bar.width==640)
            MOCK.fire('load'); MOCK.frame(0.25)
            assert(not MOMENTUM_TEST.state.broken)
        """)

    def test_saved_migration_marker_prevents_repeating_migration(self):
        write_settings(self.folder, """return T{appearance_version=2,
            bar=T{width=900,height=36,x=100,padding=10},
            style=T{font='Ashita',font_size=16,rounding=0},
            display=T{spacing=4,labels=T{remaining='To go'}}
        }""")
        lua = client_runtime(self.folder)
        load_entry(lua)
        self.assert_current_root(lua)
        lua.execute("""
            local s=MOMENTUM_TEST.settings()
            assert(s.bar.width==900 and s.bar.height==36 and s.bar.x==100)
            assert(s.style.font=='Ashita' and s.style.font_size==16 and s.style.rounding==0)
            assert(s.display.labels.remaining=='To go' and s.display.spacing==4)
            assert(CLIENT_SETTINGS.reload())
            assert(MOMENTUM_TEST.settings().bar.height==36)
        """)
        self.assert_current_root(lua)

    def test_version_one_layout_gains_automatic_startup(self):
        write_settings(self.folder, """return T{appearance_version=1,
            bar=T{docked=true,width=640,height=24,x=10,bottom=0,chat_width=true,avoid_chat=true,
                chat_left=40,chat_right=1000,chat_screen=1600,chat_top=650,chat_bottom=900,chat_height=900},
            style=T{font='Segoe UI',font_size=14,rounding=8,opacity=0.94},
            display=T{spacing=0,divider=' | '}
        }""")
        lua = client_runtime(self.folder)
        load_entry(lua)
        self.assert_current_root(lua)
        lua.execute("""
            local s=MOMENTUM_TEST.settings()
            local fresh=require('ui.defaults').make()
            assert(s.appearance_version==2)
            assert(s.bar.auto_width and s.bar.x==0 and s.bar.bottom==2)
            assert(s.bar.height==fresh.bar.height and s.bar.width==fresh.bar.width)
            assert(s.style.font_size==fresh.style.font_size and s.style.rounding==fresh.style.rounding)
            assert(s.display.spacing==fresh.display.spacing and s.display.divider==fresh.display.divider)
            assert(s.bar.chat_left==nil and s.bar.chat_right==nil and s.bar.chat_height==nil)
            assert(s.bar.chat_width==nil and s.bar.avoid_chat==nil)
            assert(MOMENTUM_TEST.services.fit_chat==nil)
            MOCK.fire('load'); MOCK.frame(0.25); MOCK.fire('unload')
            assert(not MOMENTUM_TEST.state.broken)
        """)
        saved = lua.execute("return assert(loadfile(...))()", settings_file(self.folder).as_posix())
        self.assertEqual(saved.appearance_version, 2)
        self.assertTrue(saved.bar.auto_width)

    def test_chat_placement_survives_real_library_save_and_reload(self):
        write_settings(self.folder, "return T{appearance_version=2,bar=T{docked=true,anchor='top',start=135},display=T{alignment='right'}}")
        lua = client_runtime(self.folder)
        load_entry(lua)
        lua.execute("""
            MOCK.fire('load'); MOCK.frame(0.25)
            local s=MOMENTUM_TEST.settings()
            assert(s.bar.anchor=='top' and s.bar.start==135)
            assert(s.display.alignment=='right')
            assert(MOMENTUM_TEST.services.placement('free'))
            assert(not s.bar.docked and not s.bar.snap and not s.bar.auto_width)
            local x,y,w,h=s.bar.x,s.bar.y,s.bar.width,s.bar.height
            assert(CLIENT_SETTINGS.reload())
            s=MOMENTUM_TEST.settings()
            assert(not s.bar.docked and not s.bar.snap and not s.bar.auto_width)
            assert(s.bar.anchor=='top' and s.bar.start==135)
            assert(s.bar.x==x and s.bar.y==y and s.bar.width==w and s.bar.height==h)
            assert(s.display.alignment=='right')
        """)
        self.assert_current_root(lua)

    def test_newer_profile_version_is_not_migrated_backwards(self):
        lua = client_runtime(self.folder)
        load_entry(lua)
        lua.execute("""
            local future=require('ui.defaults').make()
            future.appearance_version=99
            future.bar.height=24
            future.bar.auto_width=false
            future.bar.width=513
            future.style.font_size=14
            future.style.rounding=8
            future.display.divider=' | '
            local folder=AshitaCore:GetInstallPath()..'/config/addons/momentum/'
            assert(require('ui.profiles').new(folder):save('Future layout',future))
            assert(MOMENTUM_TEST.services.load_profile('Future layout'))
            local s=MOMENTUM_TEST.settings()
            assert(s.appearance_version==99)
            assert(s.bar.height==24 and s.bar.width==513 and not s.bar.auto_width)
            assert(s.style.font_size==14 and s.style.rounding==8)
            assert(s.display.divider==' | ')
            assert(CLIENT_SETTINGS.reload())
            assert(MOMENTUM_TEST.settings().appearance_version==99)
        """)
        self.assert_current_root(lua)

    def check_saved_skin_reload(self, name, palette, border):
        keys = ('background', 'fill', 'lp_fill', 'text', 'label', 'divider', 'chain', 'warning')

        def color(hex_value, alpha=1):
            values = [int(hex_value[index:index + 2], 16) / 255 for index in (0, 2, 4)] + [alpha]
            return 'T{' + ','.join(format(value, '.17g') for value in values) + '}'

        colors = ','.join(key + '=' + color(value) for key, value in zip(keys, palette))
        colors += ',border=' + color(*border)
        write_settings(self.folder, "return T{appearance_version=2,"
                       "bar=T{docked=true,anchor='top',start=135,height=27},"
                       "display=T{alignment='right',divider=' / ',order=T{'rate','job'}},"
                       "alerts=T{food_enabled=true,food_volume=53},"
                       "style=T{preset='" + name + "',colors=T{" + colors + '}}}')
        lua = client_runtime(self.folder)
        load_entry(lua)
        lua.globals().CLIENT_SKIN_NAME = name
        lua.execute("""
            local s=MOMENTUM_TEST.settings()
            local theme=require('ui.theme')
            local same=require('ui.history').equal
            assert(s.style.palette_version==1 and s.appearance_version==2)
            assert(same(s.style.colors,theme.colors(CLIENT_SKIN_NAME)))
            assert(same(s.style.window_colors,theme.window_colors(CLIENT_SKIN_NAME)))
            assert(s.bar.anchor=='top' and s.bar.start==135 and s.bar.height==27)
            assert(s.display.alignment=='right' and s.display.divider==' / ' and s.display.order[1]=='rate')
            assert(s.alerts.food_enabled and s.alerts.food_volume==53)
            assert(CLIENT_SETTINGS.cache.settings.defaults.style.palette_version==0)
            assert(same(CLIENT_SETTINGS.cache.settings.defaults.style.window_colors,theme.window_colors('Phoenix')))
            MOCK.fire('load'); MOCK.frame(0.25)
            assert(not MOMENTUM_TEST.state.broken)
            local before=require('ui.history').copy(s)
            assert(CLIENT_SETTINGS.reload())
            assert(same(MOMENTUM_TEST.settings(),before))
            s=MOMENTUM_TEST.settings()
            s.style.colors.fill={0.123,0.234,0.345,0.456}
            s.style.window_colors.control={0.321,0.432,0.543,0.654}
            MOMENTUM_TEST.state.dirty=true
            MOCK.fire('unload')
            assert(CLIENT_SETTINGS.reload())
            s=MOMENTUM_TEST.settings()
            assert(same(s.style.colors.fill,{0.123,0.234,0.345,0.456}))
            assert(same(s.style.window_colors.control,{0.321,0.432,0.543,0.654}))
            assert(s.style.palette_version==1 and s.style.preset==CLIENT_SKIN_NAME)
            assert(MOMENTUM_TEST.services.save_profile('Saved skin'))
            assert(theme.apply(s,'Classic FFXI'))
            assert(MOMENTUM_TEST.services.load_profile('Saved skin'))
            assert(same(s.style.colors.fill,{0.123,0.234,0.345,0.456}))
            assert(same(s.style.window_colors.control,{0.321,0.432,0.543,0.654}))
            assert(s.style.preset==CLIENT_SKIN_NAME and s.bar.anchor=='top' and s.bar.start==135)
        """)
        self.assert_current_root(lua)
        saved = lua.execute('return assert(loadfile(...))()', settings_file(self.folder).as_posix())
        self.assertEqual(saved.style.palette_version, 1)
        self.assertEqual(saved.style.preset, name)
        self.assertEqual(saved.style.colors.fill[4], 0.456)
        self.assertEqual(saved.style.window_colors.control[4], 0.654)

    def test_saved_phoenix_skin_migrates_and_serializes(self):
        self.check_saved_skin_reload('Phoenix',
                                    ('0d1219', 'e7b15e', '67cdb8', 'f4f6fa', '9da9b7', '334151', '8fd6c5', 'f1bd79'),
                                    ('3a4657', 0.4))

    def test_saved_mint_skin_migrates_and_serializes(self):
        self.check_saved_skin_reload('Mint',
                                    ('101f1b', '275342', '245866', 'edf9f1', 'b1ebd0', '83bfa5', 'a4edcc', 'ffb39b'),
                                    ('83bfa5', 0.45))


if __name__ == '__main__':
    unittest.main(verbosity=2)
