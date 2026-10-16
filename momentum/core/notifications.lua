local notifications = {}
local methods = {}
methods.__index = methods

notifications.EVENTS = { 'level', 'merit', 'goal', 'cap', 'food_soon', 'dedication_end',
    'ring_ready', 'no_exp', 'chain_soon' }

local function finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function config(settings, id)
    local alerts = settings.alerts or {}
    return (alerts.events or {})[id] or {}, alerts
end

local function signature(row)
    return tostring(row.visual == true) .. ':' .. tostring(row.sound == true) .. ':' .. tostring(row.file or '')
end

function notifications.new()
    return setmetatable({ last = {}, queue = {}, tokens = {}, token_order = {}, enabled = {} }, methods)
end

function methods:discontinuity()
    self.before, self.sampled, self.dedication_seen = nil, nil, nil
    self.queue, self.notice, self.enabled = {}, nil, {}
end

function methods:reset_session(view)
    -- Keep active effect warnings when a new session starts.
    if self.before then
        self.before.merits_gained = view.merits_gained
        self.before.goal = view.goal
    end
    for index = #self.queue, 1, -1 do
        local id = self.queue[index].id
        if id == 'merit' or id == 'goal' then table.remove(self.queue, index) end
    end
end

function methods:set_paused(paused)
    if self.before then self.before.paused = paused == true end
end

function methods:_emit(id, text, now, settings, quiet, token)
    local row, alerts = config(settings, id)
    if token then
        token = id .. ':' .. tostring(token)
        if self.tokens[token] then return false end
        self.tokens[token] = true
        self.token_order[#self.token_order + 1] = token
        if #self.token_order > 128 then self.tokens[table.remove(self.token_order, 1)] = nil end
    end
    if quiet or (row.visual ~= true and row.sound ~= true) then return false end
    local cooldown = tonumber(row.cooldown) or 30
    if not finite(cooldown) then cooldown = 30 end
    cooldown = math.max(0, math.min(3600, cooldown))
    if self.last[id] and now - self.last[id] < cooldown then return false end
    self.last[id] = now
    self.queue[#self.queue + 1] = { id = id, text = text, at = now,
        visual = row.visual == true, sound = row.sound == true, file = row.file or '', volume = row.volume or 100 }
    if #self.queue > 16 then table.remove(self.queue, 1) end
    return true
end

function methods:message(id, text, now, settings, quiet, token)
    if not finite(now) or not self.before or not self.sampled or now < self.sampled or now - self.sampled > 2 then return false end
    if id == 'dedication_end' then
        if not self.dedication_seen or now - self.dedication_seen > 2 or self.before.dead then return false end
        self.dedication_seen = nil
    elseif id ~= 'no_exp' then
        return false
    end
    local row, alerts = config(settings, id)
    quiet = quiet or (alerts.quiet_paused ~= false and self.before.paused)
    return self:_emit(id, text, now, settings, quiet, token)
end

local dynamis_events = { dyna_time = true, dyna_extension = true, dyna_wanted = true,
    dyna_pool = true, dyna_clear = true, dyna_subjob = true }
function methods:dynamis(event, now, settings, quiet)
    if type(event) ~= 'table' or not dynamis_events[event.id] or type(event.message) ~= 'string' or not finite(now) then return false end
    return self:_emit(event.id, event.message, now, settings, quiet)
end

function methods:observe(view, snapshot, now, settings, quiet)
    if not finite(now) or not view or not view.valid or not snapshot or not snapshot.valid then
        self:discontinuity()
        return
    end
    settings = settings or {}
    local alerts = settings.alerts or {}
    local current = { id = snapshot.id, job = snapshot.job, zone = snapshot.zone, dead = snapshot.dead == true,
        level = view.level, merits = view.merits, merit_cap = view.merit_cap, merits_gained = view.merits_gained,
        paused = view.paused == true, food = snapshot.food == true, food_seconds = snapshot.food_seconds,
        dedication = snapshot.dedication == true,
        chain = view.chain, chain_source = view.chain_source,
        chain_left = view.chain_source == 'local' and view.chain_left or nil,
        rings = {}, goal = view.goal }
    for _, ring in ipairs((view.rings or {}).entries or view.rings or {}) do
        if ring.key then
            current.rings[ring.key] = { recast = ring.recast, charges = ring.charges, name = ring.name }
        end
    end
    local before = self.before
    if not before or before.id ~= current.id or before.job ~= current.job or before.zone ~= current.zone
        or not self.sampled or now < self.sampled or now - self.sampled > 2 or before.dead or current.dead then
        before = nil
        self.notice, self.queue = nil, {}
        self.dedication_seen = nil
    end
    if current.dedication and not current.dead then self.dedication_seen = now end
    local armed = {}
    for _, id in ipairs(notifications.EVENTS) do
        local row = config(settings, id)
        local key = signature(row)
        armed[id] = before ~= nil and self.enabled[id] == key
        self.enabled[id] = key
    end
    quiet = quiet or (alerts.quiet_paused ~= false and current.paused)
    local function emit(id, text)
        if armed[id] then self:_emit(id, text, now, settings, quiet) end
    end
    if before then
        if finite(before.level) and finite(current.level) and current.level > before.level then
            emit('level', 'Level ' .. current.level .. ' reached.')
        end
        local merit_gained = finite(before.merits_gained) and finite(current.merits_gained)
            and current.merits_gained > before.merits_gained
        if merit_gained or (finite(before.merits) and finite(current.merits) and current.merits > before.merits) then
            emit('merit', 'Merit point gained.')
        end
        local old_goal, goal = before.goal, current.goal
        if goal and old_goal and goal.available and old_goal.available and goal.type == old_goal.type
            and goal.target == old_goal.target and goal.complete and not old_goal.complete then
            emit('goal', goal.label .. ' reached.')
        end
        if finite(current.merit_cap) and current.merit_cap > 0 and before.merit_cap == current.merit_cap
            and finite(before.merits) and finite(current.merits) then
            local threshold = math.max(0, current.merit_cap - (tonumber(alerts.cap_headroom) or 1))
            if before.merits < threshold and current.merits >= threshold then
                emit('cap', current.merits >= current.merit_cap and 'Your merit points are full.' or 'Your merit points are nearly full.')
            end
        end
        local food_threshold = tonumber(alerts.food_soon_seconds) or 60
        if before.food and current.food and finite(before.food_seconds) and finite(current.food_seconds)
            and before.food_seconds > food_threshold and current.food_seconds <= food_threshold and current.food_seconds > 0 then
            emit('food_soon', 'Food effect: ' .. math.ceil(food_threshold) .. ' seconds or less remaining.')
        end
        for key, ring in pairs(current.rings) do
            local old = before.rings[key]
            if old and finite(old.recast) and finite(ring.recast) and old.recast > 0 and ring.recast <= 0
                and finite(ring.charges) and ring.charges > 0 then
                emit('ring_ready', (ring.name or 'EXP ring') .. ' recast finished.')
            end
        end
        local chain_threshold = tonumber(alerts.chain_soon_seconds) or 10
        if current.chain_source == 'local' and before.chain_source == 'local'
            and current.chain == before.chain and finite(before.chain_left) and finite(current.chain_left)
            and before.chain_left > chain_threshold and current.chain_left <= chain_threshold and current.chain_left > 0 then
            emit('chain_soon', 'Estimated EXP chain time is running out.')
        end
    end
    self.before, self.sampled = current, now
end

function methods:take(now, quiet)
    local result = {}
    if quiet then
        self.queue = {}
        if self.notice and not self.notice.preview then self.notice = nil end
        return result
    end
    for _, event in ipairs(self.queue) do
        if now >= event.at and now - event.at <= 2 then
            result[#result + 1] = event
            if event.visual then
                if self.notice and self.notice.at == now then
                    self.notice.text = self.notice.text .. '  ' .. event.text
                else
                    self.notice = { id = event.id, text = event.text, at = now, expires = now + 5 }
                end
            end
        end
    end
    self.queue = {}
    return result
end

function methods:view(now)
    if self.notice and now >= self.notice.expires then self.notice = nil end
    return self.notice
end

function methods:preview(id, text, now)
    self.notice = { id = id, text = text, at = now, expires = now + 5, preview = true }
end

return notifications
