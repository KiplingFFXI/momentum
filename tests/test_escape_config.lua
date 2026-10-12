local imgui = require('imgui');
local history = require('ui.history');
local player = require('core.player');
local hud = require('ui.hud');
local window = require('ui.settings_window');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function check(value, label) equal(not not value, true, label); end
local active, popup, hidden, text_edit, profile_edit, profile_value = false, false, false, nil, nil, nil;
imgui.IsAnyItemActive = function() return active; end;
imgui.IsWindowFocused = function() return false; end;
imgui.IsKeyPressed = function() return false; end;
imgui.BeginCombo = function(label) return popup and (label == '##Readout list' or label == '##reset_actions' or label == '##Profile'); end;
imgui.InputText = function(label, value)
    if label == '##Label##readout' and text_edit then value[1], text_edit = text_edit, nil; return true; end
    if label == '##Profile name' then
        if profile_edit then value[1], profile_edit = profile_edit, nil; profile_value = value[1]; return true; end
        profile_value = value[1];
    end
    return false;
end;
local is_hidden = player.hidden;
player.hidden = function(flags) return hidden or is_hidden(flags); end;
local hud_draw, config_draw = hud.draw, window.draw;
local hud_draws, config_draws = 0, 0;
hud.draw = function(...) hud_draws = hud_draws + 1; return hud_draw(...); end;
window.draw = function(...) config_draws = config_draws + 1; return config_draw(...); end;
dofile(ADDON_DIR .. '/momentum.lua');
MOCK.fire('load');
local app = MOMENTUM_TEST;
local function frame(seconds)
    MOCK.imgui_calls = {};
    MOCK.frame(seconds or 0.01);
    equal(app.state.broken, false, 'Escape handling remains healthy');
end
local function call_count(name)
    local calls = 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == name then calls = calls + 1; end end
    return calls;
end
local function button_shown(label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Button' and call[2] == label then return true; end end
    return false;
end
local function toggle_config() MOCK.fire('command', { command = '/momentum' }); end
frame();
for _, case in ipairs({
    { name = 'Idle' },
    { name = 'Combat', status = 1 },
    { name = 'Combat with active text input', status = 1, active = true },
    { name = 'Combat with open dropdown', status = 1, popup = true },
    { name = 'Combat while typing in chat', status = 1, typing = true },
    { name = 'Hidden game interface', hidden = true },
    { name = 'Hidden during event', status = 4 },
    { name = 'Manually hidden bar', bar_hidden = true },
    { name = 'Hidden idle bar', hide_idle = true },
}) do
    MOCK.key_escape, MOCK.typing, MOCK.player.status = false, case.typing == true, case.status or 0;
    active, popup, hidden = case.active == true, case.popup == true, case.hidden == true;
    app.state.hidden = case.bar_hidden == true;
    app.settings().tracking.hide_idle = case.hide_idle == true;
    toggle_config();
    frame(0.25);
    equal(app.settings().window.open, true, case.name .. ': configuration starts open');
    local before = history.copy(app.settings());
    local before_session = history.copy(app.view(MOCK.now));
    local config_before, hud_before = config_draws, hud_draws;
    app.state.rings_details = true;
    MOCK.key_escape = true;
    frame();
    equal(app.settings().window.open, false, case.name .. ': Escape closes configuration on the first frame');
    equal(config_draws, config_before, case.name .. ': no settings content is drawn after Escape');
    equal(app.state.rings_details, false, case.name .. ': ring details stop requesting inventory');
    equal(MOCK.player.status, case.status or 0, case.name .. ': combat or event state is unchanged');
    equal(MOCK.typing, case.typing == true, case.name .. ': game chat input is unchanged');
    equal(app.view(MOCK.now).session_exp, before_session.session_exp, case.name .. ': EXP total is unchanged');
    equal(app.view(MOCK.now).paused, before_session.paused, case.name .. ': pause state is unchanged');
    before.window.open = false;
    check(history.equal(app.settings(), before), case.name .. ': only configuration visibility changes');
    if case.hidden or case.status == 4 or case.typing or case.bar_hidden or case.hide_idle then
        equal(hud_draws, hud_before, case.name .. ': HUD visibility rules remain in force');
    else
        equal(hud_draws, hud_before + 1, case.name .. ': ordinary HUD drawing continues');
    end
    local saves = MOCK.saved;
    frame();
    equal(MOCK.saved, saves, case.name .. ': held Escape does not save repeatedly');
    MOCK.key_escape = false;
    active, popup, hidden, MOCK.typing, MOCK.player.status = false, false, false, false, 0;
    app.state.hidden, app.settings().tracking.hide_idle = false, false;
    toggle_config();
    frame();
    equal(app.settings().window.open, true, case.name .. ': configuration can be reopened');
    equal(call_count('SetNextWindowFocus'), 1, case.name .. ': reopening restores focus to the settings window');
    frame();
    equal(call_count('SetNextWindowFocus'), 0, case.name .. ': subsequent frames never steal focus');
    toggle_config();
end

toggle_config();
app.settings().window.sections['Display/Selected readout'] = true;
active, text_edit = true, 'My EXP';
frame();
equal(app.settings().display.labels.progress, 'My EXP', 'Actual text control edits its saved label');
equal(app.state.dirty, true, 'Active text edit waits for completion');
MOCK.key_escape = true;
frame();
equal(app.settings().window.open, false, 'Escape closes an actively edited text field');
equal(app.state.dirty, false, 'Escape finishes the pending edit');
equal(MOCK.settings.last_saved.display.labels.progress, 'My EXP', 'Escape saves the typed label');
equal(MOCK.settings.last_saved.window.open, false, 'Escape saves the closed configuration choice');
equal(app.state.before, nil, 'Escape finishes undo bookkeeping for the pending edit');
MOCK.key_escape, active = false, false;
toggle_config();
popup, MOCK.clicks['Reset layout'] = true, true;
frame();
equal(button_shown('Restore default layout'), true, 'Reset-layout confirmation is open before Escape');
MOCK.key_escape = true;
frame();
MOCK.key_escape, popup = false, false;
toggle_config();
frame();
equal(button_shown('Restore default layout'), false, 'Reopening does not restore an abandoned layout-reset confirmation');
equal(app.settings().display.labels.progress, 'My EXP', 'Cancelling a reset confirmation preserves the edited layout');
check(app.services.save_profile('Escape test'), 'Profile confirmation fixture is saved');
app.settings().window.tab = 'Profiles';
profile_edit = 'Escape test';
frame();
MOCK.clicks['Save profile'] = true;
frame();
equal(button_shown('Replace saved profile'), true, 'Replace-profile confirmation is open before Escape');
MOCK.key_escape = true;
frame();
MOCK.key_escape = false;
toggle_config();
frame();
equal(button_shown('Replace saved profile'), false, 'Reopening cancels the abandoned replacement');
equal(profile_value, 'Escape test', 'Reopening preserves the typed profile name');
popup, MOCK.clicks['Escape test'] = true, true;
frame();
popup, MOCK.clicks['Delete profile'] = false, true;
frame();
equal(button_shown('Delete saved profile'), true, 'Delete-profile confirmation is open before Escape');
MOCK.key_escape = true;
frame();
MOCK.key_escape = false;
toggle_config();
frame();
equal(button_shown('Delete saved profile'), false, 'Reopening cancels the abandoned profile deletion');
equal(app.services.profile_names(true)[1], 'Escape test', 'Cancelling profile deletion keeps the saved profile');
check(app.services.session_reset(), 'Saved-session deletion fixture is archived');
app.settings().window.tab = 'Session';
frame();
local records = #app.services.session_history();
MOCK.clicks['Delete selected session'] = true;
frame();
equal(button_shown('Delete record now'), true, 'Saved-session deletion confirmation is open before Escape');
MOCK.key_escape = true;
frame();
MOCK.key_escape = false;
toggle_config();
frame();
equal(button_shown('Delete record now'), false, 'Reopening cancels the abandoned saved-session deletion');
equal(#app.services.session_history(), records, 'Cancelling session deletion keeps the archive');
app.state.broken = true;
MOCK.key_escape = true;
MOCK.frame(0.01);
equal(app.settings().window.open, false, 'Escape still closes configuration after a drawing error');
equal(app.state.broken, true, 'Escape does not conceal the existing drawing error');
equal(#MOCK.commands, 0, 'Escape handling sends no gameplay commands');
return { count = count };
