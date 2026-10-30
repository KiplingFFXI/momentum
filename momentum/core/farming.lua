local farming = {}
local methods = {}
methods.__index = methods

local ITEM_LIMIT = 1024
local RECENT_LIMIT = 25
local ALERT_LIMIT = 64
local MAX_TOTAL = 1000000000000
local MAX_ELAPSED = 315360000
local MAX_VALUE = 1000000000000000

local function number(value)
    if type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then return value end
end

local function amount(value, maximum)
    return number(value) and value >= 0 and value <= maximum and value == math.floor(value)
end

local function item_id(value)
    return amount(value, 65535) and value > 0
end

local function dense(values, limit)
    if type(values) ~= 'table' or #values > limit then return false end
    for key in pairs(values) do
        if not amount(key, #values) or key == 0 then return false end
    end
    return true
end

local function configured(values, id)
    if type(values) ~= 'table' then return nil end
    local value = values[tostring(id)]
    if value == nil then value = values[id] end
    return value
end

local function goal(config)
    config = config or {}
    local selected = item_id(config.selected_item) and config.selected_item or 0
    local target = amount(config.goal, MAX_TOTAL) and config.goal or 0
    if config.goal_unit == 'stacks' then
        local size = amount(config.stack_size, 999) and config.stack_size > 0 and config.stack_size or 1
        target = math.min(MAX_TOTAL, target * size)
    end
    return selected, target
end

function farming.new()
    local self = setmetatable({ paused = false, available = false }, methods)
    self:reset(0)
    return self
end

function methods:_now(now)
    now = math.max(self.last_time or 0, number(now) or self.last_time or 0)
    self.last_time = now
    return now
end

function methods:_elapsed(now)
    return math.min(MAX_ELAPSED, self.elapsed_total + (self.active_since and math.max(0, now - self.active_since) or 0))
end

function methods:_suspend(now)
    self.elapsed_total = self:_elapsed(now)
    self.active_since = nil
end

function methods:invalidate()
    self.cached_view, self.cached_rows = nil, nil
end

function methods:_changed(items_changed)
    self.revision = (self.revision or 0) + 1
    if items_changed then self.sorted = nil end
    self:invalidate()
end

function methods:mark_partial()
    if not self.partial then self.partial = true; self:_changed(false) end
end

function methods:observe(valid, now)
    now = self:_now(now)
    valid = valid == true or type(valid) == 'table' and valid.valid == true
    if not valid then self:discontinuity(now); return false end
    self.available = true
    if self.started and not self.paused and not self.active_since then self.active_since = now end
    return true
end

function methods:discontinuity(now)
    now = self:_now(now)
    self:_suspend(now)
    self.available = false
    self:invalidate()
end

function methods:set_paused(paused, now)
    now = self:_now(now)
    paused = paused == true
    if self.paused == paused then return end
    self.paused = paused
    if paused then self:_suspend(now)
    elseif self.started and self.available then self.active_since = now end
    self:invalidate()
end

function methods:reset(now)
    now = self:_now(now)
    self.total, self.pool_found, self.mob_gil_total = 0, 0, 0
    self.elapsed_total, self.started, self.active_since = 0, false, nil
    self.items, self.item_count, self.recent, self.alerts = {}, 0, {}, {}
    self.last_elapsed, self.partial = nil, false
    self:_changed(true)
end

function methods:_queue(value)
    if #self.alerts >= ALERT_LIMIT then return end
    self.alerts[#self.alerts + 1] = value
end

function methods:received(id, count, now, config)
    now = self:_now(now)
    if not item_id(id) or not amount(count, 999) or count == 0 or self.paused or not self.available then return false end
    local row = self.items[id]
    if self.total + count > MAX_TOTAL or not row and self.item_count >= ITEM_LIMIT then
        self:mark_partial()
        return false
    end
    if not self.started then self.started, self.active_since = true, now end
    local elapsed = self:_elapsed(now)
    if not row then
        row = { count = 0 }
        self.items[id], self.item_count = row, self.item_count + 1
    end
    local before = row.count
    row.count, row.last_elapsed = before + count, elapsed
    self.total, self.last_elapsed = self.total + count, elapsed
    self.recent[#self.recent + 1] = { item_id = id, count = count, at = elapsed }
    if #self.recent > RECENT_LIMIT then table.remove(self.recent, 1) end
    self:_changed(true)
    config = config or {}
    if configured(config.wanted, id) == true then self:_queue({ id = 'farm_item', item_id = id, count = count }) end
    local selected, target = goal(config)
    if selected == id and target > 0 and before < target and row.count >= target then
        self:_queue({ id = 'farm_goal', item_id = id, count = row.count, goal = target })
    end
    return true
end

function methods:found(id, count, now)
    self:_now(now)
    if not item_id(id) or not amount(count, 999) or count == 0 or self.paused or not self.available then return false end
    if self.pool_found + count > MAX_TOTAL then self:mark_partial(); return false end
    self.pool_found = self.pool_found + count
    self:_changed(false)
    return true
end

function methods:mob_gil(amount_gil, now)
    self:_now(now)
    if not amount(amount_gil, 999999999) or amount_gil == 0 or self.paused or not self.available then return false end
    if self.mob_gil_total + amount_gil > MAX_TOTAL then self:mark_partial(); return false end
    self.mob_gil_total = self.mob_gil_total + amount_gil
    self:_changed(false)
    return true
end

function methods:take_alerts()
    local alerts = self.alerts
    self.alerts = {}
    return alerts
end

local function recent_rows(values)
    local rows = {}
    for _, row in ipairs(values) do rows[#rows + 1] = { item_id = row.item_id, count = row.count, at = row.at } end
    return rows
end

function methods:view(now, config)
    now = self:_now(now)
    config = config or {}
    local elapsed = self:_elapsed(now)
    local second = math.floor(elapsed)
    local selected, target = goal(config)
    local cached = self.cached_view
    if cached and cached.second == second and cached.selected == selected and cached.goal == target
        and cached.prices == config.prices and cached.price_revision == config.price_revision then return cached.value end
    local row = self.items[selected]
    local count = row and row.count or 0
    local rate = elapsed >= 60 and 3600 / elapsed or nil
    local value, priced, unpriced = 0, 0, 0
    local value_partial = false
    for id, item in pairs(self.items) do
        local price = configured(config.prices, id)
        if amount(price, 999999999) then
            priced = priced + item.count
            if value + price * item.count > MAX_VALUE then value_partial = true
            else value = value + price * item.count end
        else unpriced = unpriced + item.count end
    end
    if priced == 0 or value_partial then value = nil end
    local result = { total = self.total, rate = rate and self.total * rate or nil, elapsed = elapsed,
        last_seconds = self.last_elapsed and math.max(0, elapsed - self.last_elapsed) or nil,
        pool_found = self.pool_found, mob_gil = self.mob_gil_total, partial = self.partial,
        estimated_value = value, value_rate = value and rate and value * rate or nil,
        unpriced_count = unpriced, priced_count = priced, value_partial = value_partial,
        recent = recent_rows(self.recent), selected = { id = selected, count = count,
            rate = selected ~= 0 and rate and count * rate or nil,
            last_seconds = row and math.max(0, elapsed - row.last_elapsed) or nil,
            goal = target, goal_remaining = selected ~= 0 and target > 0 and math.max(0, target - count) or nil,
            goal_fraction = selected ~= 0 and target > 0 and math.min(1, count / target) or nil,
            goal_complete = selected ~= 0 and target > 0 and count >= target } }
    self.cached_view = { second = second, selected = selected, goal = target, prices = config.prices,
        price_revision = config.price_revision, value = result }
    return result
end

function methods:rows(now, config)
    local view = self:view(now, config)
    if self.cached_rows and self.cached_rows.view == view then return self.cached_rows.value end
    if not self.sorted then
        self.sorted = {}
        for id in pairs(self.items) do self.sorted[#self.sorted + 1] = id end
        table.sort(self.sorted, function(left, right)
            if self.items[left].count ~= self.items[right].count then return self.items[left].count > self.items[right].count end
            return left < right
        end)
    end
    local rows = {}
    local rate = view.elapsed >= 60 and 3600 / view.elapsed or nil
    for _, id in ipairs(self.sorted) do
        local item = self.items[id]
        local price = configured(config and config.prices, id)
        if not amount(price, 999999999) then price = nil end
        local value = price and price * item.count or nil
        if value and value > MAX_VALUE then value = nil end
        rows[#rows + 1] = { item_id = id, count = item.count, rate = rate and item.count * rate or nil,
            last_seconds = math.max(0, view.elapsed - item.last_elapsed), price = price, estimated_value = value }
    end
    self.cached_rows = { view = view, value = rows }
    return rows
end

function methods:export(now)
    now = self:_now(now)
    local items = {}
    for id, row in pairs(self.items) do items[#items + 1] = { item_id = id, count = row.count, last_elapsed = row.last_elapsed } end
    table.sort(items, function(left, right) return left.item_id < right.item_id end)
    return { version = 1, total = self.total, pool_found = self.pool_found, mob_gil = self.mob_gil_total,
        elapsed = self:_elapsed(now), started = self.started, paused = self.paused, partial = self.partial,
        last_elapsed = self.last_elapsed, items = items, recent = recent_rows(self.recent) }
end

function methods:restore(data, now)
    if type(data) ~= 'table' or data.version ~= 1 or not amount(data.total, MAX_TOTAL)
        or not amount(data.pool_found, MAX_TOTAL) or not amount(data.mob_gil, MAX_TOTAL)
        or not number(data.elapsed) or data.elapsed < 0 or data.elapsed > MAX_ELAPSED
        or type(data.started) ~= 'boolean' or type(data.paused) ~= 'boolean' or type(data.partial) ~= 'boolean'
        or data.started ~= (data.total > 0) or not data.started and data.elapsed ~= 0
        or not dense(data.items, ITEM_LIMIT) or not dense(data.recent, RECENT_LIMIT) then return false end
    if data.started then
        if not number(data.last_elapsed) or data.last_elapsed < 0 or data.last_elapsed > data.elapsed then return false end
    elseif data.last_elapsed ~= nil then return false end
    local items, total, latest = {}, 0, nil
    for _, row in ipairs(data.items) do
        if type(row) ~= 'table' or not item_id(row.item_id) or items[row.item_id]
            or not amount(row.count, MAX_TOTAL) or row.count == 0 or not number(row.last_elapsed)
            or row.last_elapsed < 0 or row.last_elapsed > data.elapsed then return false end
        items[row.item_id] = { count = row.count, last_elapsed = row.last_elapsed }
        total, latest = total + row.count, math.max(latest or 0, row.last_elapsed)
    end
    if total ~= data.total or latest ~= data.last_elapsed then return false end
    local recent, recent_totals, last_at = {}, {}, 0
    for _, row in ipairs(data.recent) do
        if type(row) ~= 'table' or not item_id(row.item_id) or not items[row.item_id]
            or not amount(row.count, 999) or row.count == 0 or not number(row.at)
            or row.at < last_at or row.at > data.elapsed or row.at > items[row.item_id].last_elapsed then return false end
        recent_totals[row.item_id] = (recent_totals[row.item_id] or 0) + row.count
        if recent_totals[row.item_id] > items[row.item_id].count then return false end
        recent[#recent + 1] = { item_id = row.item_id, count = row.count, at = row.at }
        last_at = row.at
    end
    self.last_time = math.max(0, number(now) or 0)
    self.items, self.item_count, self.total = items, #data.items, total
    self.pool_found, self.mob_gil_total, self.partial = data.pool_found, data.mob_gil, data.partial
    self.started, self.paused, self.available = data.started, data.paused, false
    self.elapsed_total, self.active_since, self.last_elapsed = data.elapsed, nil, data.last_elapsed
    self.recent, self.alerts = recent, {}
    self:_changed(true)
    return true
end

return farming
