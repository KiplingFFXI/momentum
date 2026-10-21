local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local checks = 0;
local function eq(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local settings = defaults.make();
settings.display.order = { 'zone_time', 'zone_name', 'event_time', 'event_objective', 'event_floor', 'event_coins', 'limbus_next_entry', 'limbus_account_entry', 'assault_tags', 'enm_next_entry' };
for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true; end
local view = readouts.sample('Limbus');
view.account_cooldowns = { limbus = { remaining = 3600 } };
local function values()
    local values = {};
    for _, item in ipairs(readouts.cached(settings, view)) do values[item.id] = item.value; end
    return values;
end
local result = values();
eq(result.zone_time, '11:46', 'Zone visit time is independent of session time');
eq(result.zone_name, 'Apollyon', 'Current zone shown');
eq(result.event_time, '~18:44', 'Estimated event deadline is marked');
eq(result.event_objective, 'Open the next vortex', 'Observed objective shown');
eq(result.event_floor, '3 / 5', 'Known floor shown');
eq(result.event_coins, '12', 'Found coins shown');
eq(result.limbus_next_entry, '19h 48m', 'Character Limbus cooldown shown');
eq(result.limbus_account_entry, '1h 00m', 'Account reminder is separate');
eq(result.assault_tags, '2', 'Stored tags use observed balance');
eq(result.enm_next_entry, '--', 'Limbus cooldown is not used as an ENM wait');
view.events.zone_partial = true;
eq(values().zone_time, '~11:46', 'Late-load zone timer clearly marks partial visit');
view.valid = false;
eq(values().event_time, '~18:44', 'Known event state does not depend on EXP snapshot');
view.paused, view.elapsed = true, 0;
eq(values().event_time, '~18:44', 'Session pause does not replace event readings');
view.events.remaining = 9.8;
local before = readouts.cached(settings, view);
view.events.remaining = 9.1;
eq(readouts.cached(settings, view), before, 'Countdown cache stays stable inside a displayed second');
view.events.remaining = 9;
eq(values().event_time, '~0:09', 'Countdown moves at the proper boundary');
view.events.remaining = nil;
eq(values().event_time, '--', 'Missing event deadline stays unknown');
view.events.floor = nil;
eq(values().event_floor, '-- / 5', 'Missing floor does not become floor zero');
view.events.active = false;
eq(values().event_coins, '--', 'An inactive event hides old run totals');
eq(values().zone_name, 'Apollyon', 'Zone readings remain available outside an event');
view.events.cooldowns = { { key = 'enm:2', remaining = 0 }, { key = 'enm:3', remaining = 600 } };
view.events.cooldown_key = 'enm:3';
eq(values().enm_next_entry, '10:00', 'ENM wait uses the current shared key-item group');
view.events.cooldown_key = 'enm:2';
eq(values().enm_next_entry, 'Wait ended', 'Known elapsed wait does not claim full entry readiness');
view.events.cooldown_key = nil;
eq(values().enm_next_entry, '--', 'No group selected does not imply all ENMs are ready');
return { count = checks };
