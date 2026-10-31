local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local Events = require('core.events');
local Client = require('core.events_client');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local settings = defaults.make();
settings.display.order = { 'limbus_next_entry', 'enm_next_entry', 'assault_next_tag' };
for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true; end
settings.events.enm_group = 2;
eq(readouts.needs_character('assault_next_tag'), false, 'Observed tag deadline does not depend on EXP state');
local model = Events.new();
local client = Client.new(model, { utc = function() return nil; end });
client.server_utc, client.server_at = 1900000000, 0;
for _, key in ipairs({ 'limbus', 'enm:2', 'assault_tag' }) do
    assert(model:cooldown(key, key, 1900000001, client:utc(0), 'normal game observation', false));
end
local view = { valid = true, events = model:view(0.6, client:utc(0.6), settings) };
local function expect_all(expected, message)
    local cached, fresh = readouts.cached(settings, view), readouts.build(settings, view);
    eq(#cached, 3, message .. ': all configured deadline readouts are shown');
    for i = 1, 3 do
        eq(cached[i].value, expected, message .. ': cached deadline ' .. i);
        eq(cached[i].value, fresh[i].value, message .. ': cache matches a fresh reading ' .. i);
    end
end
expect_all('0:00', 'Positive fractional time has not expired');
view.events = model:view(1, client:utc(1), settings);
expect_all('Wait ended', 'Exact deadline immediately changes state');
view.events = model:view(500, client:utc(500), settings);
expect_all('Wait ended', 'Expired state remains correct on steady frames');
view.valid = false;
expect_all('Wait ended', 'Stored deadlines remain available while EXP state is unavailable');
view.events.cooldowns = {};
expect_all('--', 'Unknown deadlines replace the previous values');
for _, key in ipairs({ 'limbus', 'enm:2', 'assault_tag' }) do
    model:cooldown(key, key, 1900000600, client:utc(0), 'normal game observation', true);
end
view.events = model:view(0, client:utc(0), settings);
expect_all('~10:00', 'Estimated deadlines retain their estimate marker');
settings.events.enm_group = 0;
view.events.cooldown_key = 'enm:2';
eq(readouts.cached(settings, view)[2].value, '~10:00', 'Current ENM group uses its observed deadline');
view.events.cooldown_key = 'limbus';
eq(readouts.cached(settings, view)[2].value, '--', 'Current ENM does not borrow a different event deadline');

-- Retain the formatted line while fractional progress has no visible effect.
local original, builds = readouts.build, 0;
readouts.build = function(...) builds = builds + 1; return original(...); end;
settings.events.enm_group = 2;
view.events = model:view(0.01, client:utc(0.01), settings);
readouts.cached(settings, view);
local before = builds;
for tick = 2, 40 do
    view.events = model:view(tick / 100, client:utc(tick / 100), settings);
    readouts.cached(settings, view);
end
eq(builds, before, 'Unchanged formatted deadlines do not rebuild on each sample');
readouts.build = original;
return { count = count };
