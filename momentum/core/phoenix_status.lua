local status = {}
local rules = require('data.phoenix_rules')
local methods = {}
methods.__index = methods
local FRESH = 12
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
    return setmetatable({ sequences = {}, chain_sequences = {}, chain_tokens = {}, chain_token_order = {} }, methods)
end

function methods:discontinuity()
    self.snapshot, self.feed, self.feed_at = nil, nil, nil
    self.last_sample, self.no_exp, self.no_exp_at = nil, nil, nil
    self.food_name, self.pending_food, self.food_at = nil, nil, nil
    self.chain_feed, self.chain_at, self.chain_clock = nil, nil, nil
    self.chain_local_since, self.chain_local_ended = nil, nil
    self.chain_tokens, self.chain_token_order = {}, {}
end

local function same(left, right)
    return left and right and left.id == right.id and left.zone == right.zone and left.job == right.job
        and left.level == right.level and left.effective_level == right.effective_level
end

function methods:observe(snapshot, now)
    if type(snapshot) ~= 'table' or snapshot.valid ~= true or not snapshot.id or snapshot.id == 0 or not number(now) then
        self:discontinuity()
        return
    end
    if self.snapshot and (self.snapshot.id ~= snapshot.id or self.snapshot.zone ~= snapshot.zone or self.snapshot.job ~= snapshot.job
        or now < self.last_sample or now - self.last_sample > 3) then self:discontinuity() end
    if not self.snapshot then self.chain_local_since = now end
    if self.feed and (not same(self.feed, snapshot) or self.feed.sync_active ~= snapshot.sync_active
        or self.feed.dedication ~= snapshot.dedication) then self.feed = nil end
    if self.snapshot and not same(self.snapshot, snapshot) then
        self.chain_feed, self.chain_at, self.chain_clock = nil, nil, nil
    end
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

function methods:message(feed, now)
    local snapshot = self.snapshot
    if type(feed) ~= 'table' or feed.protocol ~= 1 or not number(now) or not same(feed, snapshot)
        or not self.last_sample or now < self.last_sample or now - self.last_sample > 3
        or feed.sync_active ~= snapshot.sync_active or feed.dedication ~= snapshot.dedication
        or not number(feed.sequence) or not number(feed.utc)
        or feed.sequence <= (self.sequences[feed.id] or 0) then return false end
    local utc = snapshot.utc or os.time()
    if number(snapshot.utc) then utc = utc + now - self.last_sample end
    if not number(utc) or feed.utc < utc - FRESH or feed.utc > utc + 5 then return false end
    local age = math.max(0, math.floor(utc - feed.utc))
    self.sequences[feed.id] = feed.sequence
    self.feed, self.feed_at = nil, nil
    if feed.enabled then
        self.feed = {}
        for key, value in pairs(feed) do self.feed[key] = value end
        self.feed_at = now - age
    end
    return true
end

function methods:chain_message(feed, now)
    local snapshot = self.snapshot
    if type(feed) ~= 'table' or feed.protocol ~= 'MOMC1' or not number(now) or not same(feed, snapshot)
        or not self.last_sample or now < self.last_sample or now - self.last_sample > 3
        or not number(feed.sequence) or feed.sequence < 1 or feed.sequence > 9007199254740991 or feed.sequence % 1 ~= 0
        or feed.sequence <= (self.chain_sequences[feed.id] or 0)
        or not number(feed.utc) or feed.utc < 1 or feed.utc > 4294967295 or feed.utc % 1 ~= 0
        or type(feed.enabled) ~= 'boolean' or type(feed.known) ~= 'boolean'
        or not number(feed.count) or feed.count < 0 or feed.count > 65534 or feed.count % 1 ~= 0
        or not number(feed.server_now_ms) or feed.server_now_ms < 0 or feed.server_now_ms > 9007199254740991 or feed.server_now_ms % 1 ~= 0
        or not number(feed.deadline_ms) or feed.deadline_ms < 0 or feed.deadline_ms > 9007199254740991 or feed.deadline_ms % 1 ~= 0 then return false end
    local utc = snapshot.utc or os.time()
    if number(snapshot.utc) then utc = utc + now - self.last_sample end
    if not number(utc) or feed.utc < utc - FRESH or feed.utc > utc + 5 then return false end
    local age = math.max(0, math.floor(utc - feed.utc))
    if not feed.enabled and feed.known then return false end
    if not feed.known then
        if feed.count ~= 0 or feed.server_now_ms ~= 0 or feed.deadline_ms ~= 0 then return false end
    elseif feed.deadline_ms == 0 then
        if feed.count ~= 0 then return false end
    elseif feed.deadline_ms <= feed.server_now_ms or feed.deadline_ms - feed.server_now_ms > 300000 then return false end

    self.chain_sequences[feed.id] = feed.sequence
    self.chain_feed, self.chain_at = nil, nil
    if not feed.enabled or not feed.known then return true end
    self.chain_feed = {}
    for key, value in pairs(feed) do self.chain_feed[key] = value end
    self.chain_at = now - age
    if feed.deadline_ms == 0 then
        self.chain_clock = nil
        return true
    end
    -- UTC removes known whole-second transit age; subsecond transit remains unmeasured.
    local remaining = math.max(0, (feed.deadline_ms - feed.server_now_ms) / 1000 - age)
    local previous = self.chain_clock
    local deadline = now + remaining
    if same(previous, feed) and previous.count == feed.count and previous.deadline_ms == feed.deadline_ms then
        previous.local_deadline = math.min(previous.local_deadline, deadline)
    else
        self.chain_clock = {}
        for key, value in pairs(feed) do self.chain_clock[key] = value end
        self.chain_clock.local_deadline = deadline
        -- The strip starts with the time left in the first report, not an inferred native window.
        self.chain_clock.window = remaining
    end
    return true
end

function methods:apply_chain(view, now)
    local observed = view.chain_source == 'local' and view.chain_estimated == true and number(view.chain) and view.chain > 0
    local remaining = observed and number(view.chain_left) and view.chain_left > 0 and view.chain_left or nil
    view.chain_source, view.chain_active, view.chain_estimated = observed and 'local' or 'unknown', nil, observed and true or nil
    view.chain_left, view.chain_left_min, view.chain_window = remaining, remaining, remaining and view.chain_window or nil
    if not number(now) or not self.last_sample or now < self.last_sample or now - self.last_sample > 3 then
        self.chain_feed, self.chain_at, self.chain_clock = nil, nil, nil
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
    local feed = self.chain_feed
    if not feed or not self.chain_at or now < self.chain_at or now - self.chain_at > FRESH or not same(feed, self.snapshot) then return view end
    view.chain_source, view.chain_estimated = 'server', false
    local clock = self.chain_clock
    if feed.deadline_ms == 0 or not clock or clock.local_deadline <= now then
        if observed then self.chain_local_ended = { started = view.chain_started, count = view.chain } end
        view.chain_active, view.chain, view.chain_bonus = false, nil, nil
        view.chain_left, view.chain_left_min, view.chain_window = nil, nil, nil
        return view
    end
    view.chain_active, view.chain = true, feed.count
    view.chain_bonus = math.floor((rules.chain_multipliers[math.min(feed.count + 1, 6)] - 1) * 100 + 0.5)
    view.chain_left = math.max(0, clock.local_deadline - now)
    view.chain_left_min, view.chain_window = view.chain_left, clock.window
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
    -- A received award can consume the pool before its next server snapshot.
    if self.feed then self.feed.dedication_pool = nil end
    if type(event) ~= 'table' or event.source ~= 'battle' or not number(now) then return end
    -- Keep the local expiry so the next heartbeat cannot extend this same server deadline.
    self.chain_feed, self.chain_at = nil, nil
    if number(event.chain) and event.chain > 0 then self.chain_local_ended = nil end
end

function methods:dedication_end()
    if self.feed then self.feed.dedication_pool, self.feed.dedication_bonus = nil, nil end
end

function methods:item(event, now, name)
    if not self.snapshot or self.snapshot.food or not self.snapshot.food_known or type(event) ~= 'table'
        or event.id ~= self.snapshot.id or not number(now) or type(name) ~= 'string' or #name == 0 or #name > 128
        or name:find('[%c]') then return false end
    self.pending_food, self.food_at = name, now
    return true
end

function methods:view(now)
    local result = { sync_source = 'unknown', source_ref = rules.source_ref }
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
    if self.feed and now >= self.feed_at and now - self.feed_at <= FRESH then
        local age = now - self.feed_at
        result.sync_source, result.sync_age = 'server', age
        result.sync_penalty, result.sync_rate = self.feed.sync_penalty, self.feed.sync_rate
        if self.feed.dedication and self.feed.dedication_seconds > age then
            result.dedication_pool, result.dedication_bonus = self.feed.dedication_pool, self.feed.dedication_bonus
            result.dedication_seconds = self.feed.dedication_seconds - age
        end
    end
    if self.no_exp_at and now >= self.no_exp_at and now - self.no_exp_at < REASON_TIME then
        result.no_exp_reason, result.no_exp_seconds = self.no_exp, REASON_TIME - (now - self.no_exp_at)
    end
    return result
end

return status
