local events = require('core.events');
local rules = require('data.event_rules');
local store = require('core.file_store');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end

local server = 1800000000;
local wall_clock = os.time;
os.time = function() return server + 3600 + math.floor(MOCK.now); end;
MOCK.player.zone, MOCK.player.buffs = 144, { 254 };
local fight;
for index, row in pairs(rules.areas[144].battles) do
    if row.kind == 'bcnm' then fight = index; break; end
end
assert(fight, 'The fixture needs a normal BCNM');
local saved = events.new();
saved:context(MOCK.player.server_id, 144, 0, server, true);
equal(saved:begin(144, fight, 0, server, false), true, 'Create the observed battlefield');
equal(saved:timer(900, 0, server, false), true, 'Record its native remaining time');
saved:award({ kind = 'exp', amount = 77 }, 0, server);
saved:cooldown('limbus', 'Limbus', server + 1800, server, 'Observed entry', false);
local payload = saved:export(server);
local wrong_clock = events.new();
wrong_clock:context(MOCK.player.server_id, 0, 0, os.time(), false);
equal(wrong_clock:restore(payload, os.time()), true, 'The history itself is valid with a different local clock');
equal(wrong_clock.resume, nil, 'A wrong startup clock would discard the saved fight before client confirmation');

local clock_scans = 0;
ashita.memory.find = function(_, _, pattern)
    if pattern == '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3' then
        clock_scans = clock_scans + 1;
        return 0x1000;
    end
    return 0;
end;
ashita.memory.read_uint32 = function(address)
    if address == 0x1000 then return 0x2000; end;
    if address == 0x2000 then return 0x3000; end;
    if address == 0x300C then return server + math.floor(MOCK.now); end;
    return 0;
end;

for _, preload in ipairs({ false, true }) do
    MOCK.now, MOCK.events, MOCK.login_status = 0, {}, preload and 0 or 2;
    MOMENTUM_TEST, MOMENTUM_BOOTSTRAP_TEST = nil, nil;
    package.loaded['core.player'] = nil;
    clock_scans = 0;
    equal(store.write(MOCK_INSTALL_PATH .. '/config/addons/momentum/events-1001.json', payload), true, 'Save the event fixture');
    dofile(ADDON_DIR .. '/momentum.lua');
    MOCK.fire('load');
    if preload then
        local zone = MOCK.bytes(60);
        MOCK.put(zone, 4, 4, MOCK.player.server_id); MOCK.put(zone, 48, 2, MOCK.player.zone); MOCK.put(zone, 56, 4, server);
        MOCK.fire('packet_in', MOCK.packet(0x00A, zone));
        equal(MOMENTUM_BOOTSTRAP_TEST.inspect().has_zone_packet, true, 'Launcher startup retains the normal zone packet');
        MOCK.login_status = 2;
    end
    MOCK.fire('d3d_beginscene', true);
    MOCK.now = 3;
    for _ = 1, 40 do
        MOCK.fire('d3d_beginscene', true);
        if MOMENTUM_TEST and MOMENTUM_TEST.state.resources_ready then break; end
        MOCK.now = MOCK.now + 1 / 60;
    end
    local app = assert(MOMENTUM_TEST, 'The runtime starts after the stable character wait');
    equal(app.state.resources_ready, true, 'Staged startup completes');
    equal(app.events.core.current ~= nil, true, 'The confirmed saved fight survives startup with a skewed local clock');
    equal(app.events.core.current.ends_at, server + 900, 'The saved deadline remains unchanged');
    equal(app.events.core.current.exp, 77, 'The restored run retains its observed EXP');
    equal(clock_scans, 1, 'The game clock is searched once before restoring saved timers');
    equal(require('core.player').utc(), server + math.floor(MOCK.now), 'The resolved client clock is used');
    equal(app.events.core.cooldowns.limbus.ready_at, server + 1800, 'The recorded entry cooldown remains unchanged');
    equal(app.view(MOCK.now).events.remaining, 900 - math.floor(MOCK.now), 'The countdown uses game time rather than local clock skew');
    MOCK.fire('unload');
end
os.time = wall_clock;
return { count = count };
