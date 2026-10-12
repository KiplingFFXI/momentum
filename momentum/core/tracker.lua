local rules = require('data.phoenix_rules')
local chains = require('core.chains')
local goals = require('core.goals')
local tracker = {}
local methods = {}
methods.__index = methods

local MATCH_SECONDS = 3
local TOKEN_LIMIT = 2048
local RATE_SECONDS = 1800
local RECENT_LIMIT = 100

local function number(value)
    if type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
end

function tracker.earning_mode(snapshot)
    if type(snapshot) ~= 'table' or snapshot.valid ~= true then return nil end
    local level = number(snapshot.level)
    if not level or rules.tnl[level] == nil or snapshot.exp_needed ~= rules.tnl[level] then return nil end
    if level < rules.level_cap then return 'exp' end
    local capacity = number(snapshot.merit_cap)
    if not capacity or capacity <= 0 or capacity ~= math.floor(capacity) then return nil end
    if snapshot.limit_mode == true then return 'lp' end
    local exp = number(snapshot.exp)
    if exp and exp >= snapshot.exp_needed - 1 then return 'lp' end
    if snapshot.limit_mode == false then return 'exp' end
end

local function copy(value)
    local result = {}
    for key, item in pairs(value or {}) do
        result[key] = item
    end
    return result
end

local function array(value, limit)
    if type(value) ~= 'table' or #value > limit then return false end
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key > #value or key ~= math.floor(key) then return false end
    end
    return true
end

local function recent(values, requested)
    requested = math.floor(math.max(1, math.min(RECENT_LIMIT, number(requested) or 10)))
    local sorted, total = {}, 0
    for index = math.max(1, #values - requested + 1), #values do
        sorted[#sorted + 1] = values[index]
        total = total + values[index]
    end
    table.sort(sorted)
    local count = #sorted
    return { count = count, requested = requested, total = total,
        average = count > 0 and total / count or nil,
        min = sorted[1], max = sorted[count],
        median = count > 0 and (sorted[math.floor((count + 1) / 2)] + sorted[math.floor(count / 2) + 1]) / 2 or nil }
end

function methods:_recent(kind, requested)
    requested = math.floor(math.max(1, math.min(RECENT_LIMIT, number(requested) or 10)))
    local cached = self.recent_cache[kind]
    if not cached[requested] then cached[requested] = recent(self['recent_' .. kind], requested) end
    -- Views may be edited by callers without changing the next frame's statistics.
    return copy(cached[requested])
end

local function exp_delta(before, after)
    local old_exp = number(before.exp)
    local new_exp = number(after.exp)
    local old_level = number(before.level)
    local new_level = number(after.level)
    if not old_exp or not new_exp or not old_level or not new_level then
        return nil
    end
    if old_level ~= math.floor(old_level) or new_level ~= math.floor(new_level) then
        return nil
    end
    local difference = new_exp - old_exp
    if new_level > old_level then
        for level = old_level, new_level - 1 do
            if not rules.tnl[level] then
                return nil
            end
            difference = difference + rules.tnl[level]
        end
    elseif new_level < old_level then
        for level = new_level, old_level - 1 do
            if not rules.tnl[level] then
                return nil
            end
            difference = difference - rules.tnl[level]
        end
    end
    return difference
end

function tracker.new()
    local self = setmetatable({ chain_state = chains.new(), tokens = {}, token_order = {}, paused = false }, methods)
    self:reset(0)
    return self
end

function methods:_now(now)
    now = number(now) or self.last_time or 0
    now = math.max(self.last_time or now, now)
    self.last_time = now
    return now
end

function methods:_elapsed(now)
    if not self.started then
        return 0
    end
    local until_time = self.paused and self.paused_at or now
    return math.max(0, until_time - self.started - self.pause_total)
end

function methods:_start(now)
    if not self.started then
        self.started = now
        self.pause_total = 0
    end
end

function methods:_bucket(now, field, amount)
    if not self.started then
        return
    end
    local second = math.floor(self:_elapsed(now))
    local slot = second % (RATE_SECONDS + 1) + 1
    local row = self.buckets[slot]
    if not row or row.second ~= second then
        row = { second = second }
        self.buckets[slot] = row
    end
    row[field] = (row[field] or 0) + amount
    self.rate_cache = nil
end

function methods:_reconcile(now)
    if #self.pending_gains == 0 and #self.pending_awards == 0 then return end
    for _, gain in ipairs(self.pending_gains) do
        if gain.amount > 0 then
            for _, award in ipairs(self.pending_awards) do
                if award.kind == gain.kind and award.amount > 0 and math.abs(award.time - gain.time) <= MATCH_SECONDS then
                    local matched = math.min(gain.amount, award.amount)
                    gain.amount = gain.amount - matched
                    award.amount = award.amount - matched
                end
            end
        end
    end

    local gains = {}
    for _, gain in ipairs(self.pending_gains) do
        if gain.amount > 0 then
            if now - gain.time > MATCH_SECONDS then
                local recovered = 0
                if gain.kind == 'exp' and gain.recovery and self.death_balance > 0 then
                    recovered = math.min(self.death_balance, gain.amount)
                    self.death_balance = self.death_balance - recovered
                    self.recovered = self.recovered + recovered
                end
                self.adjustment = self.adjustment + gain.amount - recovered
            else
                gains[#gains + 1] = gain
            end
        end
    end
    self.pending_gains = gains

    local awards = {}
    for _, award in ipairs(self.pending_awards) do
        if award.amount > 0 and now - award.time <= MATCH_SECONDS then
            awards[#awards + 1] = award
        end
    end
    self.pending_awards = awards
end

function methods:reset(now, keep_chain)
    now = self:_now(now)
    self.started = nil
    self.pause_total = 0
    self.paused_at = self.paused and now or nil
    self.session_exp = 0
    self.session_lp = 0
    self.net_exp = 0
    self.net_lp = 0
    self.lost = 0
    self.recovered = 0
    self.adjustment = 0
    self.merits_gained = 0
    self.count_exp = 0
    self.count_lp = 0
    self.recent_exp = {}
    self.recent_lp = {}
    self.recent_cache = { exp = {}, lp = {} }
    self.last_amount = nil
    self.last_kind = nil
    self.death_balance = 0
    self.death_at = nil
    self.revived_at = nil
    self.pending_gains = {}
    self.pending_awards = {}
    self.buckets = {}
    self.rate_cache = nil
    if keep_chain then
        self.chain_state.best = 0
    else
        self.chain_state:reset()
    end
    self.baseline = self.snapshot and self.snapshot.valid and copy(self.snapshot) or nil
end

function methods:discontinuity(now)
    now = self:_now(now)
    self:_reconcile(now + MATCH_SECONDS + 1)
    self.baseline = nil
    self.pending_gains = {}
    self.pending_awards = {}
    self.death_balance = 0
    self.death_at = nil
    self.revived_at = nil
    self.chain_state:clear()
end

function methods:pause(now, paused)
    now = self:_now(now)
    paused = paused == true
    if paused == self.paused then
        return
    end
    self:_reconcile(now + MATCH_SECONDS + 1)
    if paused then
        self.paused_at = now
    else
        if self.started then
            self.pause_total = self.pause_total + now - self.paused_at
        end
        self.paused_at = nil
    end
    self.paused = paused
    self.pending_gains = {}
    self.pending_awards = {}
    self.death_balance = 0
    self.death_at = nil
    self.revived_at = nil
    -- The next client snapshot starts a fresh progress baseline.
    self.baseline = nil
end

function methods:observe(snapshot, now)
    now = self:_now(now)
    if type(snapshot) ~= 'table' or snapshot.valid ~= true then
        self.snapshot = { valid = false }
        self:discontinuity(now)
        return
    end

    snapshot = copy(snapshot)
    local threshold = rules.tnl[snapshot.level]
    if threshold and snapshot.exp_needed and snapshot.exp_needed ~= threshold then
        -- Job and EXP packets can reach memory on different frames.
        return
    end
    if self.identity and (self.identity.id ~= snapshot.id or self.identity.job ~= snapshot.job) then
        self:reset(now)
        self:discontinuity(now)
        self.tokens = {}
        self.token_order = {}
    end
    self.identity = { id = snapshot.id, job = snapshot.job }
    local before = self.baseline
    local previous_zone = self.snapshot and self.snapshot.zone
    self.snapshot = snapshot
    self.baseline = copy(snapshot)
    if not before or before.zone ~= snapshot.zone then
        self:_reconcile(now + MATCH_SECONDS + 1)
        self.pending_gains = {}
        self.pending_awards = {}
        self.death_balance = 0
        self.death_at = nil
        self.revived_at = nil
        -- Pausing restarts EXP comparisons without ending the chain.
        if previous_zone ~= snapshot.zone or snapshot.dead == true then self.chain_state:clear() end
        return
    end
    if self.paused then
        if snapshot.dead == true then self.chain_state:clear() end
        return
    end

    self:_reconcile(now)
    if snapshot.dead == true and before.dead ~= true then
        self.death_at = now
        self.revived_at = nil
        self.death_balance = 0
        self.pending_awards = {}
        self.chain_state:clear()
    elseif before.dead == true and snapshot.dead == false then
        self.revived_at = now
    end

    local exp = exp_delta(before, snapshot)
    if exp and exp ~= 0 then
        if exp > 0 then
            self:_start(now)
            self.pending_gains[#self.pending_gains + 1] = {
                kind = 'exp', amount = exp, time = now,
                recovery = self.revived_at and now - self.revived_at <= MATCH_SECONDS,
            }
        elseif snapshot.dead == true or before.dead == true or (self.death_at and now - self.death_at <= MATCH_SECONDS) then
            self.lost = self.lost - exp
            self.death_balance = self.death_balance - exp
        else
            self.adjustment = self.adjustment + exp
        end
        self.net_exp = self.net_exp + exp
        self:_bucket(now, 'net_exp', exp)
    end

    local old_lp = number(before.lp)
    local new_lp = number(snapshot.lp)
    local old_merits = number(before.merits)
    local new_merits = number(snapshot.merits)
    local earned_merits = old_merits and new_merits and math.max(0, new_merits - old_merits) or nil
    if earned_merits and earned_merits > 0 then
        self:_start(now)
        self.merits_gained = self.merits_gained + earned_merits
    end
    if old_lp and new_lp and old_merits and new_merits then
        local delta = new_lp - old_lp + earned_merits * rules.lp_per_merit
        if delta > 0 then
            self:_start(now)
            self.net_lp = self.net_lp + delta
            self:_bucket(now, 'net_lp', delta)
            self.pending_gains[#self.pending_gains + 1] = { kind = 'lp', amount = delta, time = now }
        elseif delta < 0 then
            -- Spending stored merits changes no LP. Other drops stay adjustments.
            self.adjustment = self.adjustment + delta
            self.net_lp = self.net_lp + delta
            self:_bucket(now, 'net_lp', delta)
        end
    end
    self:_reconcile(now)
end

function methods:award(event, now)
    now = self:_now(now)
    if type(event) ~= 'table' or (event.kind ~= 'exp' and event.kind ~= 'lp') then
        return false
    end
    local amount = number(event.amount)
    if not amount or amount <= 0 or amount ~= math.floor(amount) or not self.snapshot or not self.snapshot.valid then
        return false
    end
    if event.token ~= nil then
        local token = tostring(event.token)
        if self.tokens[token] then
            return false
        end
        self.tokens[token] = true
        self.token_order[#self.token_order + 1] = token
        if #self.token_order > TOKEN_LIMIT then
            self.tokens[table.remove(self.token_order, 1)] = nil
        end
    end

    local previous_best = self.chain_state.best
    self.chain_state:award(event, self.snapshot, now)
    if self.paused then
        self.chain_state.best = previous_best
        return false
    end

    self:_reconcile(now)
    self:_start(now)
    self['session_' .. event.kind] = self['session_' .. event.kind] + amount
    self['count_' .. event.kind] = self['count_' .. event.kind] + 1
    local rewards = self['recent_' .. event.kind]
    rewards[#rewards + 1] = amount
    if #rewards > RECENT_LIMIT then table.remove(rewards, 1) end
    self.recent_cache[event.kind] = {}
    self:_bucket(now, event.kind, amount)
    self.last_amount = amount
    self.last_kind = event.kind
    self.pending_awards[#self.pending_awards + 1] = { kind = event.kind, amount = amount, time = now }
    self:_reconcile(now)
    return true
end

function methods:_rates(now, window, basis)
    local elapsed = self:_elapsed(now)
    if elapsed < 60 then
        return nil
    end
    local net = basis == 'net'
    local exp, lp, earned = 0, 0, 0
    if window == 0 then
        exp, lp, earned = net and self.net_exp or self.session_exp, net and self.net_lp or self.session_lp, self.session_exp
    else
        local first, last = math.ceil(elapsed - window), math.floor(elapsed)
        local cached = self.rate_cache
        if cached and cached.buckets == self.buckets and cached.first == first and cached.last == last and cached.net == net then
            exp, lp, earned = cached.exp, cached.lp, cached.earned
        else
            local exp_field, lp_field = net and 'net_exp' or 'exp', net and 'net_lp' or 'lp'
            for _, bucket in pairs(self.buckets) do
                if bucket.second >= first and bucket.second <= last then
                    exp, lp = exp + (bucket[exp_field] or 0), lp + (bucket[lp_field] or 0)
                    if net then earned = earned + (bucket.exp or 0) end
                end
            end
            if not net then earned = exp end
            self.rate_cache = { buckets = self.buckets, first = first, last = last, net = net, exp = exp, lp = lp, earned = earned }
        end
    end
    local duration = window == 0 and elapsed or math.min(window, elapsed)
    return exp * 3600 / duration, lp * 3600 / duration, earned * 3600 / duration
end

function methods:_rate(now, kind, window, basis)
    local exp, lp = self:_rates(now, window, basis)
    if kind == 'lp' then return lp end
    return exp
end

local totals = { 'session_exp', 'session_lp', 'net_exp', 'net_lp', 'lost', 'recovered', 'adjustment',
    'merits_gained', 'count_exp', 'count_lp' }

function methods:export(now)
    now = self:_now(now)
    self:_reconcile(now)
    local elapsed = self:_elapsed(now)
    local result = { version = 1, identity = copy(self.identity), elapsed = elapsed,
        started = self.started ~= nil, paused = self.paused, best_chain = self.chain_state.best,
        last_amount = self.last_amount, last_kind = self.last_kind,
        recent_exp = copy(self.recent_exp), recent_lp = copy(self.recent_lp), buckets = {} }
    for _, key in ipairs(totals) do result[key] = self[key] end
    -- A saved gap cannot later match a reward or a Raise packet.
    local death_balance = self.death_balance
    for _, gain in ipairs(self.pending_gains) do
        local recovery = gain.kind == 'exp' and gain.recovery and math.min(death_balance, gain.amount) or 0
        death_balance = death_balance - recovery
        result.recovered = result.recovered + recovery
        result.adjustment = result.adjustment + gain.amount - recovery
    end
    for _, bucket in pairs(self.buckets) do
        if bucket.second >= elapsed - RATE_SECONDS and bucket.second <= elapsed then
            result.buckets[#result.buckets + 1] = copy(bucket)
        end
    end
    table.sort(result.buckets, function(a, b) return a.second < b.second end)
    return result
end

function methods:restore(data, now, identity)
    if type(data) ~= 'table' or data.version ~= 1 or type(data.identity) ~= 'table'
        or not number(data.identity.id) or data.identity.id <= 0 or data.identity.id ~= math.floor(data.identity.id)
        or not number(data.identity.job) or data.identity.job < 1 or data.identity.job > 22
        or data.identity.job ~= math.floor(data.identity.job) then return false end
    if identity and (identity.id ~= data.identity.id or identity.job ~= data.identity.job) then return false end
    local elapsed = number(data.elapsed)
    if not elapsed or elapsed < 0 or elapsed > 315360000 or type(data.started) ~= 'boolean'
        or type(data.paused) ~= 'boolean' or (not data.started and elapsed ~= 0) then return false end
    local values = {}
    for _, key in ipairs(totals) do
        local value = number(data[key])
        local signed = key == 'net_exp' or key == 'net_lp' or key == 'adjustment'
        if not value or math.abs(value) > 1000000000000 or value ~= math.floor(value) or (not signed and value < 0) then return false end
        values[key] = value
    end
    local restored_recent = {}
    for _, kind in ipairs({ 'exp', 'lp' }) do
        local rewards = data['recent_' .. kind]
        if not array(rewards, RECENT_LIMIT) then return false end
        restored_recent[kind] = {}
        for _, value in ipairs(rewards) do
            if not number(value) or value <= 0 or value > 2147483647 or value ~= math.floor(value) then return false end
            restored_recent[kind][#restored_recent[kind] + 1] = value
        end
    end
    if not array(data.buckets, RATE_SECONDS + 1) then return false end
    local buckets = {}
    for _, row in ipairs(data.buckets) do
        if type(row) ~= 'table' or not number(row.second) or row.second < 0 or row.second > elapsed
            or row.second ~= math.floor(row.second) then return false end
        local bucket = { second = row.second }
        for _, key in ipairs({ 'exp', 'lp', 'net_exp', 'net_lp' }) do
            if row[key] ~= nil then
                if not number(row[key]) or math.abs(row[key]) > 1000000000000 or row[key] ~= math.floor(row[key]) then return false end
                bucket[key] = row[key]
            end
        end
        if row.second >= elapsed - RATE_SECONDS then buckets[row.second % (RATE_SECONDS + 1) + 1] = bucket end
    end
    now = number(now) or 0
    self.last_time = nil
    self.snapshot = { valid = false }
    self.paused = data.paused
    self:reset(now)
    self.identity = copy(data.identity)
    self.started = data.started and now - elapsed or nil
    self.paused_at = self.paused and now or nil
    for key, value in pairs(values) do self[key] = value end
    self.recent_exp, self.recent_lp, self.buckets = restored_recent.exp, restored_recent.lp, buckets
    self.chain_state.best = math.floor(math.max(0, math.min(1000000, number(data.best_chain) or 0)))
    self.last_amount = number(data.last_amount)
    self.last_kind = (data.last_kind == 'exp' or data.last_kind == 'lp') and data.last_kind or nil
    self.tokens, self.token_order = {}, {}
    return true
end

function methods:view(now, settings)
    now = self:_now(now)
    self:_reconcile(now)
    settings = settings or {}
    local tracking = settings.tracking or {}
    local display = settings.display or {}
    local snapshot = self.snapshot or {}
    local merit_cap = number(snapshot.merit_cap)
    if merit_cap and (merit_cap <= 0 or merit_cap ~= math.floor(merit_cap)) then merit_cap = nil end
    local mode = display.mode
    if mode ~= 'exp' and mode ~= 'lp' then
        mode = snapshot.limit_mode == true and (snapshot.level or 0) >= rules.level_cap and 'lp' or 'exp'
        if mode == 'exp' and (snapshot.level or 0) >= rules.level_cap and snapshot.exp and snapshot.exp_needed and snapshot.exp >= snapshot.exp_needed - 1 then
            mode = 'lp'
        end
    end
    local current = number(snapshot.exp)
    if mode == 'lp' then
        current = number(snapshot.lp)
    end
    local needed = mode == 'lp' and rules.lp_per_merit or number(snapshot.exp_needed)
    if not needed or needed <= 0 then
        needed = nil
    end
    local remaining = current and needed and math.max(0, needed - current) or nil
    local capped = false
    if mode == 'lp' then
        capped = current ~= nil and current >= rules.lp_per_merit - 1 and number(snapshot.merits) ~= nil and merit_cap ~= nil and snapshot.merits >= merit_cap
    elseif current and needed then
        capped = current >= needed - 1 and ((snapshot.level or 0) >= rules.level_cap or snapshot.exp_locked == true)
    end
    if capped then
        remaining = 0
    end
    local merit_headroom = number(snapshot.merits) and merit_cap
        and math.max(0, merit_cap - snapshot.merits) or nil
    local merit_full = merit_headroom == 0

    local window = tonumber(tracking.window) or 900
    if window ~= 0 and window ~= 300 and window ~= 900 and window ~= 1800 then
        window = 900
    end
    local exp_rate, lp_rate, earned_exp = self:_rates(now, window, tracking.rate_basis)
    local rates = { exp = exp_rate, lp = lp_rate }
    local rate = rates[mode]
    local eta = remaining and remaining > 0 and rate and rate > 0 and remaining / rate * 3600 or nil
    if (mode == 'exp' and (snapshot.level or 0) >= rules.level_cap) or (mode == 'lp' and (merit_full or merit_headroom == nil)) then
        eta = nil
    end
    local goal = math.max(0, math.floor(tonumber(tracking.goal_merits) or 5))
    if merit_cap then
        goal = math.min(goal, merit_cap)
    end
    local goal_remaining = snapshot.merits and snapshot.lp and math.max(0, (goal - snapshot.merits) * rules.lp_per_merit - snapshot.lp) or nil
    local result = {
        valid = snapshot.valid == true,
        job = snapshot.job,
        job_name = snapshot.job_name,
        level = snapshot.level,
        effective_level = snapshot.effective_level,
        mode = mode,
        current = current,
        needed = needed,
        remaining = remaining,
        percent = current and needed and math.max(0, math.min(1, current / needed)) or nil,
        rate = rate,
        eta = eta,
        session_exp = self.session_exp,
        session_lp = self.session_lp,
        net_exp = self.net_exp,
        net_lp = self.net_lp,
        lost = self.lost,
        recovered = self.recovered,
        adjustment = self.adjustment,
        merits = snapshot.merits,
        merit_cap = merit_cap,
        merit_headroom = merit_headroom,
        merit_full = merit_full,
        merits_gained = self.merits_gained,
        elapsed = self:_elapsed(now),
        last_amount = self.last_amount,
        last_kind = self.last_kind,
        average = self['count_' .. mode] > 0 and self['session_' .. mode] / self['count_' .. mode] or nil,
        paused = self.paused,
        collecting = self:_elapsed(now) < 60,
        capped = capped,
        dedication = snapshot.dedication,
        dedication_seconds = snapshot.dedication_seconds,
        buffer_current = snapshot.exp,
        buffer_needed = snapshot.exp_needed,
        goal_remaining = goal_remaining,
        goal_eta = merit_headroom and merit_headroom > 0 and goal_remaining and goal_remaining > 0 and lp_rate and lp_rate > 0 and goal_remaining / lp_rate * 3600 or nil,
    }
    for key, value in pairs(self.chain_state:view(now)) do
        result[key] = value
    end
    for _, kind in ipairs({ 'exp', 'lp' }) do
        local lp = kind == 'lp'
        local points = number(lp and snapshot.lp or snapshot.exp)
        -- Lua's and/or expression cannot preserve an unknown LP value.
        if lp then points = number(snapshot.lp) end
        local threshold = lp and rules.lp_per_merit or number(snapshot.exp_needed)
        if threshold and threshold <= 0 then threshold = nil end
        local cap = points ~= nil and threshold ~= nil and points >= threshold - 1
        if lp then cap = cap and number(snapshot.merits) ~= nil and merit_cap ~= nil and snapshot.merits >= merit_cap
        else cap = cap and ((snapshot.level or 0) >= rules.level_cap or snapshot.exp_locked == true) end
        local left = points and threshold and (cap and 0 or math.max(0, threshold - points)) or nil
        local pace = rates[kind]
        local estimate = left and left > 0 and pace and pace > 0 and left / pace * 3600 or nil
        if not lp and (snapshot.level or 0) >= rules.level_cap then estimate = nil end
        if lp and (merit_full or merit_headroom == nil) then estimate = nil end
        result[kind] = { current = points, needed = threshold, remaining = left,
            percent = points and threshold and math.max(0, math.min(1, points / threshold)) or nil,
            capped = cap == true, rate = pace, eta = estimate,
            blocked = lp and merit_full,
            reason = lp and (merit_full and 'Spend some merit points to make room for another.'
                or merit_headroom == nil and 'Waiting for your merit point total and limit.') or nil,
            session = self['session_' .. kind], net = self['net_' .. kind], count = self['count_' .. kind],
            average = self['count_' .. kind] > 0 and self['session_' .. kind] / self['count_' .. kind] or nil,
            recent3 = self:_recent(kind, 3), recent10 = self:_recent(kind, 10),
            recent = self:_recent(kind, tracking.average_count) }
    end
    result.recent3, result.recent10, result.recent = result[mode].recent3, result[mode].recent10, result[mode].recent
    result.goal = goals.evaluate(snapshot, result, tracking, { exp = result.exp.rate, lp = result.lp.rate,
        exp_earned = earned_exp })
    return result
end

return tracker
