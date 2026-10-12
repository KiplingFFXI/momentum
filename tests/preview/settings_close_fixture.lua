local app = assert(MOMENTUM_TEST, 'Run this fixture with --full');
local imgui = require('imgui');
local settings = app.settings();
local draw = PREVIEW.draw;
settings.window.open, settings.window.tab = true, 'Display';
settings.window.x, settings.window.y, settings.window.width, settings.window.height = 40, 90, 920, 760;
settings.window.sections['Display/Readouts and order'] = true;
settings.window.sections['Display/Selected readout'] = false;
settings.bar.docked, settings.bar.auto_width = false, false;
settings.bar.x, settings.bar.y, settings.bar.width = 40, 40, 920;
settings.preview.show = false;
MOCK.player.status = 1;
local buttons = {};
local button = imgui.Button;
imgui.Button = function(label, ...)
    buttons[label] = true;
    return button(label, ...);
end;
local input = imgui.InputText;
imgui.InputText = function(label, ...)
    local changed = input(label, ...);
    if label == '##Label##readout' then PREVIEW.label_active = imgui.IsItemActive(); end
    return changed;
end;
local header = imgui.CollapsingHeader;
imgui.CollapsingHeader = function(label, ...)
    local open = header(label, ...);
    if PREVIEW.edit_label and label:find('##section_Display/Selected readout', 1, true) then imgui.SetScrollHereY(0); end
    return open;
end;
function PREVIEW.assert_confirmation()
    assert(buttons['Restore default layout'], 'Actual menu choice opens reset confirmation');
end
function PREVIEW.assert_closed()
    assert(not settings.window.open and not app.state.broken, 'Title-bar X closes a healthy config in combat');
    assert(MOCK.settings.last_saved.window.open == false, 'Closed configuration choice is saved');
    assert(MOCK.player.status == 1 and #MOCK.commands == 0, 'Closing sends no gameplay commands or combat changes');
end
function PREVIEW.reopen() MOCK.fire('command', { command = '/momentum' }); end
function PREVIEW.assert_reopened()
    assert(settings.window.open and not buttons['Restore default layout'], 'Reopening cancels abandoned reset confirmation');
    assert(not imgui.IsAnyItemActive(), 'Reopening does not retain active text input');
end
function PREVIEW.show_label()
    settings.window.sections['Display/Readouts and order'] = false;
    settings.window.sections['Display/Selected readout'] = true;
    settings.display.labels.progress = '';
    PREVIEW.edit_label = true;
end
function PREVIEW.assert_editing()
    assert(settings.display.labels.progress == 'My EXP' and PREVIEW.label_active, 'Real text input is active before X');
end
function PREVIEW.assert_saved()
    assert(settings.display.labels.progress == 'My EXP', 'X keeps the entered label');
    assert(MOCK.settings.last_saved.display.labels.progress == 'My EXP', 'X saves the edited label');
end
return function()
    buttons = {};
    PREVIEW.label_active = false;
    draw();
    if PREVIEW.frame == PREVIEW.last_frame then
        PREVIEW.assert_reopened();
        PREVIEW.assert_saved();
        PREVIEW.log('PASS: Real title-bar X cancels the reset confirmation, saves active text, and reopens cleanly in combat.');
    end
end;
