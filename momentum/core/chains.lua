local rules = require('data.phoenix_rules')
local chains = {}
local methods = {}
methods.__index = methods

local function bracket(level)
    for _, row in ipairs(rules.chain_windows) do
        if level <= row.max_level then
            return row
        end
    end
    return rules.chain_windows[#rules.chain_windows]
end

function chains.new()
    return setmetatable({ best = 0 }, methods)
end

function methods:clear()
    self.count = nil
    self.started = nil
    self.minimum = nil
    self.maximum = nil
    self.estimated = nil
end

function methods:reset()
    self:clear()
    self.best = 0
end

function methods:award(event, snapshot, now)
    local count = tonumber(event.chain)
    if event.source ~= 'battle' or not count or count < 1 or count ~= math.floor(count) then
        return
    end

    self.count = count
    self.best = math.max(self.best, count)
    self.started = now
    local index = math.min(count + 1, 5)
    local level = tonumber(event.mob_level)
    if level and level >= 1 then
        local row = bracket(level)
        self.minimum = row.windows[index]
        self.maximum = self.minimum
        self.estimated = true
        return
    end

    -- A chain proves Even Match or harder, but the packet does not name the mob.
    local lower = tonumber(snapshot and snapshot.effective_level)
    lower = lower and lower >= 1 and lower or 1
    self.minimum = nil
    self.maximum = nil
    for _, row in ipairs(rules.chain_windows) do
        if row.max_level >= lower then
            local window = row.windows[index]
            self.minimum = math.min(self.minimum or window, window)
            self.maximum = math.max(self.maximum or window, window)
        end
    end
    -- Receipt time may trail the server timer even when the bracket is certain.
    self.estimated = true
end

function methods:view(now)
    local elapsed = self.started and math.max(0, now - self.started) or 0
    -- Use the earliest eligible Phoenix window without claiming the native deadline.
    local remaining = self.minimum and self.minimum - elapsed or nil
    if remaining and remaining <= 0 then remaining = nil end
    return {
        chain = self.count,
        chain_bonus = self.count and math.floor((rules.chain_multipliers[math.min(self.count + 1, 6)] - 1) * 100 + 0.5) or nil,
        chain_source = self.count and 'local' or 'unknown',
        chain_started = self.started,
        chain_left = remaining,
        chain_left_min = remaining,
        chain_window = remaining and self.minimum or nil,
        chain_estimated = self.estimated,
        best_chain = self.best,
    }
end

return chains
