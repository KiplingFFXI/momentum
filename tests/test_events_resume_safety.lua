local events = require('core.events');
local rules = require('data.event_rules');
local history = require('ui.history');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local zone, index;
for candidate, area in pairs(rules.areas) do
    for battle, info in pairs(area.battles or {}) do
        if info.kind == 'bcnm' then zone, index = candidate, battle; break; end
    end
    if zone then break; end
end
assert(zone, 'Battlefield fixture');
local utc, settings = 1800000000, { events = { enabled = true } };
local source = events.new();
source:context(1001, zone, 0, utc, true);
source:begin(zone, index, 0, utc, false);
source:timer(301, 0, utc, false);
local saved = source:export(utc);
saved.current.previous_remaining = {};
local restored = events.new();
restored:context(1001, zone, 1, utc + 1, false);
eq(restored:restore(saved, utc + 1), true, 'Recent saved fight is available for a matching battlefield');
eq(restored:resume_run(zone, 1, utc + 1, true), true, 'Saved transient alert state does not discard a known countdown');
local safe, alerts = pcall(restored.take_alerts, restored, 1, utc + 1, settings);
eq(safe, true, 'Saved transient alert values cannot crash the next frame');
eq(#alerts, 0, 'Resuming a fight does not replay a time warning');
eq(restored:view(1, utc + 1, settings).remaining, 300, 'Resume keeps the original countdown deadline');
for _, field in ipairs({ 'time_limit', 'floor' }) do
    local bad = history.copy(saved);
    bad.current[field] = {};
    local tracker = events.new();
    tracker:context(1001, zone, 1, utc + 1, false);
    eq(tracker:restore(bad, utc + 1), true, 'Other saved history is available with an invalid optional run field');
    eq(tracker:resume_run(zone, 1, utc + 1, true), false, 'Invalid ' .. field .. ' cannot enter the live HUD');
    eq(tracker:view(1, utc + 1, settings).active, false, 'Invalid run stays inactive');
end
return { count = count };
