local imgui = require('imgui');
local history = require('ui.history');
local settings, services = PREVIEW.settings, PREVIEW.services;
dofile('tests/preview/alerts_fixture.lua');
local event_case = PREVIEW.sound_storage_case == 'event';
local selected = event_case and 'Event custom.wav' or 'Food custom.wav';
PREVIEW.sound_storage_row = event_case and 'farm_goal' or 'food_end';
PREVIEW.sound_storage_conflict = event_case;
settings.window.sections['Alerts/Food'] = not event_case;
settings.window.sections['Alerts/Farming'] = event_case;
if event_case then
    settings.alerts.events.farm_goal.sound = true;
    settings.alerts.events.farm_goal.file = selected;
    settings.alerts.events.farm_goal.volume = 37;
else settings.alerts.food_enabled, settings.alerts.food_sound = true, selected; end
PREVIEW.sound_storage_before = history.copy(settings.alerts);
PREVIEW.sound_storage_copies, PREVIEW.sound_storage_refreshes = 0, 0;
PREVIEW.sound_storage_saved = false;
local folder = 'X:\\PhoenixXI\\config\\addons\\momentum\\sounds\\';
services.sound_folder = function() return folder; end;
services.copy = function(value) PREVIEW.sound_storage_clipboard = value; end;
services.sound_files = function() return { 'FF VII Save.mp3', 'FF IX Moogle.mp3', selected }; end;
services.sound_location = function(name)
    return name == selected and { kind = 'addon', can_save = not PREVIEW.sound_storage_exists,
        permanent_exists = PREVIEW.sound_storage_exists, saved_copy = PREVIEW.sound_storage_saved }
        or { kind = 'bundled' };
end;
services.sound_save_custom = function(name)
    assert(name == selected, 'The wrong custom sound was copied');
    PREVIEW.sound_storage_copies = PREVIEW.sound_storage_copies + 1;
    if event_case then return false, 'A file with this name already exists in the permanent folder. Rename one of the files and try again.'; end
    PREVIEW.sound_storage_saved = true;
    return true, 'Saved a copy in the permanent folder.';
end;
services.sound_refresh = function()
    PREVIEW.sound_storage_refreshes = PREVIEW.sound_storage_refreshes + 1;
    PREVIEW.sound_storage_saved = false;
end;
local button = imgui.Button;
imgui.Button = function(label, ...)
    local value = button(label, ...);
    if label == 'Copy sound folder path' or label == 'Copy to permanent folder' then
        local right = imgui.GetItemRectMax();
        local left = imgui.GetWindowPos();
        local width = imgui.GetWindowSize();
        assert(right <= left + width - 6, 'Sound storage button overflows the settings window');
    end
    return value;
end;
function PREVIEW.assert_sound_storage_copy(expected)
    assert(PREVIEW.sound_storage_copies == expected, 'A sound copy did not follow the explicit button click');
    assert(PREVIEW.sound_storage_saved == not event_case, 'A failed copy was marked protected or a successful copy was forgotten');
    assert(history.equal(settings.alerts, PREVIEW.sound_storage_before), 'Copying changed filenames, sound toggles, or volume');
    assert(PREVIEW.sound_storage_clipboard == folder, 'The permanent sound folder path was not copied');
    assert(not PREVIEW.sound_plays and PREVIEW.notification_calls == 0, 'Copying started sound playback or a test notification');
    assert(#MOCK.commands == 0, 'Sound storage controls sent game commands');
end;
