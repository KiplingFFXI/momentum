local defaults = require('ui.defaults');
local profiles = require('ui.profiles');
local readouts = require('ui.readouts');
local imgui = require('imgui');
local window = require('ui.settings_window');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end

eq(defaults.make().visibility.chat_log, false, 'Expanded chat-log hiding starts off');
for _, value in ipairs({ 'missing', false, true, 1, 'true', {}, function() end }) do
    local settings = defaults.make();
    settings.visibility.chat_log = value;
    if value == 'missing' then settings.visibility.chat_log = nil; end
    settings.visibility.map, settings.bar.hide_typing = false, false;
    defaults.tidy(settings);
    eq(settings.visibility.chat_log, value == true, 'Only a saved true enables expanded chat-log hiding');
    eq(settings.visibility.map, false, 'Validation keeps the separate map choice');
    eq(settings.bar.hide_typing, false, 'Validation keeps the separate typing choice');
end
local damaged = defaults.make();
damaged.visibility = 'invalid';
defaults.tidy(damaged);
eq(damaged.visibility.chat_log, false, 'A malformed visibility section keeps the new option off');

local source = defaults.make();
local saved = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/momentum/');
for _, enabled in ipairs({ true, false }) do
    source.visibility.chat_log = enabled;
    local captured = profiles.capture(source);
    eq(captured.visibility.chat_log, enabled, 'Profile and shared-layout capture keeps the saved choice');
    local restored = defaults.make();
    restored.visibility.chat_log = not enabled;
    profiles.apply(restored, captured);
    defaults.tidy(restored);
    eq(restored.visibility.chat_log, enabled, 'Applying a captured layout restores the saved choice');
    eq(saved:save('Chat log', source), true, 'The preference saves with a profile');
    eq(saved:load('Chat log', restored), true, 'The saved profile reloads');
    defaults.tidy(restored);
    eq(restored.visibility.chat_log, enabled, 'A profile file roundtrip keeps the choice');
end
source.visibility.chat_log = true;
profiles.apply(source, { style = { font_size = 14 } });
defaults.tidy(source);
eq(source.visibility.chat_log, true, 'A style-only profile keeps the existing hide choice');
profiles.apply(source, { visibility = { mode = 'keep' } });
defaults.tidy(source);
eq(source.visibility.chat_log, false, 'An older visibility profile defaults the new option off');

local settings = defaults.make();
settings.window.open, settings.window.tab = true, 'Tracking';
settings.window.sections['Tracking/Visibility'] = true;
local next_open, query;
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function() return next_open; end;
imgui.InputTextWithHint = function(label, _, value)
    if label == '##Find settings' and query then value[1], query = query, nil; return true; end
    return false;
end;
local title = 'Hide while the chat log is open';
local function draw(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end
    return window.draw(settings, readouts.sample('Leveling'), {});
end
local function offered()
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Checkbox' and call[2] == title then return true; end
    end
    return false;
end
draw();
eq(offered(), true, 'Tracking exposes the expanded chat-log checkbox');
draw(title);
eq(settings.visibility.chat_log, true, 'One click enables the new choice');
eq(settings.visibility.mode, 'keep', 'The checkbox does not change the bar visibility policy');
eq(settings.bar.hide_typing, true, 'The checkbox does not change Hide while typing');
settings.visibility.mode = 'always';
draw();
eq(offered(), false, 'Always visible offers no inactive hide controls');
eq(settings.visibility.chat_log, true, 'Always visible preserves the saved hide choice');
settings.visibility.mode = 'keep';
draw();
eq(offered(), true, 'Leaving Always visible restores the hide control');
draw(title);
eq(settings.visibility.chat_log, false, 'The choice can be switched off again');
settings.window.sections['Tracking/Visibility'] = false;
query = 'expanded';
draw();
eq(offered(), true, 'Find settings finds and opens expanded chat-log visibility');
eq(settings.window.sections['Tracking/Visibility'], false, 'Search keeps the saved section collapse');
eq(settings.visibility.chat_log, false, 'Searching does not enable hiding');
return { count = count };
