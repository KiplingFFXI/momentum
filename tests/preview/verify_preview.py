"""Render the actual Lua UI and replay its reorder and placement controls."""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / 'out'


def heading_scroll(label, tab='Display'):
    return ("settings.window.sections['%s/%s']=true; "
            "local ig=require('imgui'); local header=ig.CollapsingHeader; "
            "ig.CollapsingHeader=function(value,...) local open=header(value,...); "
            "if value:find('##section_%s/%s',1,true) then ig.SetScrollHereY(0); end; return open; end"
            % (tab, label, tab, label))


def main():
    fit = ['--input-script', str(HERE / 'fit_input.json')]
    free = ['--set', 'bar.docked=false']
    chat = ['--input-script', str(HERE / 'native_chat_input.json')]
    alignment = ['--frames', '6', '--input-script', str(HERE / 'alignment_input.json')]
    cases = [
        ('bar-default', ['--hud', '--window', 'momentum'] + fit),
        ('bar-free-content', ['--hud', '--window', 'momentum'] + free + fit),
        ('bar-narrow', ['--hud', '--window', 'momentum', '--set', 'bar.auto_width=false', '--set', 'bar.width=240',
                        '--input-script', str(HERE / 'overflow_input.json')] + free),
        ('bar-wide', ['--hud', '--window', 'momentum', '--size', '2560', '1080'] + fit),
        ('bar-manual-width', ['--hud', '--window', 'momentum', '--set', 'bar.auto_width=false', '--set', 'bar.width=640'] + free + fit),
        ('bar-large-type', ['--hud', '--window', 'momentum', '--set', 'bar.height=24', '--set', 'style.font_size=16'] + fit),
        ('bar-icon-layout-fixture', ['--hud', '--window', 'momentum', '--icon-fixture',
                                     '--input-script', str(HERE / 'icon_input.json')]),
        ('alignment-fixed', ['--hud', '--window', 'momentum', '--set', 'bar.auto_width=false', '--set', 'bar.width=640'] + free + alignment),
        ('alignment-docked', ['--hud', '--window', 'momentum'] + alignment),
        ('alignment-icon', ['--hud', '--window', 'momentum', '--icon-fixture', '--exec', 'PREVIEW.expect_icon=true'] + alignment),
        ('alignment-overflow', ['--hud', '--window', 'momentum', '--set', 'bar.auto_width=false', '--set', 'bar.width=240',
                                '--exec', 'PREVIEW.expect_overflow=true'] + free + alignment),
        ('bar-merits', ['--hud', '--window', 'momentum', '--scene', 'Merits', '--exec',
                        "settings.display.enabled.merits=true; settings.display.enabled.merit_rate=true"]),
        ('bar-merit-readouts', ['--hud', '--window', 'momentum', '--scene', 'Merits', '--frames', '8',
                               '--set', 'bar.docked=false', '--set', 'bar.auto_width=false', '--set', 'bar.width=1500',
                               '--exec', "settings.display.order={'rate','merits','merit_rate','merits_session','merit_headroom','lp_remaining','merit_eta'}; for _,id in ipairs(settings.display.order) do settings.display.enabled[id]=true end",
                               '--input-script', str(HERE / 'merit_readouts_input.json')]),
        ('bar-gil-readouts', ['--hud', '--window', 'momentum', '--frames', '8',
                            '--set', 'bar.docked=false', '--set', 'bar.auto_width=false', '--set', 'bar.width=700',
                            '--exec', "settings.display.order={'gil','gil_gained','gil_spent','gil_net','gil_rate'}; for _,id in ipairs(settings.display.order) do settings.display.enabled[id]=true end",
                            '--input-script', str(HERE / 'gil_readouts_input.json')]),
        ('settings-merit-details', ['--window', 'settings', '--tab', 'Details', '--scene', 'Merits', '--window-size', '400', '660',
                                   '--exec', heading_scroll('Merit points', 'Details')]),
        ('settings-merit-full', ['--window', 'settings', '--tab', 'Details', '--scene', 'Capped', '--window-size', '400', '660',
                                '--exec', heading_scroll('Merit points', 'Details')]),
        ('bar-unknown', ['--hud', '--window', 'momentum', '--scene', 'No data']),
        ('input-label-position', ['--tab', 'Display', '--frames', '15',
                                  '--exec', heading_scroll('Position and size'),
                                  '--input-script', str(HERE / 'label_position_input.json')]),
        ('input-order', ['--window', 'settings', '--tab', 'Display', '--frames', '10',
                         '--exec', heading_scroll('Readouts and order'),
                         '--input-script', str(HERE / 'order_input.json')]),
        ('input-drag-dock', ['--hud', '--window', 'momentum', '--frames', '13',
                             '--input-script', str(HERE / 'drag_input.json')]),
        ('input-resize', ['--hud', '--window', 'momentum', '--frames', '8',
                          '--input-script', str(HERE / 'resize_input.json')]),
        ('input-width', ['--hud', '--window', 'momentum', '--frames', '8',
                         '--input-script', str(HERE / 'width_input.json')] + free),
        ('input-docked-width', ['--hud', '--window', 'momentum', '--frames', '8',
                                '--input-script', str(HERE / 'width_input.json')]),
        ('input-constrained-dock-width', ['--hud', '--window', 'momentum', '--frames', '8', '--set', 'bar.height=24',
                                          '--exec', 'MOCK.chat.height=364',
                                          '--input-script', str(HERE / 'width_input.json')]),
        ('input-width-return-origin', ['--hud', '--window', 'momentum', '--frames', '10',
                                       '--input-script', str(HERE / 'width_return_input.json')] + free),
        ('input-top-resize', ['--hud', '--window', 'momentum', '--frames', '8', '--set', 'bar.anchor=top',
                              '--input-script', str(HERE / 'top_resize_input.json')]),
        ('input-top-snap', ['--hud', '--window', 'momentum', '--frames', '13',
                            '--input-script', str(HERE / 'top_snap_input.json')]),
        ('full-entry', ['--full', '--window', 'settings']),
        ('automatic-startup', ['--full', '--hud', '--window', 'momentum_bar',
                                '--exec', 'settings.preview.show=false',
                                '--input-script', str(HERE / 'startup_input.json')]),
        ('hidden-while-typing', ['--full', '--window', 'settings', '--exec', 'MOCK.typing=true',
                                 '--input-script', str(HERE / 'hidden_input.json')]),
        ('typing-hide-disabled', ['--full', '--hud', '--window', 'momentum_bar', '--exec', 'MOCK.typing=true',
                                   '--exec', 'settings.preview.show=false',
                                   '--set', 'bar.hide_typing=false', '--input-script', str(HERE / 'startup_input.json')]),
        ('native-chat-border', ['--hud', '--window', 'momentum', '--chat-fixture', '--no-crop',
                                '--exec', 'PREVIEW.expected_y=866'] + chat),
        ('reported-chat-top', ['--hud', '--window', 'momentum', '--chat-fixture', '--no-crop', '--size', '1920', '1080',
                                '--set', 'bar.anchor=top', '--exec', 'PREVIEW.expected_y=801',
                                '--input-script', str(HERE / 'diagnostic_chat_input.json')]),
        ('reported-chat-bottom', ['--hud', '--window', 'momentum', '--chat-fixture', '--no-crop', '--size', '1920', '1080',
                                   '--set', 'bar.anchor=bottom', '--exec', 'PREVIEW.expected_y=1046',
                                   '--input-script', str(HERE / 'diagnostic_chat_input.json')]),
        ('native-chat-resize', ['--hud', '--window', 'momentum', '--chat-fixture', '--no-crop', '--frames', '6',
                                '--input-script', str(HERE / 'chat_resize_input.json')]),
        ('native-chat-secondary', ['--hud', '--window', 'momentum', '--chat-fixture', '--no-crop', '--exec',
                                   'MOCK.chat.height=300; MOCK.chat.windows={{x=50,y=820,width=600,height=56}}; PREVIEW.expected_y=878'] + chat),
        ('native-chat-above', ['--hud', '--window', 'momentum', '--chat-fixture', '--no-crop', '--exec',
                               'MOCK.chat.y=40; MOCK.chat.height=850; PREVIEW.expected_y=20', '--set', 'bar.anchor=top'] + chat),
        ('native-chat-start', ['--hud', '--window', 'momentum', '--chat-fixture', '--no-crop', '--set', 'bar.start=165',
                               '--exec', 'PREVIEW.expected_x=177; PREVIEW.expected_width=735; PREVIEW.expected_y=866'] + chat),
        ('native-chat-start-limit', ['--hud', '--window', 'momentum', '--chat-fixture', '--no-crop', '--set', 'bar.start=5000',
                                     '--exec', 'PREVIEW.expected_x=792; PREVIEW.expected_width=120; PREVIEW.expected_y=866'] + chat),
        ('native-chat-short-strip', ['--hud', '--window', 'momentum', '--chat-fixture', '--no-crop', '--set', 'bar.height=24',
                                     '--exec', 'MOCK.chat.height=364; PREVIEW.expected_y=886; PREVIEW.expected_height=14'] + chat),
        ('native-chat-missing', ['--full', '--window', 'settings', '--set', 'visibility.mode=chat', '--exec', 'MOCK.chat=nil',
                                 '--input-script', str(HERE / 'hidden_input.json')]),
        ('native-chat-no-space', ['--full', '--window', 'settings', '--exec', 'MOCK.chat.y=0; MOCK.chat.height=900',
                                  '--input-script', str(HERE / 'hidden_input.json')]),
        ('native-chat-bottom-blocked', ['--full', '--window', 'settings', '--exec', 'MOCK.chat.y=40; MOCK.chat.height=850',
                                        '--input-script', str(HERE / 'hidden_input.json')]),
        ('native-chat-top-blocked', ['--full', '--window', 'settings', '--set', 'bar.anchor=top',
                                     '--exec', 'MOCK.chat.y=10; MOCK.chat.height=344',
                                     '--input-script', str(HERE / 'hidden_input.json')]),
        ('free-without-chat', ['--hud', '--window', 'momentum', '--exec', 'MOCK.chat=nil',
                               '--set', 'bar.x=45', '--set', 'bar.y=300',
                               '--input-script', str(HERE / 'free_input.json')] + free),
    ]
    cases.extend([
        ('settings-chat-visibility', ['--full', '--window', 'settings', '--tab', 'Tracking', '--window-size', '420', '660',
                                      '--exec', heading_scroll('Visibility', 'Tracking'), '--frames', '32',
                                      '--input-script', str(HERE / 'chat_visibility_input.json')]),
        ('settings-manual-modes', ['--full', '--window', 'settings', '--tab', 'Display', '--window-size', '400', '660',
                                   '--frames', '39', '--input-script', str(HERE / 'manual_modes_input.json')]),
        ('dynamis-bar', ['--hud', '--window', 'momentum', '--scene', 'Dynamis', '--frames', '8',
                         '--exec', "require('ui.defaults').apply_starter(settings,'Dynamis'); settings.dynamis.layout_active=true",
                         '--input-script', str(HERE / 'dynamis_input.json')]),
        ('dynamis-options', ['--window', 'settings', '--scene', 'Dynamis', '--tab', 'Dynamis']),
        ('dynamis-wanted-narrow', ['--window', 'settings', '--scene', 'Dynamis', '--tab', 'Dynamis',
                                  '--window-size', '420', '620', '--exec', heading_scroll('Wanted drops', 'Dynamis')]),
    ])
    for tab in ('Display', 'Tracking', 'Details', 'Dynamis', 'Alerts', 'Appearance', 'Preview', 'Session', 'Profiles'):
        cases.append(('settings-' + tab.lower(), ['--window', 'settings', '--tab', tab]))
    for name in ('Phoenix', 'Classic FFXI', 'Minimal', 'High contrast', 'Ember', 'Mint', 'Lavender', 'Colorblind safe'):
        cases.append(('palette-' + name.lower().replace(' ', '-'), ['--window', 'settings', '--tab', 'Appearance',
                       '--exec', "PREVIEW.palette_name='%s'" % name,
                       '--input-script', str(HERE / 'palette_input.json'), '--frames', '8']))
    cases.extend([
        ('settings-narrow', ['--window', 'settings', '--tab', 'Display', '--window-size', '420', '620']),
        ('settings-large-font', ['--window', 'settings', '--tab', 'Appearance', '--set', 'window.font_size=28']),
        ('settings-wrapped-readouts', ['--window', 'settings', '--tab', 'Display', '--window-size', '400', '660',
                                       '--set', 'window.font_size=28', '--set', 'window.compact_navigation=true', '--frames', '8',
                                       '--exec', "dofile('tests/preview/readout_wrap_fixture.lua')",
                                       '--input-script', str(HERE / 'readout_wrap_input.json')]),
    ])
    position_scroll = heading_scroll('Position and size')
    alignment_scroll = "settings.window.sections['Display/Position and size']=true; local ig=require('imgui'); local text=ig.TextUnformatted; ig.TextUnformatted=function(value) text(value); if value=='Readout alignment' then ig.SetScrollHereY(0.15); end; end"
    height_scroll = "settings.window.sections['Display/Position and size']=true; local ig=require('imgui'); local text=ig.TextUnformatted; ig.TextUnformatted=function(value) text(value); if value=='Bar height' then ig.SetScrollHereY(0.25); end; end"
    cases.extend([
        ('input-alignment', ['--window', 'settings', '--tab', 'Display', '--exec', alignment_scroll,
                             '--input-script', str(HERE / 'alignment_control_input.json'), '--frames', '11']),
        ('input-height-free', ['--window', 'settings', '--tab', 'Display', '--exec', height_scroll,
                               '--input-script', str(HERE / 'height_control_input.json'), '--frames', '8'] + free),
        ('input-height-top', ['--window', 'settings', '--tab', 'Display', '--exec', height_scroll,
                              '--set', 'bar.anchor=top', '--input-script', str(HERE / 'height_control_input.json'), '--frames', '8']),
        ('input-height-bottom', ['--window', 'settings', '--tab', 'Display', '--exec', height_scroll,
                                 '--input-script', str(HERE / 'height_control_input.json'), '--frames', '8']),
        ('input-placement', ['--full', '--window', 'settings', '--tab', 'Display', '--exec', position_scroll,
                             '--input-script', str(HERE / 'placement_input.json'), '--frames', '19']),
        ('input-starting-point', ['--full', '--window', 'settings', '--tab', 'Display', '--exec', position_scroll,
                                  '--input-script', str(HERE / 'start_input.json'), '--frames', '8']),
        ('input-chat-center', ['--full', '--window', 'settings', '--tab', 'Display', '--exec', position_scroll,
                               '--set', 'bar.start=146', '--input-script', str(HERE / 'chat_center_input.json'), '--frames', '24']),
        ('settings-chat-center-narrow', ['--window', 'settings', '--tab', 'Display', '--exec', position_scroll,
                                         '--set', 'bar.chat_alignment=center', '--window-size', '420', '620']),
        ('input-free-placement', ['--full', '--window', 'momentum_bar', '--tab', 'Display', '--exec', position_scroll,
                                  '--set', 'bar.locked=true',
                                  '--input-script', str(HERE / 'free_placement_input.json'), '--frames', '33']),
        ('input-free-locked', ['--full', '--hud', '--window', 'momentum_bar', '--set', 'bar.docked=false', '--set', 'bar.locked=true',
                              '--set', 'bar.auto_width=false', '--set', 'bar.x=100', '--set', 'bar.y=400',
                              '--input-script', str(HERE / 'free_locked_input.json'), '--frames', '24']),
        ('settings-position', ['--window', 'settings', '--tab', 'Display', '--exec', position_scroll]),
        ('settings-position-narrow', ['--window', 'settings', '--tab', 'Display', '--exec', position_scroll,
                                      '--window-size', '420', '620']),
    ])
    alert_fixture = "dofile('tests/preview/alerts_fixture.lua')"
    food_scroll = "PREVIEW.alert_case='food'; " + alert_fixture
    cases.extend([
        ('settings-food', ['--window', 'settings', '--tab', 'Alerts', '--exec', food_scroll,
                           '--input-script', str(HERE / 'food_input.json'), '--frames', '33']),
        ('settings-food-narrow', ['--window', 'settings', '--tab', 'Alerts', '--exec', food_scroll,
                                  '--window-size', '420', '620', '--input-script', str(HERE / 'food_input.json'), '--frames', '33']),
        ('settings-food-large-font', ['--window', 'settings', '--tab', 'Alerts', '--exec', food_scroll,
                                      '--window-size', '400', '660', '--set', 'window.font_size=28',
                                      '--input-script', str(HERE / 'food_input.json'), '--frames', '33']),
    ])
    history_fixture = "PREVIEW.session_rows={{id='current',name='',job=1,job_name='WAR',created=1700000000,elapsed=2700,session_exp=6375,session_lp=0,net_exp=6200,net_lp=0,merits_gained=0,best_chain=5,active=true}}"
    details_fixture = "dofile('tests/preview/details_fixture.lua')"
    group_scroll = (
        "settings.window.sections['Display/Selected readout']=true; settings.window.sections['Display/More options']=true; "
        "local ig=require('imgui'); local header=ig.CollapsingHeader; "
        "ig.CollapsingHeader=function(value,...) local open=header(value,...); "
        "if value:find((PREVIEW.edit_group and 'More options' or 'Readouts and order')..' (?)##section_',1,true)==1 then ig.SetScrollHereY(0); end; return open; end; "
        "local checkbox=ig.Checkbox; ig.Checkbox=function(label,...) local changed=checkbox(label,...); "
        "if not PREVIEW.edit_group and label=='Use separate alignment groups' then ig.SetScrollHereY(0.5); end; return changed; end"
    )
    divider_scroll = "local ig=require('imgui'); local header=ig.CollapsingHeader; ig.CollapsingHeader=function(value,...) local open=header(value,...); if value:find((PREVIEW.edit_custom and 'Dividers and formatting' or 'Readouts and order')..' (?)##section_',1,true)==1 then ig.SetScrollHereY(0); end; return open; end"
    cases.extend([
        ('input-dividers', ['--window', 'settings', '--tab', 'Display', '--frames', '42',
                            '--exec', divider_scroll, '--input-script', str(HERE / 'dividers_input.json')]),
        ('input-dividers-narrow', ['--window', 'settings', '--tab', 'Display', '--frames', '42', '--window-size', '400', '660',
                                   '--exec', divider_scroll, '--input-script', str(HERE / 'dividers_input.json')]),
        ('input-drag-order', ['--window', 'settings', '--tab', 'Display', '--frames', '14',
                              '--exec', heading_scroll('Readouts and order'), '--input-script', str(HERE / 'drag_order_input.json')]),
        ('input-notification', ['--window', 'settings', '--tab', 'Alerts', '--frames', '36',
                                '--exec', "PREVIEW.alert_case='notification'; " + alert_fixture,
                                '--input-script', str(HERE / 'alerts_input.json')]),
        ('input-notification-narrow', ['--window', 'settings', '--tab', 'Alerts', '--frames', '36', '--window-size', '400', '660',
                                       '--exec', "PREVIEW.alert_case='notification'; " + alert_fixture,
                                       '--input-script', str(HERE / 'alerts_input.json')]),
        ('input-notification-large-font', ['--window', 'settings', '--tab', 'Alerts', '--frames', '36', '--window-size', '400', '660',
                                           '--set', 'window.font_size=28', '--exec', "PREVIEW.alert_case='notification'; " + alert_fixture,
                                           '--input-script', str(HERE / 'alerts_input.json')]),
        ('alerts-search-collapse', ['--window', 'settings', '--tab', 'Alerts', '--frames', '33',
                                    '--exec', "PREVIEW.alert_case='search'; " + alert_fixture,
                                    '--input-script', str(HERE / 'alerts_search_input.json')]),
        ('alerts-search-collapse-narrow', ['--window', 'settings', '--tab', 'Alerts', '--frames', '33', '--window-size', '400', '660',
                                           '--exec', "PREVIEW.alert_case='search'; " + alert_fixture,
                                           '--input-script', str(HERE / 'alerts_search_input.json')]),
        ('alerts-search-collapse-large-font', ['--window', 'settings', '--tab', 'Alerts', '--frames', '33', '--window-size', '400', '660',
                                               '--set', 'window.font_size=28', '--exec', "PREVIEW.alert_case='search'; " + alert_fixture,
                                               '--input-script', str(HERE / 'alerts_search_input.json')]),
        ('input-session-history', ['--window', 'settings', '--tab', 'Session', '--frames', '22',
                                   '--exec', history_fixture, '--exec', heading_scroll('Current session', 'Session'),
                                   '--input-script', str(HERE / 'session_history_input.json')]),
        ('input-session-history-narrow', ['--window', 'settings', '--tab', 'Session', '--frames', '22', '--window-size', '400', '660',
                                   '--exec', history_fixture, '--exec', heading_scroll('Current session', 'Session'),
                                   '--input-script', str(HERE / 'session_history_input.json')]),
        ('session-reset-exp', ['--full', '--frames', '16', '--no-crop',
                               '--script', str(HERE / 'session_reset_fixture.lua'),
                               '--input-script', str(HERE / 'session_reset_input.json')]),
        ('escape-config-combat', ['--full', '--frames', '43', '--no-crop',
                                  '--script', str(HERE / 'escape_config_fixture.lua'),
                                  '--input-script', str(HERE / 'escape_config_input.json')]),
        ('settings-close-combat', ['--full', '--frames', '38', '--no-crop',
                                   '--script', str(HERE / 'settings_close_fixture.lua'),
                                   '--input-script', str(HERE / 'settings_close_input.json')]),
        ('groups-docked', ['--hud', '--window', 'momentum', '--icon-fixture', '--input-script', str(HERE / 'groups_input.json')]),
        ('groups-free', ['--hud', '--window', 'momentum', '--set', 'bar.docked=false', '--set', 'bar.auto_width=false',
                         '--set', 'bar.width=640', '--input-script', str(HERE / 'groups_input.json')]),
        ('notice-contained', ['--hud', '--window', 'momentum', '--set', 'bar.docked=false', '--set', 'bar.auto_width=false',
                              '--set', 'bar.width=240', '--frames', '5', '--input-script', str(HERE / 'notice_input.json')]),
        ('details-narrow', ['--window', 'settings', '--tab', 'Details', '--window-size', '420', '620']),
        ('alerts-narrow', ['--window', 'settings', '--tab', 'Alerts', '--window-size', '420', '620']),
        ('alerts-large-font', ['--window', 'settings', '--tab', 'Alerts', '--window-size', '400', '660', '--set', 'window.font_size=28']),
        ('alerts-counts', ['--window', 'settings', '--tab', 'Alerts', '--frames', '5',
                            '--exec', "PREVIEW.alert_case='counts'; " + alert_fixture,
                            '--input-script', str(HERE / 'alerts_counts_input.json')]),
        ('alerts-counts-large-font', ['--window', 'settings', '--tab', 'Alerts', '--frames', '5',
                                       '--window-size', '400', '660', '--set', 'window.font_size=28',
                                       '--exec', "PREVIEW.alert_case='counts'; " + alert_fixture,
                                       '--input-script', str(HERE / 'alerts_counts_input.json')]),
        ('alerts-counts-large-font-lower', ['--window', 'settings', '--tab', 'Alerts', '--frames', '5',
                                             '--window-size', '400', '660', '--set', 'window.font_size=28',
                                             '--exec', "PREVIEW.alert_case='counts'; " + alert_fixture,
                                             '--exec', "PREVIEW.scroll_target='header/Levels and merit points'",
                                             '--input-script', str(HERE / 'alerts_counts_input.json')]),
        ('input-groups', ['--window', 'settings', '--tab', 'Display', '--frames', '23', '--exec', group_scroll,
                          '--input-script', str(HERE / 'group_controls_input.json')]),
        ('groups-priority-narrow', ['--hud', '--window', 'momentum', '--set', 'bar.docked=false', '--set', 'bar.auto_width=false',
                                    '--set', 'bar.width=240', '--input-script', str(HERE / 'priority_input.json')]),
        ('details-client-fixture', ['--window', 'settings', '--tab', 'Details', '--exec', details_fixture,
                                    '--exec', heading_scroll('Level sync', 'Details')]),
        ('details-ring-fixture', ['--window', 'settings', '--tab', 'Details', '--exec', details_fixture,
                                  '--exec', heading_scroll('Owned EXP rings', 'Details')]),
        ('details-ring-narrow', ['--window', 'settings', '--tab', 'Details', '--window-size', '420', '620',
                                 '--exec', details_fixture, '--exec', heading_scroll('Owned EXP rings', 'Details')]),
        ('input-session-record', ['--window', 'settings', '--tab', 'Session', '--frames', '19', '--exec', details_fixture,
                                   '--exec', heading_scroll('Saved sessions', 'Session'), '--input-script', str(HERE / 'session_record_input.json')]),
        ('session-history-fixture', ['--window', 'settings', '--tab', 'Session', '--exec', details_fixture,
                                     '--exec', heading_scroll('Saved sessions', 'Session')]),
        ('settings-compact', ['--window', 'settings', '--tab', 'Display', '--window-size', '400', '450',
                               '--set', 'window.compact_navigation=true']),
        ('details-advanced-sync', ['--window', 'settings', '--tab', 'Details', '--exec', details_fixture,
                                    '--exec', heading_scroll('Advanced sync estimate', 'Details')]),
        ('hud-readout-tooltips', ['--hud', '--script', str(HERE / 'hud_tooltips_fixture.lua'),
                                  '--input-script', str(HERE / 'hud_tooltips_input.json'), '--frames', '104',
                                  '--set', 'bar.docked=false', '--set', 'bar.auto_width=false', '--set', 'bar.x=20',
                                  '--set', 'bar.y=100', '--set', 'bar.width=700', '--set', 'bar.height=24',
                                  '--exec', "settings.display.order={'rate'}", '--no-crop']),
        ('hud-chain-timing', ['--hud', '--script', str(HERE / 'hud_tooltips_fixture.lua'),
                              '--input-script', str(HERE / 'chain_timer_input.json'), '--frames', '122',
                              '--set', 'bar.docked=false', '--set', 'bar.auto_width=false', '--set', 'bar.x=20',
                              '--set', 'bar.y=100', '--set', 'bar.width=700', '--set', 'bar.height=24',
                              '--exec', "settings.display.order={'chain_time'}; settings.display.enabled.chain_time=true", '--no-crop']),
    ])
    customization = ['--window', 'settings', '--tab', 'Display', '--window-size', '400', '660',
                     '--set', 'bar.docked=false', '--set', 'bar.auto_width=false', '--set', 'bar.width=700',
                     '--set', 'window.compact_navigation=true', '--exec', "dofile('tests/preview/settings_customization_fixture.lua')"]
    cases.extend([
        ('event-modes-input', ['--window', 'settings', '--tab', 'Display', '--scene', 'Limbus', '--frames', '53',
                               '--input-script', str(HERE / 'event_modes_input.json')]),
        ('events-current', ['--window', 'settings', '--tab', 'Events', '--scene', 'Limbus']),
        ('events-current-narrow', ['--window', 'settings', '--tab', 'Events', '--scene', 'Assault', '--window-size', '420', '660',
                                    '--set', 'window.compact_navigation=true']),
        ('events-wanted-narrow', ['--window', 'settings', '--tab', 'Events', '--scene', 'Limbus', '--window-size', '420', '660',
                                   '--set', 'window.compact_navigation=true', '--exec', heading_scroll('Wanted event drops', 'Events')]),
        ('events-cooldowns-narrow', ['--window', 'settings', '--tab', 'Events', '--scene', 'ENM', '--window-size', '420', '660',
                                     '--set', 'window.compact_navigation=true', '--exec', heading_scroll('Entry cooldowns', 'Events')]),
        ('events-account-input', ['--window', 'settings', '--tab', 'Events', '--scene', 'Limbus', '--window-size', '520', '660',
                                   '--frames', '15', '--set', 'window.compact_navigation=true',
                                   '--exec', "PREVIEW.view.account_cooldowns={limbus={remaining=7200},dynamis={remaining=3600}}",
                                   '--exec', heading_scroll('Account timers', 'Events'), '--input-script', str(HERE / 'event_account_input.json')]),
        ('settings-filtered-order', customization + ['--frames', '23', '--exec',
            "settings.display.enabled.progress=false; settings.display.enabled.chain_time=false; settings.display.enabled.rate=true",
            '--input-script', str(HERE / 'settings_filter_input.json')]),
        ('settings-targeted-search', customization + ['--frames', '21', '--exec',
            "settings.window.sections['Display/Readouts and order']=false; settings.window.sections['Display/Position and size']=true; settings.display.colors.chain_time={0.8,0.7,0.4,1}",
            '--input-script', str(HERE / 'settings_search_input.json')]),
        ('settings-add-readout', customization + ['--frames', '27', '--exec', "settings.display.labels.food='Lunch'",
            '--input-script', str(HERE / 'settings_catalog_input.json')]),
        ('settings-preview-width', customization + ['--tab', 'Preview', '--frames', '35',
            '--input-script', str(HERE / 'settings_preview_input.json')]),
        ('settings-auto-layout', ['--full', '--window', 'settings', '--tab', 'Display', '--window-size', '400', '660',
                                 '--set', 'window.compact_navigation=true', '--frames', '21',
                                 '--exec', "dofile('tests/preview/auto_layout_fixture.lua')",
                                 '--input-script', str(HERE / 'auto_layout_input.json')]),
    ])
    for kind in ('Assault', 'Limbus', 'BCNM', 'KSNM', 'ENM'):
        cases.append(('event-bar-' + kind.lower(), ['--hud', '--window', 'momentum', '--scene', kind,
            '--set', 'bar.docked=false', '--set', 'bar.auto_width=false', '--set', 'bar.width=900',
            '--exec', "require('ui.modes').select(settings,'%s')" % kind.lower(), '--input-script', str(HERE / 'event_bar_input.json')]))
    for mode in ('keep', 'always'):
        for anchor in ('top', 'bottom'):
            cases.append(('chat-hold-%s-%s' % (mode, anchor), [
                '--full', '--hud', '--window', 'momentum_bar', '--frames', '18', '--no-crop',
                '--set', 'visibility.mode=' + mode, '--set', 'bar.anchor=' + anchor,
                '--exec', 'settings.preview.show=false', '--input-script', str(HERE / 'chat_hold_input.json')]))
            cases.append(('chat-center-%s-%s' % (mode, anchor), [
                '--full', '--hud', '--window', 'momentum_bar', '--frames', '18', '--no-crop', '--chat-fixture',
                '--set', 'visibility.mode=' + mode, '--set', 'bar.anchor=' + anchor,
                '--set', 'bar.chat_alignment=center', '--exec', 'settings.preview.show=false',
                '--input-script', str(HERE / 'chat_center_hold_input.json')]))
    if len(sys.argv) > 1:
        selected = set(sys.argv[1:])
        missing = selected - {name for name, _ in cases}
        if missing:
            print('Unknown cases: ' + ', '.join(sorted(missing)))
            return 1
        cases = [(name, args) for name, args in cases if name in selected]
    failed = 0
    for name, args in cases:
        command = [sys.executable, str(HERE / 'preview.py'), '--size', '1600', '900', '--out', str(OUT / (name + '.png'))] + args
        result = subprocess.run(command, capture_output=True, text=True)
        print(result.stdout.strip())
        if result.stderr:
            print(result.stderr.strip())
        if result.returncode:
            failed += 1
    print('%d real UI preview cases, %d failures.' % (len(cases), failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
