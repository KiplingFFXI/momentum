local tracker = require('core.tracker')
local rules = require('data.phoenix_rules')
local file_store = require('core.file_store')
local json = require('json')
local sessions = {}
local methods = {}
methods.__index = methods

local LIMIT = 100
local SAVE_SECONDS = 30

local function number(value)
    if type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then return value end
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= 'table' then return left == right end
    for key, value in pairs(left) do if not equal(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local function name(value)
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$')
    if value == '' or #value > 48 or value:find('[^ -~]') or value:find('##', 1, true) then return nil end
    return value
end

local function coherent(snapshot)
    return type(snapshot) == 'table' and snapshot.valid == true
        and number(snapshot.id) and snapshot.id > 0 and snapshot.id <= 4294967295 and snapshot.id == math.floor(snapshot.id)
        and number(snapshot.job) and snapshot.job >= 1 and snapshot.job <= 22 and snapshot.job == math.floor(snapshot.job)
        and rules.tnl[snapshot.level] ~= nil and snapshot.exp_needed == rules.tnl[snapshot.level]
end

sessions.coherent = coherent

local function same(a, b)
    return a and b and a.id == b.id and a.job == b.job
end

local function newer(a, b)
    if a.saved ~= b.saved then return a.saved > b.saved end
    return tonumber(a.id) > tonumber(b.id)
end

local function open_store(path, options, character)
    options = options or {}
    local self = setmetatable({ path = path, read = options.read or file_store.read, write = options.write or file_store.write,
        clock = options.clock or os.time, entries = {}, next_id = 1, retention = 30, resume = true,
        tracker = tracker.new(), dirty = false, last_save = nil, last_attempt = nil }, methods)
    local data, problem = self.read(path)
    if not data then self.blocked, self.error = true, problem or 'The session file could not be read.'; return self end
    self.previous = copy(data)
    if next(data) == nil then return self end
    if data.version ~= 1 or type(data.entries) ~= 'table' or #data.entries > LIMIT then
        self.blocked, self.error = true, 'Momentum cannot read this version of the session file. The file has not been changed.'
        return self
    end
    for key in pairs(data.entries) do
        if type(key) ~= 'number' or key < 1 or key > #data.entries or key ~= math.floor(key) then
            self.blocked, self.error = true, 'The session list could not be read. It was kept unchanged.'
            return self
        end
    end
    local ids = {}
    for _, entry in ipairs(data.entries) do
        local id = type(entry) == 'table' and tonumber(entry.id)
        local payload = type(entry) == 'table' and entry.payload
        local check = tracker.new()
        if not id or id < 1 or id > 1000000000 or id ~= math.floor(id) or ids[id]
            or not name(entry.name) or not number(entry.created) or not number(entry.saved)
            or entry.created < 0 or entry.saved < 0 or not check:restore(payload, 0)
            or payload.identity.id ~= character then
            self.entries = {}
            self.blocked, self.error = true, 'The session file could not be read. It was kept unchanged.'
            return self
        end
        ids[id] = true
        self.next_id = math.max(self.next_id, id + 1)
        self.entries[#self.entries + 1] = { id = tostring(id), name = entry.name,
            job_name = type(entry.job_name) == 'string' and entry.job_name:gsub('[^A-Z]', ''):sub(1, 8) or nil,
            created = entry.created, saved = entry.saved, closed = entry.closed == true, payload = check:export(0) }
    end
    if number(data.next_id) and data.next_id == math.floor(data.next_id) and data.next_id <= 1000000000 then
        self.next_id = math.max(self.next_id, data.next_id)
    end
    return self
end

function methods:problem() return self.error end

function methods:_stamp()
    return math.max(0, math.floor(number(self.clock()) or 0))
end

function methods:_trim()
    local entries = {}
    for _, entry in ipairs(self.entries) do entries[#entries + 1] = entry end
    table.sort(entries, newer)
    while #entries > self.retention do
        local index = #entries
        if entries[index] == self.entry then index = index - 1 end
        if index < 1 then break end
        table.remove(entries, index)
    end
    return entries
end

function methods:_write(now)
    if self.blocked then return false, self.error end
    local entries = self:_trim()
    self.last_attempt = now
    local previous, problem = self.read(self.path)
    if not previous then self.error = problem or 'The session file could not be read.'; return false, self.error end
    if not equal(previous, self.previous) then
        self.error = 'Another game client changed this character\'s session file. Your unsaved progress is still being tracked here; the saved file has not been overwritten.'
        return false, self.error
    end
    local data = { version = 1, next_id = self.next_id, entries = entries }
    local ok
    ok, problem = self.write(self.path, data)
    self.error = nil
    if not ok then self.error = problem or 'The session file could not be saved.' end
    if ok then
        self.entries, self.dirty, self.last_save = entries, false, now
        -- Compare the next read with the numbers written by the JSON encoder.
        self.previous = json.decode(json.encode(data))
    end
    return ok, self.error
end

function methods:_capture(now)
    if self.entry then
        self.entry.payload = self.tracker:export(now)
        self.entry.saved = self:_stamp()
        self.dirty = true
    end
end

function methods:checkpoint(now, force)
    now = number(now) or 0
    if not force and self.last_attempt and now >= self.last_attempt and now - self.last_attempt < SAVE_SECONDS then
        return self.error == nil, self.error
    end
    if self.entry and (force or self.tracker.started or self.tracker.gil.started or self.dirty) then self:_capture(now) end
    if not self.dirty then return true end
    return self:_write(now)
end

function methods:_create(snapshot, now, label)
    local stamp = self:_stamp()
    self.entry = { id = tostring(self.next_id), name = label or ((snapshot.job_name or tostring(snapshot.job)) .. ' session'),
        job_name = snapshot.job_name, created = stamp, saved = stamp, closed = false,
        payload = self.tracker:export(now) }
    self.next_id = self.next_id + 1
    self.entries[#self.entries + 1] = self.entry
    self.dirty = true
    self.resumed = false
end

function methods:select(snapshot, now, settings)
    if not coherent(snapshot) then return self.tracker, false, false end
    settings = settings or {}
    local config = settings.sessions or settings
    local retention = math.floor(math.max(1, math.min(LIMIT, number(config.retention) or 30)))
    if retention ~= self.retention then self.dirty = true end
    self.retention = retention
    self.resume = config.resume ~= false
    if self.entry and same(self.entry.payload.identity, snapshot) then return self.tracker, self.resumed, true end
    self:checkpoint(now, true)
    self.entry = nil
    self.tracker = tracker.new()
    local found
    if self.resume then
        for _, entry in ipairs(self.entries) do
            if not entry.closed and same(entry.payload.identity, snapshot) and (not found or newer(entry, found)) then found = entry end
        end
    end
    self.resumed = found ~= nil and self.tracker:restore(found.payload, now, snapshot)
    if self.resumed then
        self.entry = found
    else
        -- Turning resume off ends the previous sessions for this job.
        for _, entry in ipairs(self.entries) do
            if not entry.closed and same(entry.payload.identity, snapshot) then
                entry.closed = true
                entry.payload.buckets = {}
            end
        end
        self.tracker:observe(snapshot, now)
        self:_create(snapshot, now)
    end
    self.dirty = true
    self:checkpoint(now, true)
    return self.tracker, self.resumed, true
end

local function summary(entry, active, resumed)
    local data = entry.payload
    return { id = entry.id, name = entry.name, character_id = data.identity.id, job = data.identity.job,
        job_name = entry.job_name, created = entry.created, saved = entry.saved, closed = entry.closed,
        active = active, resumed = resumed == true, elapsed = data.elapsed, session_exp = data.session_exp,
        session_lp = data.session_lp, net_exp = data.net_exp, net_lp = data.net_lp,
        merits_gained = data.merits_gained, best_chain = data.best_chain }
end

function methods:current()
    if not self.entry then return nil end
    local row = summary(self.entry, true, self.resumed)
    row.elapsed = self.tracker:_elapsed(self.tracker.last_time or 0)
    row.best_chain = self.tracker.chain_state.best
    for _, key in ipairs({ 'session_exp', 'session_lp', 'net_exp', 'net_lp', 'merits_gained' }) do row[key] = self.tracker[key] end
    return row
end

function methods:list(character_id)
    if character_id == nil and self.entry then character_id = self.entry.payload.identity.id end
    local rows = {}
    for _, entry in ipairs(self.entries) do
        if character_id == nil or entry.payload.identity.id == character_id then
            rows[#rows + 1] = entry == self.entry and self:current() or summary(entry, false, false)
        end
    end
    table.sort(rows, newer)
    return rows
end

function methods:new_session(now, label)
    if not self.entry then return nil, 'No session is running for this character.' end
    if label ~= nil and not name(label) then return nil, 'Use 1 to 48 plain characters without ## for the session name.' end
    if self.blocked then return nil, self.error end
    local snapshot = self.tracker.snapshot
    if not coherent(snapshot) then return nil, 'Wait for your current job and EXP to load before starting a session.' end
    local ok, problem = self:checkpoint(now, true)
    if not ok then return nil, problem end
    self.entry.closed = true
    self.entry.payload.buckets = {}
    self.tracker:reset(now, true)
    self:_create(snapshot, now, label and name(label))
    ok, problem = self:checkpoint(now, true)
    -- The new in-memory session remains available if saving fails.
    return self.tracker, problem
end

function methods:detach(now)
    local _, problem = self:checkpoint(now, true)
    self.entry = nil
    self.tracker = tracker.new()
    self.resumed = false
    return self.tracker, problem
end

function methods:rename(id, label)
    label = name(label)
    if not label then return false, 'Use 1 to 48 plain characters without ## for the session name.' end
    for _, entry in ipairs(self.entries) do
        if entry.id == tostring(id) then
            local previous = entry.name
            entry.name = label
            self.dirty = true
            local ok, problem = self:_write(self.last_save or 0)
            if not ok then entry.name = previous end
            return ok, problem
        end
    end
    return false, 'That session is no longer saved.'
end

function methods:delete(id)
    for index, entry in ipairs(self.entries) do
        if entry.id == tostring(id) then
            if entry == self.entry then return false, 'Start a new session before deleting the current one.' end
            table.remove(self.entries, index)
            self.dirty = true
            local ok, problem = self:_write(self.last_save or 0)
            if not ok then table.insert(self.entries, index, entry) end
            return ok, problem
        end
    end
    return false, 'That session is no longer saved.'
end

local managers = {}
managers.__index = managers

function sessions.new(path, options)
    return setmetatable({ path = path, options = options or {}, stores = {}, tracker = tracker.new() }, managers)
end

local function character_id(value)
    return number(value) and value > 0 and value <= 4294967295 and value == math.floor(value)
end

function managers:_store(id)
    if not character_id(id) then return nil end
    if not self.stores[id] then
        local base = self.path:gsub('%.json$', '')
        self.stores[id] = open_store(base .. '-' .. string.format('%.0f', id) .. '.json', self.options, id)
    end
    return self.stores[id]
end

function managers:problem()
    if self.active and self.active.error then return self.active.error end
    for _, store in pairs(self.stores) do if store.error then return store.error end end
end

function managers:select(snapshot, now, settings)
    if not coherent(snapshot) then return self.tracker, false, false end
    local previous = self.active
    if self.active and self.character ~= snapshot.id then self.active:detach(now) end
    self.active, self.character = self:_store(snapshot.id), snapshot.id
    local resumed, ready
    self.tracker, resumed, ready = self.active:select(snapshot, now, settings)
    if self.active ~= previous then self.checkpoint_at = nil end
    return self.tracker, resumed, ready
end

function managers:checkpoint_due(now)
    now = number(now) or 0
    if not self.checkpoint_at or now >= self.checkpoint_at or now < self.checkpoint_time then return true end
    local active = self.active
    -- The first reward after a long idle period is still saved as soon as it is due.
    if active and not active.blocked and (active.dirty or (active.entry and active.tracker.started)) then
        return not active.last_attempt or now < active.last_attempt or now >= active.last_attempt + SAVE_SECONDS
    end
    return false
end

function managers:checkpoint(now, force)
    now = number(now) or 0
    local problem
    local next_check = now + SAVE_SECONDS
    for _, store in pairs(self.stores) do
        local ok, error_text = store:checkpoint(now, force)
        if not ok then problem = problem or error_text end
        if store.last_attempt and store.last_attempt + SAVE_SECONDS > now then
            next_check = math.min(next_check, store.last_attempt + SAVE_SECONDS)
        end
    end
    self.checkpoint_at, self.checkpoint_time = next_check, now
    return problem == nil, problem
end

local function qualified(row, id)
    if row then row.id = string.format('%.0f', id) .. ':' .. row.id end
    return row
end

function managers:current()
    return self.active and qualified(self.active:current(), self.character) or nil
end

function managers:list(id)
    id = id or self.character
    local store = id and self:_store(id)
    if not store then return {} end
    local rows = store:list(id)
    for _, row in ipairs(rows) do qualified(row, id) end
    return rows
end

-- Read-only archived rows stay reusable while the current session keeps ticking.
function managers:history(id)
    id = id or self.character
    local store = id and self:_store(id)
    if not store then
        self.empty_history = self.empty_history or {}
        return self.empty_history
    end
    local cached = store.history_cache
    if cached and cached.entries == store.entries and cached.active == store.entry then return cached.rows end
    local rows = {}
    for _, entry in ipairs(store.entries) do
        if entry ~= store.entry then rows[#rows + 1] = summary(entry, false, false) end
    end
    table.sort(rows, newer)
    for _, row in ipairs(rows) do qualified(row, id) end
    store.history_cache = { entries = store.entries, active = store.entry, rows = rows }
    return rows
end

function managers:new_session(now, label)
    if not self.active then return nil, 'No session is running for this character.' end
    local next_tracker, problem = self.active:new_session(now, label)
    if next_tracker then self.tracker = next_tracker end
    self.checkpoint_at = nil
    return next_tracker, problem
end

function managers:detach(now)
    local problem
    if self.active then local empty; empty, problem = self.active:detach(now) end
    self.active, self.character = nil, nil
    self.tracker = tracker.new()
    self.checkpoint_at = nil
    return self.tracker, problem
end

function managers:_record(id)
    if type(id) ~= 'string' then return nil end
    local character, record = id:match('^(%d+):(%d+)$')
    if tonumber(character) ~= self.character or not self.active then return nil end
    return record
end

function managers:rename(id, label)
    local record = self:_record(id)
    if not record then return false, 'That session is not for the current character.' end
    self.checkpoint_at = nil
    return self.active:rename(record, label)
end

function managers:delete(id)
    local record = self:_record(id)
    if not record then return false, 'That session is not for the current character.' end
    self.checkpoint_at = nil
    return self.active:delete(record)
end

return sessions
