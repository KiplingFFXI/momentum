-- Phoenix 465ac4c: Food is 251; ordinary loss uses message 206.
-- The message also covers non-silent removal, so it does not prove natural expiry.
local food = {}
local rules = require('data.phoenix_rules')
local methods = {}
methods.__index = methods

local FOOD = rules.food_effect
local WEARS_OFF = rules.food_end_message
local GRACE = 2
local TOKEN_LIMIT = 256

function food.new()
    return setmetatable({ enabled = false, tokens = {}, token_order = {} }, methods)
end

function methods:discontinuity()
    self.id = nil
    self.zone = nil
    self.last_sample = nil
    self.present = nil
    self.absent_at = nil
    self.armed = false
    self.consumed = false
end

function methods:_enabled(enabled)
    enabled = enabled == true
    if self.enabled ~= enabled then
        self.enabled = enabled
        self:discontinuity()
        return false
    end
    return enabled
end

local function valid_time(now)
    return type(now) == 'number' and now == now and now ~= math.huge and now ~= -math.huge
end

function methods:observe(snapshot, now, enabled)
    self:_enabled(enabled)
    if not self.enabled or not valid_time(now) or type(snapshot) ~= 'table' or snapshot.valid ~= true
        or snapshot.food_known ~= true or type(snapshot.food) ~= 'boolean' or not snapshot.id or snapshot.id == 0 or not snapshot.zone then
        self:discontinuity()
        return false
    end

    if self.id ~= snapshot.id or self.zone ~= snapshot.zone or (self.last_sample and (now < self.last_sample or now - self.last_sample > GRACE)) then
        self:discontinuity()
    end
    self.id = snapshot.id
    self.zone = snapshot.zone
    self.last_sample = now

    if snapshot.food then
        -- A still-visible old icon must not rearm after its loss message.
        if not self.consumed then
            self.armed = true
        end
        self.present = true
        self.absent_at = nil
    else
        if self.present then
            self.absent_at = now
        end
        self.present = false
        self.consumed = false
        if not self.absent_at or now - self.absent_at > GRACE then
            self.armed = false
        end
    end
    return false
end

function methods:message(event, now, enabled)
    local unchanged = self:_enabled(enabled)
    if type(event) ~= 'table' or event.effect ~= FOOD or event.message ~= WEARS_OFF then
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
    if not unchanged or not self.armed or not valid_time(now) or not self.last_sample
        or now < self.last_sample or now - self.last_sample > GRACE
        or event.actor_id ~= self.id or event.target_id ~= self.id
        or (self.absent_at and now - self.absent_at > GRACE) then
        return false
    end

    self.armed = false
    self.consumed = true
    return true
end

return food
