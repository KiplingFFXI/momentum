local packets = require('core.packets');
local original_time = os.time;
os.time = function() return 1800000000; end;
local count = 0;
local function equal(actual, expected, why)
    count = count + 1;
    assert(actual == expected, why .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function close(actual, expected, why)
    count = count + 1;
    assert(type(actual) == 'number' and math.abs(actual - expected) < 0.000001, why .. ': ' .. tostring(actual));
end
local function frame(message, channel, sender)
    local bytes = MOCK.bytes(23 + #message + 1);
    MOCK.put(bytes, 4, 1, channel or 29); MOCK.put(bytes, 6, 2, 102);
    sender = sender or 'Momentum';
    for i = 1, #sender do bytes[7 + i] = sender:byte(i); end
    for i = 1, #message do bytes[22 + i] = message:byte(i); end
    return MOCK.packet(0x017, bytes);
end
local sequence = 1000;
local function chain(known, chain_count, server_now, deadline, enabled)
    sequence = sequence + 1;
    return frame(table.concat({ 'MOMC1', 1001, 102, 1, 50, 50, sequence, os.time(), enabled == false and 0 or 1,
        known and 1 or 0, chain_count or 0, server_now or 0, deadline or 0 }, '|'));
end
local function battle(amount, chain_count)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, 1001); MOCK.put(bytes, 8, 4, 1001);
    MOCK.put(bytes, 16, 4, amount); MOCK.put(bytes, 20, 4, chain_count); MOCK.put(bytes, 24, 2, 8);
    return MOCK.packet(0x02D, bytes);
end
local function item(amount)
    local bytes = MOCK.bytes(40);
    local function put(offset, length, value)
        for i = 0, length - 1 do
            local at = math.floor((offset + i) / 8);
            bytes[at] = bytes[at] + math.floor(value / 2 ^ i) % 2 * 2 ^ ((offset + i) % 8);
        end
    end
    put(40, 32, 1001); put(72, 6, 1); put(82, 4, 5); put(150, 32, 1001); put(182, 4, 1);
    put(186 + 27, 17, amount); put(186 + 44, 10, 105);
    return MOCK.packet(0x028, bytes);
end

MOCK.load_addon();
MOCK.fire('load');
local app = MOMENTUM_TEST;
local started_at = MOCK.now;
equal(app.view(started_at + 0).chain_source, 'unknown', 'No observed chain means no timer at load');
MOCK.fire('packet_in', battle(100, 0));
equal(app.view(started_at + 0).chain_left, nil, 'An ordinary reward cannot identify the initial native window');
local initial_reward = battle(200, 2);
MOCK.fire('packet_in', initial_reward);
local view = app.view(started_at + 0);
equal(view.chain, 2, 'Observed reward count remains available');
equal(view.chain_bonus, 25, 'Observed reward bonus remains available');
equal(view.chain_source, 'local', 'Confirmed chain starts local tracking without server installation');
equal(view.chain_estimated, true, 'Local clock is clearly marked as an estimate');
equal(view.chain_active, nil, 'Local clock does not claim confirmed native activity');
close(view.chain_left, 180, 'Local countdown comes from pinned Phoenix tables');
close(view.chain_left_min, 180, 'Local presentation has one countdown without a range');
local report = chain(true, 2, 100000, 220000);
MOCK.fire('packet_in', report);
equal(report.blocked, true, 'Validated own chain report consumed');
view = app.view(started_at + 0);
equal(view.chain_source, 'server', 'Entry applies authoritative source');
equal(view.chain_active, true, 'Entry applies active flag');
equal(view.chain_estimated, false, 'Entry does not label server time an estimate');
close(view.chain_left, 120, 'Entry displays server time remaining');
MOCK.now = started_at + 1;
app.sample(started_at + 1);
close(app.view(started_at + 1).chain_left, 119, 'Entry counts down locally between reports');
local replay = frame(report.data:sub(24):gsub('%z.*', ''));
MOCK.fire('packet_in', replay);
equal(replay.blocked, false, 'Replay is not accepted as a new server report');
local item_reward = item(750);
MOCK.fire('packet_in', item_reward);
equal(app.view(started_at + 1).chain_source, 'server', 'EXP item leaves exact battle clock active');
local reward = battle(100, 0);
MOCK.fire('packet_in', reward);
equal(app.view(started_at + 1).chain_source, 'local', 'New battle reward invalidates old server feed and retains local estimate');
close(app.view(started_at + 1).chain_left, 179, 'Unqualified chain-zero award does not restart the local clock');
local resumed = chain(true, 2, 100500, 220000);
MOCK.fire('packet_in', resumed);
equal(resumed.blocked, true, 'Fresh unchanged native timer restores nonqualifying reward window');
close(app.view(started_at + 1).chain_left, 119, 'Same deadline never extends local countdown');
MOCK.fire('packet_in', reward);
equal(app.view(started_at + 1).chain_source, 'server', 'Duplicate packet cannot remove newer report');
MOCK.fire('packet_in', chain(true, 0, 101000, 401000));
equal(app.view(started_at + 1).chain, 0, 'Initial native chain-zero window remains visible');
equal(app.view(started_at + 1).chain_active, true, 'Chain-zero window remains active');
close(app.view(started_at + 1).chain_left, 300, 'Initial native window countdown');
MOCK.fire('packet_in', chain(true, 0, 102000, 0));
equal(app.view(started_at + 1).chain_source, 'server', 'Known inactive keeps authoritative source');
equal(app.view(started_at + 1).chain_active, false, 'Known inactive reaches final view');
equal(app.view(started_at + 1).chain, nil, 'Known inactive explicitly clears observed old count');
equal(app.view(started_at + 1).chain_bonus, nil, 'Known inactive explicitly clears old bonus');
MOCK.fire('packet_in', chain(false));
equal(app.view(started_at + 1).chain_source, 'unknown', 'Missing provider report returns unknown');
equal(app.view(started_at + 1).chain_active, nil, 'Missing provider never means no active chain');
MOCK.fire('packet_in', chain(true, 1, 103000, 343000));
local ordinary = frame('MOMC1|not a server report', 0, 'Tester');
MOCK.fire('packet_in', ordinary);
equal(ordinary.blocked, false, 'Ordinary player text is untouched');
MOCK.now = started_at + 2; MOCK.zoning = true; app.sample(started_at + 2);
equal(app.view(started_at + 2).chain_source, 'unknown', 'Unavailable character clears final timer');
equal(app.view(started_at + 2).chain_left, nil, 'Unavailable character clears clock');
MOCK.zoning = false; MOCK.now = started_at + 3; app.sample(started_at + 3);
equal(app.view(started_at + 3).chain_source, 'unknown', 'Returning character needs a fresh report');
MOCK.fire('packet_in', chain(true, 1, 105000, 345000));
for t = 4, 15 do MOCK.now = started_at + t; app.sample(MOCK.now); end
equal(app.view(started_at + 15).chain_source, 'server', 'Report is fresh at twelve seconds');
MOCK.now = started_at + 15.001; app.sample(MOCK.now);
equal(app.view(MOCK.now).chain_source, 'unknown', 'Final view expires old reports');
equal(app.view(MOCK.now).chain_left, nil, 'Final view has no stale timer');
MOCK.fire('packet_in', chain(false, 0, 0, 0, false));
equal(app.view(MOCK.now).chain_source, 'unknown', 'Opt-out clears the authoritative clock');
MOCK.now = started_at + 16; app.sample(MOCK.now);
local local_reward = battle(200, 2);
MOCK.fire('packet_in', local_reward);
equal(app.view(started_at + 16).chain_source, 'local', 'Local tracking works with server reports explicitly disabled');
close(app.view(started_at + 16).chain_left, 180, 'New observed chain starts Phoenix estimate');
MOCK.now = started_at + 17; app.sample(MOCK.now);
MOCK.fire('packet_in', local_reward);
close(app.view(started_at + 17).chain_left, 179, 'Duplicate reward cannot restart local timer');
MOCK.fire('packet_in', item(100));
close(app.view(started_at + 17).chain_left, 179, 'Item reward cannot restart local timer');
MOCK.now = started_at + 18; app.sample(MOCK.now);
MOCK.fire('packet_in', battle(100, 0));
close(app.view(started_at + 18).chain_left, 178, 'Nonqualifying reward preserves local timer');
MOCK.now = started_at + 22; app.sample(MOCK.now);
equal(app.view(started_at + 22).chain_source, 'unknown', 'Sampling gap removes certainty in the old local window');
equal(app.view(started_at + 22).chain_left, nil, 'Sampling gap cannot revive an old local estimate');
MOCK.fire('packet_in', battle(200, 3));
equal(app.view(started_at + 22).chain_source, 'local', 'New positive chain after gap starts local tracking again');
close(app.view(started_at + 22).chain_left, 120, 'Fresh observed chain uses its Phoenix window');
equal(#MOCK.commands, 0, 'Chain tracking never queues gameplay commands');
os.time = original_time;
return { count = count };
