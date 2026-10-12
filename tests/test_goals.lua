local goals = require('core.goals')
local rules = require('data.phoenix_rules')
local checks = 0
local function equal(a, b, label)
    checks = checks + 1
    assert(a == b, label .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a))
end
local s = { valid = true, level = 30, exp = 1000, exp_needed = rules.tnl[30], lp = 9500, merits = 2, merit_cap = 10 }
local session = { session_exp = 3000, merits_gained = 0 }
local rates = { exp = 12000, lp = 10000, exp_earned = 18000 }
local g = goals.evaluate(s, session, { goal_type = 'level', goal_level = 32 }, rates)
equal(g.remaining, rules.tnl[30] - 1000 + rules.tnl[31], 'Target level sums Phoenix thresholds')
equal(g.unit, 'EXP', 'Level goal uses EXP')
equal(g.eta, g.remaining / 12000 * 3600, 'Level goal ETA')
equal(g.target_level, 32, 'Level goal reports clamped level')
g = goals.evaluate(s, session, { goal_type = 'level', goal_level = 100 }, rates)
equal(g.target_level, 75, 'No target beyond Phoenix level cap')
g = goals.evaluate(s, session, { goal_type = 'level', goal_level = 20 }, rates)
equal(g.complete, true, 'Already reached level goal completes')
equal(g.remaining, 0, 'Complete goal has no remaining points')
equal(g.eta, nil, 'Complete goal has no ETA')
g = goals.evaluate(s, session, { goal_type = 'session_exp', goal_exp = 5000 }, rates)
equal(g.remaining, 2000, 'Session reward EXP goal')
equal(g.rate, 18000, 'Reported EXP goal uses reported rate')
equal(g.eta, 400, 'Session EXP ETA')
g = goals.evaluate(s, session, { goal_type = 'session_merits', goal_session_merits = 1 }, rates)
equal(g.remaining, 500, 'First observed merit can finish from preexisting LP')
session.merits_gained, s.lp, s.merits = 1, 100, 3
g = goals.evaluate(s, session, { goal_type = 'session_merits', goal_session_merits = 2 }, rates)
equal(g.remaining, 9900, 'Earned-merit goal counts observed conversions')
s.merits = 0
g = goals.evaluate(s, session, { goal_type = 'session_merits', goal_session_merits = 2 }, rates)
equal(g.remaining, 9900, 'Spending stored merits does not erase earned goal progress')
g = goals.evaluate(s, session, { goal_type = 'stored_merits', goal_merits = 2 }, rates)
equal(g.remaining, 19900, 'Stored merit goal reflects spending')
g = goals.evaluate(s, session, { goal_type = 'buffer', goal_buffer = 100000 }, rates)
equal(g.target, rules.tnl[30] - 1, 'Buffer goal cannot exceed current EXP buffer')
equal(g.remaining, rules.tnl[30] - 1001, 'Buffer remaining uses current EXP')
g = goals.evaluate(s, session, { goal_type = 'buffer', goal_buffer = 500 }, rates)
equal(g.complete, true, 'Buffer threshold already reached')
s.merits, s.lp = 10, 9999
g = goals.evaluate(s, session, { goal_type = 'stored_merits', goal_merits = 50 }, rates)
equal(g.target_merits, 10, 'Stored merit target respects client cap')
equal(g.complete, true, 'Full stored merits complete capped target')
g = goals.evaluate(s, session, { goal_type = 'session_merits', goal_session_merits = 50 }, rates)
equal(g.target_merits, 50, 'Session earnings goal can exceed storage cap')
equal(g.blocked, true, 'Full store blocks further observed merit conversions')
equal(g.eta, nil, 'Blocked conversion has no misleading ETA')
for _, points in ipairs({ 0, 9500 }) do
    s.lp = points
    g = goals.evaluate(s, session, { goal_type = 'session_merits', goal_session_merits = 2 }, rates)
    equal(g.blocked, true, 'Full merit store blocks conversion before LP buffer is full')
    equal(g.eta, nil, 'A partially filled buffer cannot promise another merit at storage cap')
end
g = goals.evaluate(s, session, { goal_type = 'session_merits', goal_session_merits = 1 }, rates)
equal(g.complete, true, 'Already earned merit goal stays complete at storage cap')
equal(g.blocked, nil, 'Completed goal does not ask the player to spend merits')
s.lp = nil
g = goals.evaluate(s, session, { goal_type = 'stored_merits' }, rates)
equal(g.complete, true, 'Known stored merit count can prove a completed goal without LP')
s.merits = 0
g = goals.evaluate(s, session, { goal_type = 'stored_merits' }, rates)
equal(g.available, false, 'Unknown LP leaves an unfinished goal unavailable')
equal(g.remaining, nil, 'Unknown remaining stays unknown')
g = goals.evaluate({ valid = false }, session, { goal_type = 'session_exp' }, rates)
equal(g.available, false, 'Invalid character does not show available goal')
g = goals.evaluate(s, session, { goal_type = 'session_exp' }, {})
equal(g.eta, nil, 'No rate means no ETA')
return checks .. ' assertions'
