local defaults = require('ui.defaults');
local profiles = require('ui.profiles');
local sound = require('core.sound');
local count = 0;
local function eq(actual, expected, title)
    count = count + 1;
    assert(actual == expected, title .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local saved = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/momentum/');
for index, name in ipairs({ 'My alert.wav', string.rep('a', 157) .. '.mp3', string.rep('b', 196) .. '.wav', string.rep('c', 196) .. '.MP3' }) do
    MOCK.fs[sound.FOLDER .. name] = true;
    eq(sound.use(name, true), true, 'The player accepts the selected sound ' .. index);
    local settings = defaults.make();
    settings.alerts.food_sound = name;
    for _, alert in pairs(settings.alerts.events) do alert.file = name; end
    defaults.tidy(settings);
    eq(settings.alerts.food_sound, name, 'Tidying preserves the whole food filename ' .. index);
    for _, alert in ipairs(defaults.ALERTS) do
        eq(settings.alerts.events[alert[1]].file, name, 'Tidying preserves ' .. alert[1] .. ' filename ' .. index);
    end
    eq(saved:save('Boundary ' .. index, settings), true, 'The sound selection can be saved ' .. index);
    local restored = defaults.make();
    eq(saved:load('Boundary ' .. index, restored), true, 'The sound selection can be loaded ' .. index);
    defaults.tidy(restored);
    eq(restored.alerts.food_sound, name, 'Food keeps its exact filename after a JSON save and reload ' .. index);
    eq(restored.alerts.events.event_time.file, name, 'Event sound keeps its exact filename after a JSON save and reload ' .. index);
    eq(sound.use(restored.alerts.food_sound, true), true, 'The restored food filename can still be selected ' .. index);
    eq(sound.use(restored.alerts.events.event_time.file, true), true, 'The restored event filename can still be selected ' .. index);
end

local valid_prefix = string.rep('d', 196) .. '.mp3';
for _, name in ipairs({ string.rep('e', 197) .. '.wav', valid_prefix .. 'x' }) do
    eq(#name, 201, 'The rejected fixture crosses the player limit by one byte');
    MOCK.fs[sound.FOLDER .. name], MOCK.fs[sound.FOLDER .. valid_prefix] = true, true;
    eq(sound.use(name, true), false, 'The player rejects a filename over its limit');
    local settings = defaults.make();
    settings.alerts.food_sound, settings.alerts.events.level.file = name, name;
    defaults.tidy(settings);
    eq(settings.alerts.food_sound, '', 'An overlong food filename is cleared without inventing a shorter sound');
    eq(settings.alerts.events.level.file, '', 'An overlong event filename is cleared without inventing a shorter sound');
end
local settings = defaults.make();
settings.alerts.food_sound, settings.alerts.events.level.file = '..', '.';
defaults.tidy(settings);
eq(settings.alerts.food_sound, '', 'The empty-directory sentinel remains unavailable');
eq(settings.alerts.events.level.file, '', 'A dot alone remains unavailable');
eq(MOCK.sound_workers, nil, 'Validating, tidying, and saving choices never starts a sound decoder');
return { count = count };
