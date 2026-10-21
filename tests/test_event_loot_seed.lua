local events = require('core.events');
local rules = require('data.event_rules');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local zone, index;
for candidate, area in pairs(rules.areas) do
    for battle, info in pairs(area.battles or {}) do
        if info.kind == 'limbus' then zone, index = candidate, battle; break; end
    end
    if zone then break; end
end
local utc, settings = 1800000000, { events = { enabled = true } };
local core = events.new();
core:context(1001, zone, 0, utc, true);
core:begin(zone, index, 0, utc, false);
local drop = { slot = 0, item_id = 1875, count = 2, start_time = 12345, old = false };
core:drop(drop, 0, utc, 'new');
core:drop({ slot = 0, item_id = 1875, count = 2, old = true }, 1, utc + 1, 'seed');
core:drop(drop, 2, utc + 2, 'repeat');
eq(core:view(2, utc + 2, settings).drops[1].count, 2, 'Pool seeding preserves an already observed drop identity');
core:lot({ slot = 0, kind = 'win', winner_id = 1001 }, 3, utc + 3, 'win');
eq(core:view(3, utc + 3, settings).received[1].count, 2, 'Seeded known treasure is received once');
core:lot({ slot = 0, kind = 'win', winner_id = 1001 }, 3, utc + 3, 'win-repeat');
eq(core:view(3, utc + 3, settings).received[1].count, 2, 'Repeated treasure receipt does not increase a cleared slot');
core:drop({ slot = 0, item_id = 1875, count = 2, start_time = 12346, old = false }, 4, utc + 4, 'next');
eq(core:view(4, utc + 4, settings).drops[1].count, 4, 'A later drop in the same slot still counts');
return { count = count };
