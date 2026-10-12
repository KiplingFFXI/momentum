local packets = require('core.packets');
local status = require('core.phoenix_status');
local count = 0;
local function equal(actual, expected, why)
    count = count + 1;
    assert(actual == expected, why .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function close(actual, expected, why)
    count = count + 1;
    assert(type(actual) == 'number' and math.abs(actual - expected) < 0.000001, why .. ': ' .. tostring(actual));
end
local function frame(message, channel, sender, zone)
    local bytes = MOCK.bytes(23 + #message + 1);
    MOCK.put(bytes, 4, 1, channel or 29);
    MOCK.put(bytes, 6, 2, zone or 102);
    sender = sender or 'Momentum';
    for i = 1, #sender do bytes[7 + i] = sender:byte(i); end
    for i = 1, #message do bytes[22 + i] = message:byte(i); end
    return MOCK.packet(0x017, bytes);
end
local function fields()
    return { 1001, 102, 1, 75, 50, 1800000000001, 1800000000, 1, 1, 2, 100000, 220000 };
end
local function payload(values)
    local text = {};
    for _, value in ipairs(values or fields()) do text[#text + 1] = tostring(value); end
    return 'MOMC1|' .. table.concat(text, '|');
end
local function decoded(values) return packets.chain_status(frame(payload(values)), 1001); end
local function snapshot()
    return { valid = true, id = 1001, zone = 102, job = 1, level = 75, effective_level = 50,
        utc = 1800000000, sync_active = true, dedication = true, food = false, food_known = true };
end
local function tracker_view()
    return { chain = 7, chain_bonus = 50, chain_left = 90, chain_left_min = 60, chain_window = 120, chain_estimated = true, best_chain = 9 };
end
local feed = decoded();
equal(feed.protocol, 'MOMC1', 'Chain protocol is distinct');
equal(feed.count, 2, 'Server count decoded');
equal(feed.deadline_ms, 220000, 'Server deadline decoded');
equal(feed.server_now_ms, 100000, 'Server monotonic time decoded');
equal(packets.status(frame(payload()), 1001), nil, 'MOMC1 never decodes as MOM1');
for _, channel in ipairs({ 0, 1, 6, 26, 200 }) do equal(packets.chain_status(frame(payload(), channel), 1001), nil, 'Non-system channel rejected'); end
equal(packets.chain_status(frame(payload(), 29, 'Tester'), 1001), nil, 'Different sender rejected');
equal(packets.chain_status(frame(payload(), 29, 'Momentum', 101), 1001), nil, 'Zone envelope mismatch rejected');
equal(packets.chain_status(frame(payload()), 1002), nil, 'Different recipient rejected');
for _, flag in ipairs({ 'blocked', 'blocked_original', 'injected', 'is_injected' }) do
    local event = frame(payload()); event[flag] = true;
    equal(packets.chain_status(event, 1001), nil, 'Rejected packet flag ' .. flag);
end
for length = 0, 23 do
    local event = frame(payload()); event.data, event.size = event.data:sub(1, length), length;
    equal(packets.chain_status(event, 1001), nil, 'Truncated envelope');
end
for _, bad in ipairs({ payload() .. '|0', payload() .. '|', payload():gsub('MOMC1', 'MOMC2'),
    payload():gsub('|220000$', '||'), payload():gsub('|220000$', '|-1'), payload():gsub('|220000$', '|220000.0'),
    payload():gsub('|220000$', '|2e5'), payload():gsub('|220000$', '|NaN'), payload():gsub('|220000$', '|inf'),
    payload():gsub('|220000$', '|9007199254740992'), (payload():gsub('|220000$', '|00000000000000000')) }) do
    equal(packets.chain_status(frame(bad), 1001), nil, 'Malformed chain message rejected');
end
for _, bad in ipairs({ { 1, 0 }, { 1, 4294967296 }, { 2, 65536 }, { 3, 0 }, { 3, 23 }, { 4, 0 }, { 4, 100 },
    { 5, 0 }, { 5, 76 }, { 6, 0 }, { 6, '9007199254740992' }, { 7, 0 }, { 7, 4294967296 }, { 8, 2 }, { 9, 2 },
    { 10, 65535 }, { 11, '9007199254740992' }, { 12, '9007199254740992' }, { 12, 100000 }, { 12, 99999 }, { 12, 400001 } }) do
    local values = fields(); values[bad[1]] = bad[2];
    equal(decoded(values), nil, 'Out-of-range field ' .. tostring(bad[1]));
end
local values = fields(); values[10], values[12] = 0, 400000;
equal(decoded(values).count, 0, 'Count zero can describe an active initial window');
values[12] = 0;
equal(decoded(values).known, true, 'Explicit inactive report is known');
values[10] = 1;
equal(decoded(values), nil, 'Inactive report cannot contain an active count');
values = fields(); values[8], values[9], values[10], values[11], values[12] = 0, 0, 0, 0, 0;
equal(decoded(values).enabled, false, 'Opt-out report decoded');
values[8] = 1;
equal(decoded(values).known, false, 'Missing provider report decoded');
values[11] = 1;
equal(decoded(values), nil, 'Unknown report has no timer fields');
values = fields(); values[8] = 0;
equal(decoded(values), nil, 'Disabled feed cannot claim a known chain');
values = fields(); values[6] = '9007199254740991';
equal(decoded(values).sequence, 9007199254740991, 'Maximum safe integer remains valid');
values[11], values[12] = '9007199254740990', '9007199254740991';
equal(decoded(values).deadline_ms - decoded(values).server_now_ms, 1, 'Safe monotonic integer boundary');

local state = status.new();
local sample = snapshot();
state:observe(sample, 0);
local view = state:apply_chain(tracker_view(), 0);
equal(view.chain_source, 'unknown', 'No inferred timer is called server timing');
equal(view.chain_active, nil, 'Unknown is distinct from inactive');
equal(view.chain_left, nil, 'Estimated upper timer removed');
equal(view.chain_left_min, nil, 'Estimated lower timer removed');
equal(view.chain_window, nil, 'Estimated strip denominator removed');
equal(view.chain_estimated, nil, 'Only a fresh server timer gets exact marker');
equal(view.chain, 7, 'Unknown feed retains observed reward count');
equal(view.chain_bonus, 50, 'Unknown feed retains observed bonus');
equal(state:chain_message(feed, 0), true, 'Fresh authoritative timer accepted');
view = state:apply_chain(tracker_view(), 0);
equal(view.chain_source, 'server', 'Fresh timer source');
equal(view.chain_active, true, 'Active timer known');
equal(view.chain, 2, 'Server count replaces observed count');
equal(view.chain_bonus, 25, 'Server count maps to Phoenix chain bonus');
equal(view.chain_estimated, false, 'Only server timing is marked non-estimated');
close(view.chain_left, 120, 'Server remaining duration mapped at receipt');
close(view.chain_left_min, view.chain_left, 'Single countdown has no estimate range');
close(view.chain_window, 120, 'Strip starts with first observed remaining duration');
equal(view.best_chain, 9, 'Authoritative clock does not rewrite session best');
equal(state:chain_message(feed, 1), false, 'Replay rejected');
feed.sequence = feed.sequence + 1;
feed.server_now_ms = 100500;
state:observe(sample, 2);
equal(state:chain_message(feed, 2), true, 'New same-window heartbeat accepted');
view = state:apply_chain(tracker_view(), 2);
close(view.chain_left, 118, 'Delayed heartbeat cannot increase existing countdown');
close(view.chain_window, 120, 'Heartbeat keeps first-observed denominator');
state:award({ source = 'item', token = 'item' }, 2);
equal(state:apply_chain(tracker_view(), 2).chain_source, 'server', 'EXP item does not invalidate battle timer');
state:award({ source = 'battle', chain = 0, token = 'battle' }, 2);
equal(state:apply_chain(tracker_view(), 2).chain_source, 'unknown', 'Battle reward waits for a fresh report');
equal(state:chain_message(feed, 2), false, 'Pre-award replay cannot resurrect timer');
feed.sequence, feed.server_now_ms = feed.sequence + 1, 102500;
state:observe(sample, 3);
equal(state:chain_message(feed, 3), true, 'Nonqualifying reward can retain same authoritative deadline');
close(state:apply_chain(tracker_view(), 3).chain_left, 117, 'Recovered same timer still cannot grow');
state:award({ source = 'battle', chain = 0, token = 'battle' }, 3);
equal(state:apply_chain(tracker_view(), 3).chain_source, 'server', 'Duplicate award cannot invalidate newer timer');
feed.sequence, feed.server_now_ms, feed.deadline_ms = feed.sequence + 1, 103000, 403000;
feed.count = 0;
equal(state:chain_message(feed, 3), true, 'A new count-zero initial window is accepted');
view = state:apply_chain(tracker_view(), 3);
equal(view.chain_active, true, 'Initial window is active even without a chain bonus');
equal(view.chain, 0, 'Initial chain count zero retained');
equal(view.chain_bonus, 0, 'Initial window has no chain bonus');
close(view.chain_left, 300, 'Initial 300-second window supported');
feed.sequence, feed.deadline_ms = feed.sequence + 1, 0;
equal(state:chain_message(feed, 3), true, 'Explicit inactive report accepted');
view = state:apply_chain(tracker_view(), 3);
equal(view.chain_source, 'server', 'Known inactive retains server source');
equal(view.chain_active, false, 'Inactive is explicit');
equal(view.chain, nil, 'Inactive clears stale reward count');
equal(view.chain_bonus, nil, 'Inactive clears stale bonus');
equal(view.chain_left, nil, 'Inactive has no ticking clock');
feed.sequence, feed.count, feed.server_now_ms, feed.deadline_ms = feed.sequence + 1, 3, 200000, 201000;
equal(state:chain_message(feed, 3), true, 'Short active window accepted');
state:observe(sample, 4);
view = state:apply_chain(tracker_view(), 4);
equal(view.chain_active, false, 'Known deadline expiry is inactive');
equal(view.chain, nil, 'Deadline expiry clears old count');
feed.sequence, feed.server_now_ms, feed.deadline_ms = feed.sequence + 1, 200500, 201000;
equal(state:chain_message(feed, 4), true, 'Late same-window heartbeat is consumed');
equal(state:apply_chain(tracker_view(), 4).chain_active, false, 'Late same-window report cannot revive expired local clock');

local fresh = status.new(); fresh:observe(snapshot(), 0);
feed = decoded();
equal(fresh:chain_message(feed, 0), true, 'Timeout fixture');
for t = 1, 12 do fresh:observe(snapshot(), t); end
equal(fresh:apply_chain(tracker_view(), 12).chain_source, 'server', 'Twelve-second freshness boundary');
fresh:observe(snapshot(), 12.001);
view = fresh:apply_chain(tracker_view(), 12.001);
equal(view.chain_source, 'unknown', 'Stale heartbeat returns unknown');
equal(view.chain_left, nil, 'Stale heartbeat cannot leave inferred range visible');
equal(view.chain, 7, 'Stale heartbeat preserves only observed count');
feed.sequence = feed.sequence + 1;
equal(fresh:chain_message(feed, 12.001), true, 'Fresh heartbeat can restore state');
for _, key in ipairs({ 'id', 'zone', 'job', 'level', 'effective_level' }) do
    local changed = snapshot(); changed[key] = changed[key] + 1;
    fresh:observe(changed, 12.1);
    equal(fresh:apply_chain(tracker_view(), 12.1).chain_source, 'unknown', 'Context change clears timer: ' .. key);
    feed.sequence = feed.sequence + 1;
    equal(fresh:chain_message(feed, 12.1), false, 'Old context rejected: ' .. key);
    fresh:observe(snapshot(), 12.2);
    equal(fresh:chain_message(feed, 12.2), true, 'Current context returns: ' .. key);
end
fresh:observe(snapshot(), 16);
equal(fresh:apply_chain(tracker_view(), 16).chain_source, 'unknown', 'Observation gap clears timer');
feed.sequence = feed.sequence + 1;
equal(fresh:chain_message(feed, 16), true, 'New report after gap accepted');
fresh:observe(snapshot(), 15);
equal(fresh:apply_chain(tracker_view(), 15).chain_source, 'unknown', 'Backwards monotonic time clears timer');
fresh:discontinuity(); fresh:observe(snapshot(), 20);
equal(fresh:chain_message(feed, 20), false, 'Replay rejected after explicit discontinuity');
feed.sequence, feed.utc = feed.sequence + 1, 1800000000 - 13;
equal(fresh:chain_message(feed, 20), false, 'Old UTC report rejected');
feed.utc = 1800000000 + 6;
equal(fresh:chain_message(feed, 20), false, 'Future UTC report rejected');
feed.utc = 1800000000;
equal(fresh:chain_message(feed, 20), true, 'Current report accepted');
feed.sequence, feed.enabled, feed.known, feed.count, feed.server_now_ms, feed.deadline_ms = feed.sequence + 1, true, false, 0, 0, 0;
equal(fresh:chain_message(feed, 20), true, 'Unavailable provider report consumed');
equal(fresh:apply_chain(tracker_view(), 20).chain_source, 'unknown', 'Unavailable provider never claims inactive');
feed.sequence, feed.enabled = feed.sequence + 1, false;
equal(fresh:chain_message(feed, 20), true, 'Opt-out consumed');
equal(fresh:apply_chain(tracker_view(), 20).chain_active, nil, 'Opt-out means unknown');
local paired = status.new(); paired:observe(snapshot(), 0);
feed = decoded();
local main = { protocol = 1, id = feed.id, zone = feed.zone, job = feed.job, level = feed.level, effective_level = feed.effective_level,
    sequence = feed.sequence, utc = feed.utc, sync_active = true, dedication = true, enabled = true,
    sync_penalty = 37, sync_rate = 15, dedication_pool = 700, dedication_bonus = 50, dedication_seconds = 600 };
equal(paired:message(main, 0), true, 'MOM1 uses paired sequence');
equal(paired:chain_message(feed, 0), true, 'MOMC1 independently accepts the same paired sequence');
equal(paired:message(main, 0), false, 'MOM1 still rejects its own replay');
equal(paired:chain_message(feed, 0), false, 'MOMC1 independently rejects its own replay');
equal(paired:view(0).sync_penalty, 37, 'Chain report leaves penalty report intact');
equal(paired:view(0).dedication_pool, 700, 'Chain report leaves Dedication intact');

local delayed = status.new();
sample = snapshot(); sample.utc = sample.utc + 10;
delayed:observe(sample, 0);
feed = decoded(); feed.deadline_ms = feed.server_now_ms + 5000;
equal(delayed:chain_message(feed, 0), true, 'Delayed first report is accepted within freshness limit');
view = delayed:apply_chain(tracker_view(), 0);
equal(view.chain_source, 'server', 'Delayed but still fresh report has server source');
equal(view.chain_active, false, 'First report cannot revive a deadline that passed during known transit');
equal(view.chain_left, nil, 'Expired delayed first report has no countdown');
feed.sequence, feed.deadline_ms = feed.sequence + 1, feed.server_now_ms + 20000;
equal(delayed:chain_message(feed, 0), true, 'Delayed new deadline accepted');
close(delayed:apply_chain(tracker_view(), 0).chain_left, 10, 'Known report age is removed from new deadline');
close(delayed:apply_chain(tracker_view(), 0).chain_window, 10, 'Strip begins with age-adjusted remaining duration');
sample.utc = sample.utc + 2; delayed:observe(sample, 2);
equal(delayed:apply_chain(tracker_view(), 2).chain_source, 'server', 'Delayed report stays fresh only through original twelve-second age');
delayed:observe(sample, 2.001);
equal(delayed:apply_chain(tracker_view(), 2.001).chain_source, 'unknown', 'Known transit age reduces remaining freshness lifetime');
feed.sequence, feed.deadline_ms, feed.utc = feed.sequence + 1, feed.server_now_ms + 3000, sample.utc - 5;
equal(delayed:chain_message(feed, 2.001), true, 'Subsequent delayed new deadline accepted');
equal(delayed:apply_chain(tracker_view(), 2.001).chain_active, false, 'New deadline that expired in transit cannot revive prior active state');

local sampled = status.new();
sample = snapshot(); sample.utc = sample.utc + 6;
sampled:observe(sample, 0);
feed = decoded(); feed.deadline_ms = feed.server_now_ms + 20000;
equal(sampled:chain_message(feed, 2.4), true, 'Fresh sampled UTC may be projected to receipt');
close(sampled:apply_chain(tracker_view(), 2.4).chain_left, 12, 'Whole-second age includes elapsed time since the UTC snapshot');
close(sampled:apply_chain(tracker_view(), 2.7).chain_left, 11.7, 'Projected countdown continues monotonically');
feed.sequence = feed.sequence + 1; feed.utc = sample.utc - 11;
equal(sampled:chain_message(feed, 2.4), false, 'Elapsed snapshot time also rejects an over-age report');

local recovery = status.new(); recovery:observe(snapshot(), 0);
feed = decoded();
equal(recovery:chain_message(feed, 0), true, 'Pre-gap active fixture');
sample = snapshot(); sample.utc = sample.utc + 10;
recovery:observe(sample, 10);
equal(recovery:apply_chain(tracker_view(), 10).chain_source, 'unknown', 'Gap clears prior deadline cache');
feed.sequence, feed.deadline_ms = feed.sequence + 1, feed.server_now_ms + 5000;
equal(recovery:chain_message(feed, 10), true, 'Delayed report after observation gap accepted');
equal(recovery:apply_chain(tracker_view(), 10).chain_active, false, 'Post-gap recovery does not resurrect an expired reported window');

local heartbeat = status.new(); heartbeat:observe(snapshot(), 0);
feed = decoded();
equal(heartbeat:chain_message(feed, 0), true, 'Heartbeat timing fixture');
sample = snapshot(); sample.utc = sample.utc + 2; heartbeat:observe(sample, 2);
feed.sequence, feed.utc, feed.server_now_ms = feed.sequence + 1, feed.utc + 1, 101000;
equal(heartbeat:chain_message(feed, 2), true, 'Delayed same-deadline heartbeat accepted');
close(heartbeat:apply_chain(tracker_view(), 2).chain_left, 118, 'Heartbeat removes transit age without extending the countdown');
sample.utc = sample.utc + 2; heartbeat:observe(sample, 4);
feed.sequence = feed.sequence + 1;
equal(heartbeat:chain_message(feed, 4), true, 'Later same-deadline report accepted');
close(heartbeat:apply_chain(tracker_view(), 4).chain_left, 116, 'Repeated delayed heartbeat cannot move expiry forward');

local fallback = status.new(); sample = snapshot(); sample.utc = nil; fallback:observe(sample, 0);
local original_time = os.time;
os.time = function() return 1800000010; end;
feed = decoded(); feed.deadline_ms = feed.server_now_ms + 5000;
equal(fallback:chain_message(feed, 0), true, 'Wall-clock fallback validates known report age');
os.time = original_time;
equal(fallback:apply_chain(tracker_view(), 0).chain_active, false, 'Fallback UTC also prevents delayed timer resurrection');

local chains = require('core.chains');
local local_chain, local_status = chains.new(), status.new();
sample = snapshot(); sample.effective_level = 19;
local_status:observe(sample, 0);
local_chain:award({ source = 'battle', chain = 2 }, sample, 0);
view = local_status:apply_chain(local_chain:view(0), 0);
equal(view.chain_source, 'local', 'Phoenix local clock works with no server report');
equal(view.chain_estimated, true, 'Standalone timer is explicitly an estimate');
equal(view.chain_active, nil, 'Standalone estimate does not establish native activity');
close(view.chain_left, 80, 'Standalone countdown uses earliest eligible pinned Phoenix window');
close(view.chain_left_min, 80, 'Standalone timer has no range');
close(view.chain_window, 80, 'Standalone strip uses the same conservative duration');
for t = 1, 80 do local_status:observe(sample, t); end
view = local_status:apply_chain(local_chain:view(80), 80);
equal(view.chain_source, 'local', 'Expired estimate retains its local origin');
equal(view.chain_left, nil, 'Expired conservative timer stops counting');
equal(view.chain_active, nil, 'Expired estimate does not claim native inactivity');
equal(view.chain, 2, 'Expiry keeps observed chain count');
equal(view.chain_bonus, 25, 'Expiry keeps observed chain bonus');
equal(view.best_chain, 2, 'Expiry keeps session best chain');

local_chain, local_status = chains.new(), status.new();
sample = snapshot(); local_status:observe(sample, 0);
local_chain:award({ source = 'battle', chain = 2 }, sample, 0);
feed = decoded();
equal(local_status:chain_message(feed, 0), true, 'Optional server timer may supplement local tracking');
view = local_status:apply_chain(local_chain:view(0), 0);
equal(view.chain_source, 'server', 'Fresh server data takes precedence');
close(view.chain_left, 120, 'Server deadline replaces conservative estimate');
for t = 1, 13 do local_status:observe(sample, t); end
view = local_status:apply_chain(local_chain:view(13), 13);
equal(view.chain_source, 'local', 'Stale optional report falls back to existing local estimate');
close(view.chain_left, 167, 'Fallback keeps original local start instead of restarting');

local_chain, local_status = chains.new(), status.new();
sample = snapshot(); local_status:observe(sample, 0);
local event = { source = 'battle', chain = 2, token = 'first' };
local_chain:award(event, sample, 0); local_status:award(event, 0);
feed = decoded(); feed.count, feed.deadline_ms = 0, 0;
equal(local_status:chain_message(feed, 0), true, 'Optional server can confirm this observed window ended');
equal(local_status:apply_chain(local_chain:view(0), 0).chain_active, false, 'Fresh inactivity remains explicit');
feed.sequence, feed.known, feed.server_now_ms = feed.sequence + 1, false, 0;
equal(local_status:chain_message(feed, 0), true, 'Provider becomes unavailable after confirmed end');
view = local_status:apply_chain(local_chain:view(0), 0);
equal(view.chain_left, nil, 'Known-ended local window cannot resurrect when provider disappears');
equal(view.chain_source, 'unknown', 'Suppressed window does not falsely say local estimate elapsed');
event = { source = 'battle', chain = 2, token = 'second' };
local_chain:award(event, sample, 0); local_status:award(event, 0);
view = local_status:apply_chain(local_chain:view(0), 0);
equal(view.chain_source, 'local', 'Distinct positive reward at same client timestamp restores local tracking');
close(view.chain_left, 180, 'Distinct same-time reward can create a new estimate');
feed.sequence, feed.known = feed.sequence + 1, true;
equal(local_status:chain_message(feed, 0), true, 'Second observed window may also be confirmed ended');
local_status:apply_chain(local_chain:view(0), 0);
feed.sequence, feed.known = feed.sequence + 1, false;
equal(local_status:chain_message(feed, 0), true, 'Second provider absence consumed');
local_status:award(event, 0);
equal(local_status:apply_chain(local_chain:view(0), 0).chain_left, nil, 'Duplicate reward token cannot clear confirmed-end guard');

local_chain, local_status = chains.new(), status.new();
sample = snapshot(); local_status:observe(sample, 0);
local_chain:award({ source = 'battle', chain = 2 }, sample, 0);
local_status:observe(sample, 5);
view = local_status:apply_chain(local_chain:view(5), 5);
equal(view.chain_left, nil, 'Sampling gap suppresses old local timing');
equal(view.chain_source, 'unknown', 'Sampling gap is unavailable timing, not an expired estimate');
equal(view.chain, 2, 'Sampling gap retains last observed count');
local_chain:award({ source = 'battle', chain = 3 }, sample, 5);
local_status:award({ source = 'battle', chain = 3 }, 5);
equal(local_status:apply_chain(local_chain:view(5), 5).chain_source, 'local', 'Positive reward after a gap starts a new estimate');
return { count = count };
