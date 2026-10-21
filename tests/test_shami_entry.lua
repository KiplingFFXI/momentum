local rules = require('data.event_rules');
local count, sequence = 0, 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
require('ui.hud').draw = function() return false; end;
require('ui.settings_window').draw = function() return false; end;
MOCK.player.zone = rules.npcs.shami.zone;
MOCK.load_addon(); MOCK.frame(0.25);
local app, shami = MOMENTUM_TEST, rules.npcs.shami;
local function packet(kind, id, size, fields)
    local bytes = MOCK.bytes(size);
    sequence = sequence + 1; MOCK.put(bytes, 2, 2, sequence);
    for _, row in ipairs(fields or {}) do MOCK.put(bytes, row[1], row[2], row[3]); end
    MOCK.fire(kind, MOCK.packet(id, bytes));
end
local function balances(bs, ks)
    packet('packet_in', 0x034, 52, { { 4, 4, shami.id }, { 8, 4, ks * 65536 + bs },
        { 42, 2, shami.zone }, { 44, 2, shami.event } });
end
local function stored(key) return app.view(MOCK.now).events.currencies[key].value; end
balances(100, 90);
eq(stored('beastmen_seals'), 100, 'Registered incoming handler reads the Shami menu');
eq(stored('kindred_seals'), 90, 'Registered incoming handler reads both seal types');
app.services.session_pause(true);
local orb = rules.orbs[1131];
packet('packet_out', 0x05B, 20, { { 4, 4, shami.id }, { 8, 4, orb.option },
    { 14, 2, 0 }, { 16, 2, shami.zone }, { 18, 2, shami.event } });
packet('packet_in', 0x02A, 28, { { 4, 4, 1001 }, { 8, 4, 1131 }, { 26, 2, shami.item_obtained } });
eq(stored('beastmen_seals'), 100 - orb.cost, 'Registered outgoing and receipt handlers update seals while paused');
eq(app.services.session_reset(), true, 'EXP session reset succeeds');
eq(stored('beastmen_seals'), 100 - orb.cost, 'Reset preserves the confirmed stored balance');
packet('packet_in', 0x034, 52, { { 4, 4, shami.id }, { 12, 4, 95 * 65536 },
    { 42, 2, shami.zone }, { 44, 2, shami.deposit_event } });
eq(stored('kindred_seals'), 95, 'Deposits update independently of EXP session reset');
eq(stored('beastmen_seals'), 100 - orb.cost, 'A KS deposit leaves BS alone');
packet('packet_in', 0x032, 20, { { 4, 4, shami.id }, { 10, 2, shami.zone }, { 12, 2, shami.empty_event } });
eq(stored('beastmen_seals'), 0, 'Actual parameterless incoming handler reads a known empty balance');
eq(stored('kindred_seals'), 0, 'Empty dialogue clears both known seal balances');
MOCK.fire('unload');
eq(#MOCK.commands, 0, 'Stored seal updates send no gameplay or currency requests');
return { count = count };
