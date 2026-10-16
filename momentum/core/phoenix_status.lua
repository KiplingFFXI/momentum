local status = {}
local rules = require('data.phoenix_rules')
local methods = {}
methods.__index = methods
local REASON_TIME = 15

status.tiers = rules.sync_tiers

local function number(value)
    return type(value) == 'number' and value == value and math.abs(value) ~= math.huge
end

function status.plan(actual, synced, population)
    if not number(actual) or not number(synced) or not number(population) or actual % 1 ~= 0 or synced % 1 ~= 0
        or actual < 1 or actual > 99 or synced < 10 or synced > actual or population < 0 then return nil end
    local gap = actual - synced
    if gap <= 10 then return 0 end
    local rate = 0
    for _, tier in ipairs(status.tiers) do
        if population >= tier.minimum then rate = tier.rate end
    end
    return math.floor(math.min(50, gap * rate / 10))
end

function status.new()
    return setmetatable({ chain_tokens = {}, chain_token_order = {} }, methods)
end

function methods:discontinuity()
    self.snapshot = nil
    self.last_sample, self.no_exp, self.no_exp_at = nil, nil, nil
    self.food_name, self.pending_food, self.food_at = nil, nil, nil
    self.chain_local_since, self.chain_local_ended = nil, nil
    self.chain_tokens, self.chain_token_order = {}, {}
end

function methods:observe(snapshot, now)
    if type(snapshot) ~= 'table' or snapshot.valid ~= true or not snapshot.id or snapshot.id == 0 or not number(now) then
        self:discontinuity()
        return
    end
    if self.snapshot and (self.snapshot.id ~= snapshot.id or self.snapshot.zone ~= snapshot.zone or self.snapshot.job ~= snapshot.job
        or now < self.last_sample or now - self.last_sample > 3) then self:discontinuity() end
    if not self.snapshot then self.chain_local_since = now end
    if snapshot.food_known then
        if not snapshot.food then
            self.food_name = nil
        elseif self.snapshot and self.snapshot.food_known and not self.snapshot.food and self.pending_food
            and now >= self.food_at and now - self.food_at <= 3 then
            self.food_name, self.pending_food = self.pending_food, nil
        end
    else
        self.food_name, self.pending_food = nil, nil
    end
    if self.food_at and now - self.food_at > 3 then self.pending_food = nil end
    self.snapshot = {}
    for key, value in pairs(snapshot) do self.snapshot[key] = value end
    self.last_sample = now
end

function methods:apply_chain(view, now)
    local observed = view.chain_source == 'local' and view.chain_estimated == true and number(view.chain) and view.chain > 0
    local remaining = observed and number(view.chain_left) and view.chain_left > 0 and view.chain_left or nil
    view.chain_source, view.chain_active, view.chain_estimated = observed and 'local' or 'unknown', nil, observed and true or nil
    view.chain_left, view.chain_left_min, view.chain_window = remaining, remaining, remaining and view.chain_window or nil
    if not number(now) or not self.last_sample or now < self.last_sample or now - self.last_sample > 3 then
        if observed then self.chain_local_ended = { started = view.chain_started, count = view.chain } end
        view.chain_source, view.chain_estimated = 'unknown', nil
        view.chain_left, view.chain_left_min, view.chain_window = nil, nil, nil
        return view
    end
    if remaining and (not number(view.chain_started) or view.chain_started > now
        or self.chain_local_since and view.chain_started < self.chain_local_since
        or self.chain_local_ended and view.chain_started == self.chain_local_ended.started and view.chain == self.chain_local_ended.count) then
        view.chain_source, view.chain_estimated = 'unknown', nil
        view.chain_left, view.chain_left_min, view.chain_window = nil, nil, nil
    end
    return view
end

function methods:reason(event, now)
    if not self.snapshot or type(event) ~= 'table' or event.actor_id ~= self.snapshot.id
        or event.target_id ~= self.snapshot.id or not number(now)
        or (event.reason ~= 'distance' and event.reason ~= 'sync_target') then return false end
    self.no_exp, self.no_exp_at = event.reason, now
    return true
end

function methods:award(event, now)
    if type(event) == 'table' and number(now) and event.token ~= nil then
        local token = tostring(event.token)
        if self.chain_tokens[token] then return end
        self.chain_tokens[token] = true
        self.chain_token_order[#self.chain_token_order + 1] = token
        if #self.chain_token_order > 256 then self.chain_tokens[table.remove(self.chain_token_order, 1)] = nil end
    end
    self.no_exp, self.no_exp_at = nil, nil
    if type(event) ~= 'table' or event.source ~= 'battle' or not number(now) then return end
    if number(event.chain) and event.chain > 0 then self.chain_local_ended = nil end
end

function methods:item(event, now, name)
    if not self.snapshot or self.snapshot.food or not self.snapshot.food_known or type(event) ~= 'table'
        or event.id ~= self.snapshot.id or not number(now) or type(name) ~= 'string' or #name == 0 or #name > 128
        or name:find('[%c]') then return false end
    self.pending_food, self.food_at = name, now
    return true
end

function methods:view(now)
    local result = { source_ref = rules.source_ref }
    local snapshot = self.snapshot
    if not snapshot or not number(now) or now < self.last_sample or now - self.last_sample > 3 then return result end
    result.sync_active = snapshot.sync_active
    result.sync_level = snapshot.effective_level
    result.sync_gap = snapshot.level and snapshot.effective_level and math.max(0, snapshot.level - snapshot.effective_level) or nil
    result.dedication = snapshot.dedication
    result.food, result.food_name = snapshot.food, self.food_name
    local elapsed = now - self.last_sample
    result.food_seconds = snapshot.food_seconds and math.max(0, snapshot.food_seconds - elapsed) or nil
    result.dedication_seconds = snapshot.dedication_seconds and math.max(0, snapshot.dedication_seconds - elapsed) or nil
    if self.no_exp_at and now >= self.no_exp_at and now - self.no_exp_at < REASON_TIME then
        result.no_exp_reason, result.no_exp_seconds = self.no_exp, REASON_TIME - (now - self.no_exp_at)
    end
    return result
end

return status
