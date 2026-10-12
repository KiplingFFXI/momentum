local player = require('core.player');
local rules = require('data.phoenix_rules');
local checks = 0;
local function equal(actual, expected, label)
    checks = checks + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end

local memory = AshitaCore:GetMemoryManager():GetPlayer();
memory.GetJobLevel = function() return MOCK.actual_level; end;
MOCK.actual_level, MOCK.player.main_level = 75, 20;
MOCK.player.exp_needed, MOCK.player.mode = rules.tnl[75], 'lp';
for _, capacity in ipairs({ 0, -1, 0.5, math.huge, 0 / 0, '30', false }) do
    MOCK.player.merit_cap = capacity;
    local snapshot = player.read();
    equal(snapshot.valid, true, 'Unavailable merits do not hide valid EXP data');
    equal(snapshot.lp, nil, 'LP is unknown until merit data is ready');
    equal(snapshot.merits, nil, 'Stored merits are unknown until merit data is ready');
    equal(snapshot.merit_cap, nil, 'Invalid client capacity is unknown');
end
MOCK.player.merit_cap = nil;
equal(player.read().merit_cap, nil, 'Missing client capacity stays unknown');

MOCK.player.merit_cap, MOCK.player.limit_points, MOCK.player.merits = 0, 0, 0;
dofile(ADDON_DIR .. '/momentum.lua');
MOCK.fire('load');
local app = MOMENTUM_TEST;
local function view() return app.tracker():view(MOCK.now, app.settings()); end
local function merit_packet(lp, merits, capacity)
    local bytes = MOCK.bytes(16);
    MOCK.put(bytes, 4, 2, 2);
    MOCK.put(bytes, 6, 2, 12);
    MOCK.put(bytes, 8, 2, lp);
    MOCK.put(bytes, 10, 2, merits + 0xE000);
    MOCK.put(bytes, 12, 1, capacity);
    MOCK.fire('packet_in', MOCK.packet(0x063, bytes));
    -- Ashita applies the incoming packet to memory after packet_in returns.
    MOCK.player.limit_points, MOCK.player.merits, MOCK.player.merit_cap = lp, merits, capacity;
    MOCK.frame(0.25);
end
equal(view().valid, true, 'Full addon starts with valid EXP and pending merit data');
equal(view().merits, nil, 'Initial zeroed memory does not display zero stored merits');
equal(view().merit_cap, nil, 'Initial zeroed memory does not display zero capacity');
equal(view().merit_headroom, nil, 'Initial memory does not claim full merit storage');
app.settings().alerts.events.merit.visual = true;
app.settings().alerts.events.cap.visual = true;
app.sample(MOCK.now);
merit_packet(9500, 29, 30);
equal(view().mode, 'lp', 'Actual level75 keeps LP mode while synced20');
equal(view().current, 9500, 'First valid packet supplies the LP balance');
equal(view().merits, 29, 'First valid packet supplies stored merit points');
equal(view().merit_cap, 30, 'Positive client capacity is authoritative');
equal(view().merits_gained, 0, 'Preexisting stored merits are not session earnings');
equal(view().session_lp, 0, 'Preexisting LP is not a reported session reward');
equal(view().net_lp, 0, 'Preexisting LP is not retained session progress');
equal(view().elapsed, 0, 'Loading existing merit balances does not start a session');
equal(app.notifications:view(MOCK.now), nil, 'Initial merit data does not trigger earned or near-cap alerts');

local reward = MOCK.bytes(28);
MOCK.put(reward, 4, 4, MOCK.player.server_id);
MOCK.put(reward, 8, 4, MOCK.player.server_id);
MOCK.put(reward, 16, 4, 1000);
MOCK.put(reward, 24, 2, 371);
MOCK.now = 1;
MOCK.fire('packet_in', MOCK.packet(0x02D, reward));
merit_packet(500, 30, 30);
equal(view().merits_gained, 1, 'Later observed conversion earns one session merit');
equal(view().session_lp, 1000, 'Later LP reward is counted once');
equal(view().net_lp, 1000, 'Later LP rollover retains the correct progress');
equal(view().merit_full, true, 'Actual full storage remains detectable');
equal(view().lp.eta, nil, 'Full store has no next-merit ETA');

merit_packet(0, 0, 0);
equal(view().merits, nil, 'A data gap returns to unknown stored merits');
equal(view().merits_gained, 1, 'A data gap preserves observed session merits');
equal(view().net_lp, 1000, 'A data gap does not record a fictitious LP loss');
merit_packet(500, 30, 30);
equal(view().merits_gained, 1, 'Restored balances do not duplicate session merits');
equal(view().net_lp, 1000, 'Restored balances do not duplicate retained LP');
equal(view().session_lp, 1000, 'Restored balances do not duplicate rewards');

MOCK.actual_level, MOCK.player.main_level, MOCK.player.mode = 30, 30, 'exp';
MOCK.player.exp_needed, MOCK.player.limit_breaker = rules.tnl[30], false;
for _, capacity in ipairs({ 10, 30, 45 }) do
    MOCK.player.merit_cap, MOCK.player.merits, MOCK.player.limit_points = capacity, 4, 1250;
    local snapshot = player.read();
    equal(snapshot.valid, true, 'Lower job remains valid');
    equal(snapshot.merit_cap, capacity, 'Positive capacity comes from the client');
    equal(snapshot.merits, 4, 'Stored merits remain visible on lower jobs');
    equal(snapshot.lp, 1250, 'Stored LP remains visible without current merit-mode eligibility');
end
return { count = checks };
