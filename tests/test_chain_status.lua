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
local function snapshot()
    return { valid = true, id = 1001, zone = 102, job = 1, level = 75, effective_level = 50,
        utc = 1800000000, sync_active = true, dedication = true, food = false, food_known = true };
end
local chains = require('core.chains');
local local_chain, local_status = chains.new(), status.new();
local sample = snapshot(); sample.effective_level = 19;
local_status:observe(sample, 0);
local_chain:award({ source = 'battle', chain = 2 }, sample, 0);
local view = local_status:apply_chain(local_chain:view(0), 0);
equal(view.chain_source, 'local', 'Phoenix local clock uses the observed chain reward');
equal(view.chain_estimated, true, 'The countdown is explicitly an estimate');
equal(view.chain_active, nil, 'The estimate does not establish native activity');
close(view.chain_left, 80, 'The countdown uses the earliest eligible pinned Phoenix window');
close(view.chain_left_min, 80, 'The countdown has no range');
close(view.chain_window, 80, 'The strip uses the same conservative duration');
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
local_status:observe(sample, 5);
view = local_status:apply_chain(local_chain:view(5), 5);
equal(view.chain_left, nil, 'Sampling gap suppresses old local timing');
equal(view.chain_source, 'unknown', 'Sampling gap is unavailable timing, not an expired estimate');
equal(view.chain, 2, 'Sampling gap retains last observed count');
local_chain:award({ source = 'battle', chain = 3 }, sample, 5);
local_status:award({ source = 'battle', chain = 3 }, 5);
equal(local_status:apply_chain(local_chain:view(5), 5).chain_source, 'local', 'Positive reward after a gap starts a new estimate');

-- A missed observation must not revive an older estimate when sampling resumes.
local_chain, local_status = chains.new(), status.new();
sample = snapshot(); local_status:observe(sample, 0);
local event = { source = 'battle', chain = 2, token = 'first' };
local_chain:award(event, sample, 0); local_status:award(event, 0);
view = local_status:apply_chain(local_chain:view(3.1), 3.1);
equal(view.chain_source, 'unknown', 'Stale status suppresses timing before the next sample');
equal(view.chain_left, nil, 'Stale status has no ticking clock');
local_status:observe(sample, 3.1);
view = local_status:apply_chain(local_chain:view(3.1), 3.1);
equal(view.chain_left, nil, 'A new sample does not revive the old chain');
equal(view.chain, 2, 'Suppression preserves the last observed count');
event = { source = 'battle', chain = 3, token = 'second' };
local_chain:award(event, sample, 3.1); local_status:award(event, 3.1);
view = local_status:apply_chain(local_chain:view(3.1), 3.1);
equal(view.chain_source, 'local', 'A new positive chain starts a fresh local estimate');
close(view.chain_left, 120, 'New local window uses pinned Phoenix rules');
local_status:observe(sample, 2);
equal(local_status:apply_chain(local_chain:view(2), 2).chain_source, 'unknown', 'Backwards sampling invalidates later chain receipt time');
for _, key in ipairs({ 'id', 'zone', 'job' }) do
    local_chain, local_status = chains.new(), status.new();
    sample = snapshot(); local_status:observe(sample, 0);
    local_chain:award({ source = 'battle', chain = 2 }, sample, 0);
    sample[key] = sample[key] + 1;
    local_status:observe(sample, 1);
    view = local_status:apply_chain(local_chain:view(1), 1);
    equal(view.chain_source, 'unknown', 'Context change suppresses old timing: ' .. key);
    equal(view.chain_left, nil, 'Context change leaves no old countdown: ' .. key);
end
local_status:observe(nil, 1);
equal(local_status:apply_chain(local_chain:view(1), 1).chain_left, nil, 'Missing client status leaves the timer unknown');
return { count = count };
