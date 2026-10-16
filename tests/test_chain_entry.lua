local player = require('core.player');
local player_reads = 0;
local read = player.read;
player.read = function(...)
    player_reads = player_reads + 1;
    return read(...);
end;
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
equal(view.chain_source, 'local', 'Observed chain starts client tracking');
equal(view.chain_estimated, true, 'Local clock is clearly marked as an estimate');
equal(view.chain_active, nil, 'Local clock does not claim confirmed native activity');
close(view.chain_left, 180, 'Local countdown comes from pinned Phoenix tables');
close(view.chain_left_min, 180, 'Local presentation has one countdown without a range');
for _, message in ipairs({
    'MOM1|1001|102|1|50|50|1|1800000000|0|0|15|1|700|50|600|1',
    'MOMC1|1001|102|1|50|50|1001|1800000000|1|1|2|100000|220000',
    'Hello from party chat.',
}) do
    local reads, sampled = player_reads, app.state.sampled;
    local chat = frame(message);
    MOCK.fire('packet_in', chat);
    equal(chat.blocked, false, 'Chat text stays visible regardless of its contents');
    equal(player_reads, reads, 'Chat text does not force a player read');
    equal(app.state.sampled, sampled, 'Chat text does not invalidate the normal sample cache');
    equal(app.view(started_at).chain_source, 'local', 'Chat text cannot replace the client chain estimate');
    close(app.view(started_at).chain_left, 180, 'Chat text cannot change the chain deadline');
end
MOCK.now = started_at + 1;
app.sample(started_at + 1);
close(app.view(started_at + 1).chain_left, 179, 'Entry counts down from the observed reward');
local item_reward = item(750);
MOCK.fire('packet_in', item_reward);
equal(app.view(started_at + 1).chain_source, 'local', 'EXP item leaves the battle chain estimate active');
close(app.view(started_at + 1).chain_left, 179, 'EXP item cannot restart the chain timer');
local reward = battle(100, 0);
MOCK.fire('packet_in', reward);
equal(app.view(started_at + 1).chain_source, 'local', 'Unqualified reward retains the client chain estimate');
close(app.view(started_at + 1).chain_left, 179, 'Unqualified chain-zero award does not restart the local clock');
MOCK.fire('packet_in', reward);
close(app.view(started_at + 1).chain_left, 179, 'Duplicate reward cannot change the client deadline');
local ordinary = frame('Hello from a player.', 0, 'Tester');
MOCK.fire('packet_in', ordinary);
equal(ordinary.blocked, false, 'Ordinary player text is untouched');
MOCK.now = started_at + 2; MOCK.zoning = true; app.sample(started_at + 2);
equal(app.view(started_at + 2).chain_source, 'unknown', 'Unavailable character clears final timer');
equal(app.view(started_at + 2).chain_left, nil, 'Unavailable character clears clock');
MOCK.zoning = false; MOCK.now = started_at + 3; app.sample(started_at + 3);
equal(app.view(started_at + 3).chain_source, 'unknown', 'Returning character needs a fresh observed chain');
local local_reward = battle(200, 2);
MOCK.fire('packet_in', local_reward);
equal(app.view(started_at + 3).chain_source, 'local', 'Fresh reward restarts client chain tracking');
close(app.view(started_at + 3).chain_left, 180, 'New observed chain starts Phoenix estimate');
MOCK.now = started_at + 4; app.sample(MOCK.now);
MOCK.fire('packet_in', local_reward);
close(app.view(started_at + 4).chain_left, 179, 'Duplicate reward cannot restart local timer');
MOCK.fire('packet_in', item(100));
close(app.view(started_at + 4).chain_left, 179, 'Item reward cannot restart local timer');
MOCK.now = started_at + 5; app.sample(MOCK.now);
MOCK.fire('packet_in', battle(100, 0));
close(app.view(started_at + 5).chain_left, 178, 'Nonqualifying reward preserves local timer');
MOCK.now = started_at + 9; app.sample(MOCK.now);
equal(app.view(started_at + 9).chain_source, 'unknown', 'Sampling gap removes certainty in the old local window');
equal(app.view(started_at + 9).chain_left, nil, 'Sampling gap cannot revive an old local estimate');
MOCK.fire('packet_in', battle(200, 3));
equal(app.view(started_at + 9).chain_source, 'local', 'New positive chain after gap starts local tracking again');
close(app.view(started_at + 9).chain_left, 120, 'Fresh observed chain uses its Phoenix window');
equal(#MOCK.commands, 0, 'Chain tracking never queues gameplay commands');
return { count = count };
