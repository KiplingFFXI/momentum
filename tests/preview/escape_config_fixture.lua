local app = assert(MOMENTUM_TEST, 'Run this fixture with --full');
local imgui = require('imgui');
local bit = require('bit');
local settings = app.settings();
local draw = PREVIEW.draw;
settings.window.open, settings.window.tab = true, 'Display';
settings.window.x, settings.window.y, settings.window.width, settings.window.height = 40, 90, 920, 760;
settings.window.sections['Display/Readouts and order'] = true;
settings.window.sections['Display/Selected readout'] = false;
settings.bar.docked, settings.bar.auto_width = false, false;
settings.bar.x, settings.bar.y, settings.bar.width = 40, 40, 920;
MOCK.player.status = 1;
local popup_flags = bit.bor(ImGuiPopupFlags_AnyPopupId, ImGuiPopupFlags_AnyPopupLevel);
local input = imgui.InputText;
imgui.InputText = function(label, ...)
    local changed = input(label, ...);
    if label == '##Label##readout' then PREVIEW.label_active = imgui.IsItemActive(); end
    return changed;
end;
local headers = imgui.CollapsingHeader;
imgui.CollapsingHeader = function(label, ...)
    local open = headers(label, ...);
    if PREVIEW.show_label and label:find('##section_Display/Selected readout', 1, true) then imgui.SetScrollHereY(0); end
    return open;
end;
function PREVIEW.assert_open_popup()
    assert(settings.window.open and PREVIEW.popup, 'A real dropdown or popup must be open before Escape');
end
function PREVIEW.assert_closed()
    assert(not settings.window.open, 'Escape closes config during combat');
    assert(not PREVIEW.popup, 'No owned popup remains open after Escape');
    assert(MOCK.player.status == 1 and #MOCK.commands == 0, 'Escape sends no gameplay commands or combat changes');
    assert(not app.state.broken, 'Full entry remains healthy');
end
function PREVIEW.reopen()
    MOCK.fire('command', { command = '/momentum' });
end
function PREVIEW.assert_reopened()
    assert(settings.window.open and not PREVIEW.popup, 'Reopening config does not revive a stale popup');
    assert(not imgui.IsAnyItemActive(), 'Reopened configuration does not retain the old active input');
end
function PREVIEW.show_label_editor()
    settings.window.sections['Display/Readouts and order'] = false;
    settings.window.sections['Display/Selected readout'] = true;
    settings.display.labels.progress = '';
    PREVIEW.show_label = true;
end
function PREVIEW.assert_editing()
    assert(settings.display.labels.progress == 'My EXP', 'Real text input updates the readout label');
    assert(PREVIEW.label_active, 'The real text input is still active before Escape');
end
function PREVIEW.assert_saved_edit()
    PREVIEW.assert_closed();
    assert(settings.display.labels.progress == 'My EXP', 'Escape keeps the entered label');
    assert(MOCK.settings.last_saved.display.labels.progress == 'My EXP', 'Escape saves the active text edit');
end
function PREVIEW.show_catalog()
    PREVIEW.show_label = false;
    settings.window.sections['Display/Readouts and order'] = true;
    settings.window.sections['Display/Selected readout'] = false;
end
return function()
    PREVIEW.label_active = false;
    draw();
    PREVIEW.popup = imgui.IsPopupOpen('', popup_flags);
    if PREVIEW.frame == PREVIEW.last_frame then
        PREVIEW.assert_reopened();
        assert(settings.display.labels.progress == 'My EXP', 'Reopening keeps the saved text edit');
        PREVIEW.log('PASS: Escape closes real combat config with dropdown, active text, and catalog popup; reopening is clear and the edit is saved.');
    end
end;
