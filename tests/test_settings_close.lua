local imgui = require('imgui');
local defaults = require('ui.defaults');
local window = require('ui.settings_window');
local readouts = require('ui.readouts');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local settings, view = defaults.make(), readouts.sample();
settings.window.open = true;
local closing, input, active, label_edit = false, nil, false, nil;
local reset_count, saves, deletes, session_deletes = 0, 0, 0, 0;
local original_begin = imgui.Begin;
imgui.Begin = function(name, open, ...)
    if name == 'Momentum##settings' and closing then open[1], closing = false, false; end
    return original_begin(name, open, ...);
end;
imgui.IsAnyItemActive = function() return active; end;
local next_open;
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function() return next_open; end;
imgui.BeginCombo = function(label) return label == '##reset_actions' or label == '##Profile'; end;
local shown_name;
imgui.InputText = function(label, value)
    if label == '##Label##readout' and label_edit then value[1], label_edit = label_edit, nil; return true; end
    if label == '##Profile name' then
        if input then value[1], input = input, nil; end
        shown_name = value[1];
    end
    return false;
end;
local services = {
    reset = function() reset_count = reset_count + 1; end,
    profile_names = function() return { 'Saved' }; end,
    save_profile = function() saves = saves + 1; return true; end,
    delete_profile = function() deletes = deletes + 1; return true; end,
    session_history = function() return {{ id = '100:1', name = 'Old run', created = 1700000000, saved = 1700000010 }}; end,
    session_delete = function() session_deletes = session_deletes + 1; return true; end,
};
local function draw(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end
    return window.draw(settings, view, services);
end
local function button(label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Button' and call[2] == label then return true; end end
    return false;
end
local function close_and_reopen(prompt)
    eq(button(prompt), true, 'Explicit action opened ' .. prompt);
    closing, active, MOCK.mouse_down = true, true, true;
    eq(draw(), true, 'Title-bar close reports a changed setting even while mouse or text is active');
    eq(settings.window.open, false, 'Title-bar X closes configuration');
    active, MOCK.mouse_down = false, false;
    settings.window.open = true;
    draw();
    eq(button(prompt), false, 'Reopening does not revive ' .. prompt);
    local focuses = 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'SetNextWindowFocus' then focuses = focuses + 1; end end
    eq(focuses, 1, 'Reopened settings receive focus once');
    eq(draw(), false, 'Reopening produces no delayed edit or action');
end
draw('Reset layout');
close_and_reopen('Restore default layout');
eq(reset_count, 0, 'Closing never resets the layout');
settings.window.tab, input = 'Profiles', 'Saved';
draw('Save profile');
close_and_reopen('Replace saved profile');
eq(shown_name, 'Saved', 'Closing preserves the typed profile name');
eq(saves, 0, 'Closing never overwrites a profile');
draw('Saved');
draw('Delete profile');
close_and_reopen('Delete saved profile');
eq(deletes, 0, 'Closing never deletes a profile');
settings.window.tab = 'Session';
draw('Delete selected session');
close_and_reopen('Delete record now');
eq(session_deletes, 0, 'Closing never deletes a saved session');

window.close();
MOCK.load_addon();
MOCK.fire('load');
local app = MOMENTUM_TEST;
local function frame(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end
    MOCK.frame(0.25);
    eq(app.state.broken, false, 'Full entry remains healthy');
end
local function command() MOCK.fire('command', { command = '/momentum' }); end
frame();
eq(app.services.save_profile('Audit profile'), true, 'Save full-entry profile fixture');
for _, route in ipairs({ 'command', 'character' }) do
    local function finish_close(prompt)
        eq(button(prompt), true, route .. ': confirmation is visible');
        if route == 'command' then command();
        else
            local next_settings = defaults.make();
            next_settings.window.open = false;
            MOCK.player.server_id = MOCK.player.server_id + 1;
            MOCK.settings.current = next_settings;
            for _, callback in pairs(MOCK.settings.callbacks) do callback(next_settings); end
        end
        eq(app.settings().window.open, false, route .. ': configuration is closed');
        frame();
        command();
        frame();
        eq(button(prompt), false, route .. ': old confirmation does not reappear');
    end
    if not app.settings().window.open then command(); end
    app.settings().window.tab, input = 'Profiles', 'Audit profile';
    frame('Save profile');
    finish_close('Replace saved profile');
    app.settings().window.tab = 'Profiles';
    frame('Audit profile');
    frame('Delete profile');
    finish_close('Delete saved profile');
    eq(app.services.profile_names(true)[1], 'Audit profile', route .. ': saved profile survives');
    frame('Reset layout');
    finish_close('Restore default layout');
    eq(app.services.session_reset(), true, route .. ': archive a real session');
    app.settings().window.tab = 'Session';
    frame('Delete selected session');
    local old_character = MOCK.player.server_id;
    local saved_count = #app.sessions:history(old_character);
    finish_close('Delete record now');
    eq(#app.sessions:history(old_character), saved_count + (route == 'character' and 1 or 0),
        route .. ': prior archive survives, with current session archived on character switch');
end
app.settings().window.tab = 'Display';
app.settings().window.sections['Display/Selected readout'] = true;
label_edit, active = 'Saved on close', true;
frame();
eq(app.state.dirty, true, 'An active label edit is pending');
command();
eq(app.state.dirty, false, 'Command close finishes the active edit');
eq(MOCK.settings.last_saved.display.labels.progress, 'Saved on close', 'Command close saves entered text');
eq(MOCK.settings.last_saved.window.open, false, 'Command close saves visibility');
active = false;
command();
frame();
eq(app.settings().display.labels.progress, 'Saved on close', 'Reopening preserves the command-closed edit');
eq(#MOCK.commands, 0, 'All close routes send no gameplay commands');
return { count = count };
