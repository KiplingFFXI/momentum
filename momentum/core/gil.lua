local gil = {}
local methods = {}
methods.__index = methods

local MAX_GIL = 999999999
local MAX_TOTAL = 1000000000000
local MAX_ELAPSED = 315360000

local function number(value)
    if type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then return value end
end

local function amount(value, maximum)
    return number(value) and value >= 0 and value <= maximum and value == math.floor(value)
end

function gil.new()
    return setmetatable({ gained = 0, spent = 0, elapsed_total = 0, started = false, paused = false }, methods)
end

function methods:_now(now)
    now = math.max(self.last_time or 0, number(now) or self.last_time or 0)
    self.last_time = now
    return now
end

function methods:_elapsed(now)
    return self.elapsed_total + (self.active_since and math.max(0, now - self.active_since) or 0)
end

function methods:_suspend(now)
    self.elapsed_total = self:_elapsed(now)
    self.active_since = nil
end

function methods:observe(balance, now, baseline_only)
    if not amount(balance, MAX_GIL) then return false end
    now = self:_now(now)
    local before = self.current
    self.current = balance
    if self.started and not self.paused and not self.active_since then self.active_since = now end
    if before == nil or baseline_only == true or self.paused or balance == before then return true end
    local delta = balance - before
    if delta > 0 then self.gained = self.gained + delta
    else self.spent = self.spent - delta end
    if not self.started then
        self.started = true
        self.active_since = now
    end
    return true
end

function methods:discontinuity(now)
    now = self:_now(now)
    self:_suspend(now)
    self.current = nil
end

function methods:set_paused(paused, now)
    now = self:_now(now)
    paused = paused == true
    if paused == self.paused then return end
    self.paused = paused
    if paused then self:_suspend(now)
    elseif self.started and self.current ~= nil then self.active_since = now end
end

function methods:reset(now)
    now = self:_now(now)
    self.gained, self.spent, self.elapsed_total = 0, 0, 0
    self.started, self.active_since = false, nil
end

function methods:view(now)
    now = self:_now(now)
    local elapsed = self:_elapsed(now)
    local net = self.gained - self.spent
    return { current = self.current, gained = self.gained, spent = self.spent, net = net,
        rate = elapsed >= 60 and net * 3600 / elapsed or nil, elapsed = elapsed }
end

function methods:export(now)
    now = self:_now(now)
    -- The next connection starts with its own wallet balance.
    return { version = 1, gained = self.gained, spent = self.spent, elapsed = self:_elapsed(now),
        started = self.started, paused = self.paused }
end

function methods:restore(data, now)
    if type(data) ~= 'table' or data.version ~= 1 or not amount(data.gained, MAX_TOTAL)
        or not amount(data.spent, MAX_TOTAL) or not number(data.elapsed) or data.elapsed < 0
        or data.elapsed > MAX_ELAPSED or type(data.started) ~= 'boolean' or type(data.paused) ~= 'boolean'
        or (not data.started and (data.elapsed ~= 0 or data.gained ~= 0 or data.spent ~= 0))
        or (data.started and data.gained == 0 and data.spent == 0) then return false end
    self.gained, self.spent, self.elapsed_total = data.gained, data.spent, data.elapsed
    self.started, self.paused = data.started, data.paused
    self.current, self.active_since = nil, nil
    self.last_time = math.max(0, number(now) or 0)
    return true
end

return gil
