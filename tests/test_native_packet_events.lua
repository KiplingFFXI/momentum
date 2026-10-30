local packets = require('core.packets');
local dynamis = require('core.dynamis_client');
local events = require('core.events_client');
local farming = require('core.farming_client');
local model = require('core.farming');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end

-- Ashita's native event exposes documented packet fields and rejects unknown members.
local function native(fields)
    local value = newproxy(true);
    local known = { id = true, size = true, data = true, data_raw = true, blocked = true, injected = true };
    getmetatable(value).__index = function(_, name)
        if not known[name] then error('Unknown native packet member: ' .. tostring(name)); end
        return fields[name];
    end;
    return value;
end
local function packet(id, size, values)
    local bytes = MOCK.bytes(size);
    for _, field in ipairs(values or {}) do MOCK.put(bytes, field[1], field[2], field[3]); end
    return MOCK.packet(id, bytes);
end
local drop = packet(0x0D2, 28, { { 4, 4, 12 }, { 16, 2, 1455 }, { 20, 1, 0 }, { 24, 4, 100 } });
local award = packet(0x0D3, 24, { { 4, 4, 1001 }, { 20, 1, 0 }, { 21, 1, 1 } });
local event = native(drop);
eq(type(event), 'userdata', 'The fixture matches Ashita native event type');
eq(packets.allowed(event), true, 'Documented native flags pass without compatibility members');
eq(packets.valid(event, 28), true, 'Native packet payload passes validation');
local kind, value = dynamis.parse(event);
eq(kind, 'drop', 'Dynamis reads native treasure metadata');
eq(value.item_id, 1455, 'Dynamis preserves native item identity');
eq(value.count, 12, 'Dynamis preserves native quantity');
kind, value = events.parse(event);
eq(kind, 'drop', 'Event modes receive native treasure through their shared decoder');
eq(value.count, 12, 'Event treasure quantity remains exact');
local observer, tracker = farming.new(), model.new();
observer:observe({ valid = true, id = 1001, zone = 185 }); tracker:observe(true, 0);
observer:packet(event, 1, tracker);
observer:packet(native(award), 2, tracker);
eq(tracker:view(2).total, 12, 'Farming counts a confirmed native personal award');
observer:packet(native(award), 2, tracker);
eq(tracker:view(2).total, 12, 'Native duplicate awards cannot count twice');

for _, flag in ipairs({ 'blocked', 'injected' }) do
    local fields = packet(0x0D2, 28, { { 4, 4, 1 }, { 16, 2, 1455 } });
    fields[flag] = true;
    eq(packets.valid(native(fields), 28), false, 'Native blocked or injected packets stay excluded');
    eq(dynamis.parse(native(fields)), nil, 'Dynamis excludes native blocked or injected packets');
end
for _, flag in ipairs({ 'blocked_original', 'is_injected' }) do
    local fields = packet(0x0D2, 28, { { 4, 4, 1 }, { 16, 2, 1455 } });
    fields[flag] = true;
    eq(packets.valid(fields, 28), false, 'Table transport compatibility flags stay excluded');
    eq(dynamis.parse(fields), nil, 'Dynamis retains table compatibility flag exclusions');
end
for _, size in ipairs({ 27, 28.5, 513, math.huge, 0 / 0 }) do
    local fields = packet(0x0D2, 28); fields.size = size;
    eq(dynamis.parse(native(fields)), nil, 'Dynamis rejects malformed native packet lengths');
end
local truncated = packet(0x0D2, 28); truncated.data = truncated.data:sub(1, 27);
eq(dynamis.parse(native(truncated)), nil, 'Native declared size cannot outread the actual string');
for _, invalid in ipairs({ false, true, 1, 'event', function() end }) do
    eq(packets.allowed(invalid), false, 'Invalid event kinds are rejected');
end
eq(packets.allowed(nil), false, 'A missing event is rejected');

local reward = native(packet(0x02D, 28, { { 4, 4, 1001 }, { 8, 4, 1001 }, { 16, 4, 150 }, { 24, 2, 8 } }));
eq(packets.reward_candidate(reward, 1001), true, 'Native EXP awards retain their own-player filter');
eq(packets.awards(reward, 1001)[1].amount, 150, 'Native EXP award values remain exact');
local wallet = native(packet(0x01E, 12, { { 4, 4, 12345 } }));
eq(packets.inventory(wallet).balance, 12345, 'Native gil inventory updates retain the balance');
local timer = native(packet(0x075, 40, { { 4, 4, 1 }, { 12, 4, 900 }, { 36, 1, 1 } }));
kind, value = events.parse(timer);
eq(kind, 'timer', 'Event modes decode native countdown updates');
eq(value.seconds, 900, 'Native event countdown stays exact');

local rules = require('data.event_rules');
local shami, orb = rules.npcs.shami, rules.orbs[1131];
local core = require('core.events').new();
local source = events.new(core, { memory = {}, clock = function() return 1800000000; end });
local settings = { events = { enabled = true } };
source:context(1001, shami.zone, 0, settings, false);
source:packet(native(packet(0x034, 52, { { 4, 4, shami.id }, { 8, 4, 90 * 65536 + 120 },
    { 42, 2, shami.zone }, { 44, 2, shami.event } })), 0, settings);
eq(core.currencies.beastmen_seals.value, 120, 'Native Shami dialogue reads stored seals');
source:outgoing(native(packet(0x05B, 20, { { 4, 4, shami.id }, { 8, 4, orb.option },
    { 16, 2, shami.zone }, { 18, 2, shami.event } })), 1);
eq(source.shami_pending.at, 1, 'Live outgoing menu uses the current observation time');
source:packet(native(packet(0x02A, 28, { { 4, 4, 1001 }, { 8, 4, 1131 },
    { 26, 2, shami.item_obtained } })), 2, settings);
eq(core.currencies.beastmen_seals.value, 120 - orb.cost, 'Native confirmed orb receipt updates stored seals');
return { count = count };
