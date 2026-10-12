local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local imgui = require('imgui');
local window = require('ui.settings_window');
local count = 0;
local function eq(actual, expected, title)
    count = count + 1;
    assert(actual == expected, title .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local settings = defaults.make();
settings.window.open = true;
local view = readouts.sample('Leveling');
local resets, current, problem = 0, '1:1', nil;
local failure_changes_session, replacement;
local services = {
    session_current = function() return current and { id = current } or nil; end,
    session_reset = function()
        resets = resets + 1;
        if problem then
            if failure_changes_session then current = replacement; end
            return false, problem;
        end
        return true;
    end,
};
local next_open, toggle, query;
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function(label)
    if toggle and label:find(toggle, 1, true) then toggle = nil; return not next_open; end
    return next_open;
end;
imgui.InputText = function(label, value)
    if label == '##Find settings' and query ~= nil then value[1], query = query, nil; return true; end
    return false;
end;
imgui.InputTextWithHint = function(label, _, value) return imgui.InputText(label, value); end;
local function draw(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end
    return window.draw(settings, view, services);
end
local function text(value)
    for _, item in ipairs(MOCK.imgui_calls) do
        if item[1] == 'TextUnformatted' and item[2] == value then return true; end
    end
    return false;
end
local function button(value)
    for _, item in ipairs(MOCK.imgui_calls) do
        if item[1] == 'Button' and item[2] == value then return true; end
    end
    return false;
end

draw();
eq(button('Reset session'), true, 'Reset is visible on the initial Display tab');
eq(button('Pause session'), true, 'Pause is beside the reset control');
eq(resets, 0, 'Rendering never changes session');
draw('Reset session');
eq(resets, 1, 'One click saves and resets the session');
eq(button('Save and reset session'), false, 'Reset needs no second button');
eq(text('Previous session saved. New session started.'), true, 'Successful reset is reported');
draw();
eq(resets, 1, 'Later frames do not repeat the reset');
problem = 'The session file changed outside the addon.';
draw('Reset session');
eq(resets, 2, 'A click calls reset once');
eq(text(problem), true, 'Actual persistence failure is shown');
draw();
eq(resets, 2, 'Failed saves are not retried by rendering');
eq(button('Reset session'), true, 'Reset remains available for an explicit retry');
problem = nil;
draw('Reset session');
eq(resets, 3, 'Retry is explicit');
eq(text('Previous session saved. New session started.'), true, 'Success is reported only after true service result');
current = '2:3';
draw();
eq(resets, 3, 'A job change never resets a session by itself');
current = nil;
problem = 'No session is running for this character.';
draw('Reset session');
eq(resets, 4, 'Unavailable session is handled by the reset service');
eq(text(problem), true, 'Unavailable session message is visible');
current = '3:1';
draw();
eq(resets, 4, 'Loading a character never retries an old reset click');
problem, failure_changes_session, replacement = 'The new session file could not be saved.', true, '3:2';
draw('Reset session');
eq(resets, 5, 'A reset with a failed new-record write is called once');
eq(text('The session was reset, but saving failed: ' .. problem), true, 'Changed session and save failure are both reported');
draw();
eq(resets, 5, 'A new-record save failure does not reset the session again');
eq(text('The session was reset, but saving failed: ' .. problem), true, 'Save failure remains visible on following frames');
problem, failure_changes_session, replacement = nil, false, nil;
settings.window.tab = 'Appearance';
draw();
eq(button('Reset session'), true, 'Reset remains visible on Appearance');
settings.window.tab = 'Session';
draw();
eq(button('Reset session'), true, 'Reset remains visible on Session');

settings.window.tab = 'Display';
draw();
eq(settings.window.sections['Display/Readouts and order'], nil, 'Drawing default folds creates no preference');
toggle = '##section_Display/Readouts and order';
draw();
eq(settings.window.sections['Display/Readouts and order'], false, 'User collapse is saved');
draw();
eq(button('Up##order'), false, 'Saved collapse hides its controls');
query = 'order';
draw();
eq(button('Up##order'), true, 'Search expands the relevant page controls');
eq(settings.window.sections['Display/Readouts and order'], false, 'Search does not overwrite saved collapse');
query = '';
draw();
eq(button('Up##order'), false, 'Clearing search restores saved collapse');
toggle = '##section_Display/Readouts and order';
draw();
eq(settings.window.sections['Display/Readouts and order'], true, 'User reopening is saved');
draw('04  EXP/HR');
eq(settings.window.sections['Display/Selected readout'], true, 'Selecting a readout opens its edit controls');

settings.window.tab = 'Tracking';
draw();
eq(button('Refresh##food_sound'), false, 'Food-end sound no longer appears in Tracking');
settings.window.tab = 'Alerts';
local id_stack, checks, check_click = {}, {}, nil;
local original_push, original_pop, original_checkbox = imgui.PushID, imgui.PopID, imgui.Checkbox;
imgui.PushID = function(id) id_stack[#id_stack + 1] = id; original_push(id); end;
imgui.PopID = function() table.remove(id_stack); original_pop(); end;
imgui.Checkbox = function(label, value)
    local key = tostring(id_stack[#id_stack]) .. '/' .. label;
    checks[key] = value[1];
    if key == check_click then check_click = nil; value[1] = not value[1]; return true; end
    return false;
end;
local plays, tests = 0, 0;
services.sound_play = function() plays = plays + 1; return true; end;
services.notification_test = function() tests = tests + 1; end;
draw();
for _, group in ipairs({ 'Food', 'EXP chains', 'Dedication', 'EXP rings', 'Levels and merit points', 'Level Sync and missed EXP' }) do
    eq(settings.window.sections['Alerts/' .. group], nil, group .. ' starts folded without writing a preference');
end
eq(next(checks), nil, 'Initially collapsed groups have no alert controls');
eq(button('Refresh##food_sound'), false, 'Food sound controls wait for their group to open');
eq(button('Test notification'), false, 'Disabled folded alerts expose no automatic test action');
toggle = '##section_Alerts/Food';
eq(draw(), true, 'Opening Food reports a settings change');
eq(settings.window.sections['Alerts/Food'], true, 'Food group opening is saved');
eq(button('Refresh##food_sound'), true, 'Open Food group contains the sound refresh control');
eq(button('Play##food_sound'), true, 'Open Food group retains manual playback while disabled');
eq(checks['food_end/Play sound'], false, 'Food sound checkbox reflects its saved disabled value');
eq(checks['food_soon/Show notice'], false, 'Food warning notice has its own event ID');
eq(checks['food_soon/Play sound'], false, 'Food warning sound has its own event ID');
check_click = 'food_end/Play sound';
eq(draw(), true, 'Food checkbox reports a persistable change');
eq(settings.alerts.food_enabled, true, 'Food checkbox edits the original food_enabled key');
eq(settings.alerts.events.food_soon.sound, false, 'Food-end checkbox does not change the warning sound');
eq(plays, 0, 'Enabling food sound does not play it');
toggle = '##section_Alerts/EXP chains';
draw();
check_click = 'chain_soon/Show notice';
eq(draw(), true, 'Notice checkbox reports a persistable change');
eq(settings.alerts.events.chain_soon.visual, true, 'Chain notice choice is saved');
eq(settings.alerts.events.chain_soon.sound, false, 'Notice checkbox leaves the sound choice alone');
eq(button('Test notification'), true, 'An enabled alert exposes its explicit test button');
check_click = 'chain_soon/Play sound';
eq(draw(), true, 'Sound checkbox reports a persistable change');
eq(settings.alerts.events.chain_soon.visual, true, 'Adding chain sound preserves its notice');
eq(settings.alerts.events.chain_soon.sound, true, 'Chain sound choice is saved');
eq(settings.alerts.events.food_soon.sound, false, 'Repeated sound labels cannot change another alert');
check_click = 'chain_soon/Show notice';
draw();
eq(settings.alerts.events.chain_soon.visual, false, 'Notice can be disabled independently');
eq(settings.alerts.events.chain_soon.sound, true, 'Sound remains enabled independently');
eq(plays, 0, 'Editing alert checkboxes never plays food audio');
eq(tests, 0, 'Editing alert checkboxes never tests notifications');
toggle = '##section_Alerts/EXP chains';
draw();
eq(settings.window.sections['Alerts/EXP chains'], false, 'Chain group collapse is saved');
eq(settings.alerts.events.chain_soon.sound, true, 'Collapsing a group preserves its enabled alert');
checks = {};
draw();
eq(checks['chain_soon/Play sound'], nil, 'Saved group collapse hides its controls');
eq(settings.alerts.food_enabled, true, 'Later frames preserve the food enable choice');
eq(settings.alerts.events.chain_soon.sound, true, 'Later frames preserve the chain enable choice');
query = 'chain';
checks = {};
draw();
eq(checks['chain_soon/Play sound'], true, 'Searching EXP chains exposes the saved sound checkbox');
eq(settings.window.sections['Alerts/EXP chains'], false, 'Search does not overwrite group collapse');
query = '';
checks = {};
draw();
eq(checks['chain_soon/Play sound'], nil, 'Clearing search restores the saved group collapse');
eq(settings.alerts.events.chain_soon.sound, true, 'Searching never disables the saved alert');
eq(#id_stack, 0, 'Alert IDs remain balanced across full settings renders');
imgui.PushID, imgui.PopID, imgui.Checkbox = original_push, original_pop, original_checkbox;
return { count = count };
