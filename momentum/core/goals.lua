local rules = require('data.phoenix_rules')
local goals = {}

local function number(value)
    if type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then return value end
end

local function integer(value, low, high, fallback)
    return math.floor(math.max(low, math.min(high, number(value) or fallback)))
end

local function total_to(level)
    local total = 0
    for current = 1, level - 1 do
        if not rules.tnl[current] then return nil end
        total = total + rules.tnl[current]
    end
    return total
end

function goals.evaluate(snapshot, session, settings, rates)
    snapshot, session, settings, rates = snapshot or {}, session or {}, settings or {}, rates or {}
    local kind = settings.goal_type or 'stored_merits'
    if kind ~= 'level' and kind ~= 'session_exp' and kind ~= 'session_merits' and kind ~= 'buffer' then kind = 'stored_merits' end
    local result = { type = kind, available = false, complete = false }
    if kind == 'level' then
        local target = integer(settings.goal_level, 1, rules.level_cap, rules.level_cap)
        result.label, result.unit, result.target_level = 'Level ' .. target, 'EXP', target
        result.target = total_to(target)
        local level, exp = number(snapshot.level), number(snapshot.exp)
        if level and level == math.floor(level) and level >= 1 and level <= rules.level_cap and exp then
            local base = total_to(level)
            if base then result.current = base + exp end
        end
        result.rate = rates.exp
    elseif kind == 'session_exp' then
        result.label, result.unit = 'Session EXP', 'EXP'
        result.current = number(session.session_exp)
        result.target = integer(settings.goal_exp, 1, 1000000000, 10000)
        result.rate = rates.exp_earned
    elseif kind == 'buffer' then
        result.label, result.unit = 'EXP buffer', 'EXP'
        result.current = number(snapshot.exp)
        local needed = number(snapshot.exp_needed)
        if needed and needed > 0 then
            result.target = integer(settings.goal_buffer, 0, needed - 1, math.min(10000, needed - 1))
        end
        result.rate = rates.exp
    else
        local earned = kind == 'session_merits'
        result.label, result.unit = earned and 'Session merit points' or 'Stored merit points', 'LP'
        local count = number(snapshot.merits)
        if earned then count = number(session.merits_gained) end
        local lp = number(snapshot.lp)
        local capacity = number(snapshot.merit_cap)
        if capacity and (capacity <= 0 or capacity ~= math.floor(capacity)) then capacity = nil end
        local cap = earned and 999 or capacity or 999
        local wanted = settings.goal_merits
        if earned then wanted = settings.goal_session_merits end
        local target = integer(wanted, 1, math.max(1, cap), earned and 1 or 5)
        result.target_merits = target
        result.target = target * rules.lp_per_merit
        if count and lp then result.current = count * rules.lp_per_merit + lp
        elseif count and count >= target then result.current = count * rules.lp_per_merit end
        result.rate = rates.lp
        if not capacity or number(snapshot.merits) == nil then
            result.blocked = true
            result.reason = 'Waiting for your merit point total and limit.'
        elseif earned and snapshot.merits >= capacity then
            result.blocked = true
            result.reason = 'Spend some merit points to make room for another.'
        end
    end
    result.available = snapshot.valid == true and result.current ~= nil and result.target ~= nil
    if result.available then
        result.remaining = math.max(0, result.target - result.current)
        result.complete = result.remaining == 0
        if result.complete then result.blocked, result.reason = nil, nil end
        result.percent = result.target > 0 and math.max(0, math.min(1, result.current / result.target)) or 1
        if not result.blocked and result.remaining > 0 and result.rate and result.rate > 0 then
            result.eta = result.remaining / result.rate * 3600
        end
    else
        result.reason = 'Waiting for your EXP and LP to load.'
    end
    return result
end

return goals
