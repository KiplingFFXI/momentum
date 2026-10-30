local store = require('core.file_store');
local history = require('ui.history');
local event_rules = require('data.event_rules');
local json = require('json');
local count, writes, encodes = 0, 0, 0;
local function eq(actual, expected, title)
    count = count + 1;
    assert(actual == expected, title .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local write = store.write;
store.write = function(...) writes = writes + 1; return write(...); end;
local encode = json.encode;
json.encode = function(...) encodes = encodes + 1; return encode(...); end;
local utc = 1800000000;
local folder = MOCK_INSTALL_PATH .. '/config/addons/momentum/';
local index;
for key, value in pairs(event_rules.areas[144].battles) do
    if value.kind == 'bcnm' then index = key; break; end
end
local function zone(runtime, id, area, now, server_utc)
    local bytes = MOCK.bytes(60);
    MOCK.put(bytes, 4, 4, id); MOCK.put(bytes, 48, 2, area); MOCK.put(bytes, 56, 4, server_utc);
    runtime:packet(MOCK.packet(0x00A, bytes), now, {});
end
local cases = {
    { name = 'Events', module = 'core.events_runtime', zone = 144, id = 1001,
        start = function(runtime, now)
            eq(runtime.core:begin(144, index, now, runtime.observer:utc(now), false), true, 'Begin the observed battlefield');
            runtime.core:timer(600, now, runtime.observer:utc(now), false);
        end,
        update = function(runtime, now, number)
            runtime.core:currency({ beastmen_seals = number * 100 }, runtime.observer:utc(now));
        end,
        resume = function(runtime, now)
            eq(runtime.core:resume_run(144, now, runtime.observer:utc(now), true), true, 'Client confirmation resumes the saved battlefield');
        end,
        verify = function(runtime)
            eq(runtime.core.currencies.beastmen_seals.value, 300, 'The latest observed currency survives reload');
            eq(runtime.core.current ~= nil, true, 'The confirmed battlefield is restored');
        end,
        edit = function(payload) payload.currencies.beastmen_seals.value = 999; end,
        edited = function(payload) return payload.currencies.beastmen_seals.value; end },
    { name = 'Dynamis', module = 'core.dynamis_runtime', zone = 185, id = 1002,
        start = function(runtime, now)
            eq(runtime.core:hourglass({ zone = 185, start_time = utc, end_time = utc + 3600 }, now, runtime.observer:utc(now)), true, 'Read the observed hourglass');
        end,
        update = function(runtime, now, number)
            runtime.core:drop({ slot = number - 1, item_id = 1456, count = 1, start_time = 100 + number, token = 'drop-' .. number }, now, runtime.observer:utc(now));
        end,
        resume = function(runtime, now)
            eq(runtime.core:hourglass({ zone = 185, start_time = utc, end_time = utc + 3600 }, now, runtime.observer:utc(now)), true, 'Client hourglass revalidates the saved Dynamis run');
        end,
        verify = function(runtime)
            eq(runtime:view(100.123, {}).currency_found, 300, 'The latest observed Dynamis drops survive reload');
            eq(runtime.core.current.start_time, utc, 'The saved Dynamis run keeps its original start');
        end,
        edit = function(payload) payload.current.kills = 999; end,
        edited = function(payload) return payload.current.kills; end },
};
for _, case in ipairs(cases) do
    local module = require(case.module);
    local clock = utc;
    local options = { utc = function() return nil; end, clock = function() return clock; end };
    local runtime = module.new(folder, options);
    zone(runtime, case.id, case.zone, 0.123, utc);
    case.start(runtime, 1.456);
    for number, now in ipairs({ 1.456, 32.789, 63.142 }) do
        case.update(runtime, now, number);
        local previous_encodes = encodes;
        local ok, problem = runtime:save(now, number == 1);
        eq(ok, true, case.name .. ' fractional save ' .. number .. ': ' .. tostring(problem));
        eq(encodes, previous_encodes + 1, case.name .. ' reuses the JSON written to disk without a second encoding');
        eq(runtime.blocked, false, case.name .. ' never mistakes its own serialized numbers for an external edit');
        eq(history.equal(runtime.disk, assert(store.read(runtime.path))), true, case.name .. ' retains the numbers actually written');
    end
    local previous_writes, previous_encodes = writes, encodes;
    eq(runtime:save(64, true), true, case.name .. ' clean save succeeds');
    eq(writes, previous_writes, case.name .. ' clean saves do not rewrite history');
    eq(encodes, previous_encodes, case.name .. ' clean saves do not encode history');
    clock = utc + 100;
    local restored = module.new(folder, options);
    eq(restored:select(case.id, 100.123), true, case.name .. ' selects its saved character');
    eq(restored.blocked, false, case.name .. ' loads its fractional saved data');
    zone(restored, case.id, case.zone, 100.123, utc + 100);
    case.resume(restored, 100.123);
    case.verify(restored);
    case.update(restored, 101.456, 4);
    local ok, problem = restored:save(101.456, true);
    eq(ok, true, case.name .. ' can keep saving after reload: ' .. tostring(problem));
    local external = assert(store.read(restored.path));
    case.edit(external);
    eq(store.write(restored.path, external), true, case.name .. ' external edit is written to disk');
    case.update(restored, 102.789, 5);
    ok, problem = restored:save(102.789, true);
    eq(ok, false, case.name .. ' still blocks an actual external edit');
    eq(restored.blocked, true, case.name .. ' marks the genuine conflict');
    eq(problem:find('changed outside Momentum', 1, true) ~= nil, true, case.name .. ' explains the external file change');
    eq(case.edited(assert(store.read(restored.path))), 999, case.name .. ' leaves the external data unchanged');
end
return { count = count };
