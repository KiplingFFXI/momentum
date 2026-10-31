local imgui = require('imgui');
local defaults = require('ui.defaults');
local details = require('ui.details');
local history = require('ui.history');
local checks = 0;
local function equal(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end

local settings = defaults.make();
local opened, clicks, selected, notes, buttons = {}, {}, {}, {}, {};
local current_id, disabled = '', false;
local changed, looked_up, copied, tested, played, refreshed = 0, 0, nil, 0, 0, 0;
local saves, save_okay, save_message = {}, true, 'Saved a copy in the permanent folder.';
local locations = {
    ['FF VII Save.mp3'] = { kind = 'bundled' },
    ['Permanent.wav'] = { kind = 'permanent' },
    ['Addon.wav'] = { kind = 'addon', can_save = true },
    ['Other.wav'] = { kind = 'addon', can_save = true },
    ['Missing.wav'] = { kind = 'missing' },
};
local folder = 'Z:\\Phoenix\\config\\addons\\momentum\\sounds\\';
local services = {
    sound_folder = function() return folder; end,
    copy = function(value) copied = value; end,
    sound_files = function() return { 'FF VII Save.mp3', 'Permanent.wav', 'Addon.wav', 'Other.wav', 'Missing.wav' }; end,
    sound_location = function(name) looked_up = looked_up + 1; return locations[name]; end,
    sound_save_custom = function(name)
        saves[#saves + 1] = name;
        if save_okay then
            locations[name].saved_copy, locations[name].permanent_exists, locations[name].can_save = true, true, false;
        end
        return save_okay, save_message;
    end,
    sound_refresh = function()
        refreshed = refreshed + 1;
        for _, location in pairs(locations) do location.saved_copy = nil; end
    end,
    sound_play = function() played = played + 1; return true; end,
    notification_test = function() tested = tested + 1; return true; end,
};
local ui = {
    section = function(name) return opened[name] == true; end,
    note = function(text) notes[#notes + 1] = { id = current_id, text = text }; end,
    tip = function() end, help = function() end,
    checkbox = function() end, slider = function() end,
    changed = function() changed = changed + 1; end,
    combo = function(_, _, _, apply)
        if selected[current_id] ~= nil then apply(selected[current_id]); selected[current_id] = nil; end
    end,
};
imgui.PushID = function(id) current_id = tostring(id); end;
imgui.PopID = function() current_id = ''; end;
imgui.BeginDisabled = function(value) disabled = value == true; end;
imgui.EndDisabled = function() disabled = false; end;
imgui.Button = function(label)
    local key = current_id .. '/' .. label;
    buttons[key] = true;
    local click = clicks[key]; clicks[key] = nil;
    return click == true and not disabled;
end;
local function draw(click)
    notes, buttons = {}, {};
    if click then clicks[click] = true; end
    details.alerts(settings, {}, services, ui);
end
local function contains(text, id)
    for _, note in ipairs(notes) do
        if (id == nil or note.id == id) and note.text:find(text, 1, true) then return true; end
    end
    return false;
end

draw();
equal(contains('Custom sounds go in config/addons/momentum/sounds/.'), true, 'Permanent folder guidance is visible with every group closed');
equal(buttons['/Copy sound folder path'], true, 'The full folder path can be copied without opening an alert');
equal(looked_up, 0, 'Collapsed alert groups do not request selected file origins');
equal(#saves, 0, 'Opening Alerts never copies audio');
draw('/Copy sound folder path');
equal(copied, folder, 'The clipboard receives the actual permanent folder path');
equal(changed, 0, 'Copying a path does not dirty settings');

opened.Food = true;
settings.alerts.food_sound = 'Addon.wav';
local before = history.copy(settings.alerts);
draw();
equal(contains('Update warning:', 'food_end'), true, 'Food sound shows the replaceable addon-folder warning');
equal(buttons['food_end/Copy to permanent folder'], true, 'An addon-local food sound offers an explicit copy');
equal(history.equal(settings.alerts, before), true, 'Viewing sound guidance leaves all alert choices unchanged');
equal(played, 0, 'Viewing an unsafe sound does not play it');
draw('food_end/Copy to permanent folder');
equal(saves[1], 'Addon.wav', 'The explicit food action copies only the selected filename');
equal(contains('Saved a copy', 'food_end'), true, 'A successful copy is explained immediately');
equal(settings.alerts.food_sound, 'Addon.wav', 'Copying leaves the chosen filename intact');
equal(changed, 0, 'Copying a file never changes alert settings');
equal(played, 0, 'Copying a file never starts playback');
draw();
equal(buttons['food_end/Copy to permanent folder'], nil, 'A recorded successful copy is not offered again every frame');
equal(contains('Update warning:', 'food_end'), true, 'Copying does not hide the sound\'s current addon origin');
equal(contains('Saved a copy', 'food_end'), true, 'A saved-copy message stays with that selected file');
draw('food_end/Refresh##food_sound');
draw();
equal(refreshed, 1, 'The existing Refresh control is retained');
equal(buttons['food_end/Copy to permanent folder'], nil, 'Refreshing does not offer to copy over an existing permanent file');
equal(contains('already in the permanent folder', 'food_end'), true, 'Refresh recognizes a same-name permanent file');
equal(contains('using the addon copy', 'food_end'), true, 'The current playback source is explained without assuming both files match');
equal(contains('Update warning:', 'food_end'), true, 'The addon origin remains visible after recognizing a permanent file');

for _, file in ipairs({ 'FF VII Save.mp3', 'Permanent.wav', 'Missing.wav', '' }) do
    selected.food_end = file;
    draw();
    equal(contains('Update warning:', 'food_end'), false, 'Only addon-local custom files receive the update warning');
    equal(buttons['food_end/Copy to permanent folder'], nil, 'Bundled, permanent, missing and empty selections never offer an unsafe copy');
end

opened.Farming = true;
local event = settings.alerts.events.farm_goal;
event.sound, event.file, event.volume = true, 'Other.wav', 37;
save_okay, save_message = false, 'A file with that name already exists. Nothing was replaced.';
before = history.copy(settings.alerts);
local edits_before = changed;
draw('farm_goal/Copy to permanent folder');
equal(saves[#saves], 'Other.wav', 'Event alerts use the same explicit protection action');
equal(contains('Nothing was replaced.', 'farm_goal'), true, 'A copy conflict is shown on the matching event');
equal(contains('Nothing was replaced.', 'food_end'), false, 'An event conflict does not appear on a different alert');
equal(history.equal(settings.alerts, before), true, 'Copy failure preserves filenames, toggles, volumes and cooldowns');
equal(changed, edits_before, 'A copy failure does not dirty settings');
equal(tested, 0, 'Copying never tests a notification');

settings.alerts = history.copy(settings.alerts);
draw();
equal(contains('Nothing was replaced.'), false, 'A new character or profile cannot inherit another settings table\'s copy error');
draw('farm_goal/Copy to permanent folder');
details.cancel_pending();
draw();
equal(contains('Nothing was replaced.'), false, 'Closing settings clears pending copy feedback');

draw('food_end/Play##food_sound');
equal(played, 0, 'An empty food selection still cannot play');
selected.food_end = 'Permanent.wav';
draw('food_end/Play##food_sound');
equal(played, 1, 'The existing Play button still works with a permanent custom sound');
draw('farm_goal/Test notification');
equal(tested, 1, 'Event notification testing remains available');
equal(#MOCK.commands, 0, 'Sound storage controls send no game commands');
return { count = checks };
