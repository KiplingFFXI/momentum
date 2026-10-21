local store = require('core.file_store');
local cooldowns = {};
local methods = {};
methods.__index = methods;

local function finite(value)
    return type(value) == 'number' and value == value and value > 0 and value < 4294967295;
end

local function group_name(value)
    return type(value) == 'string' and value:gsub('[^ -~]', ''):match('^%s*(.-)%s*$'):sub(1, 80):lower() or '';
end

local function valid(data)
    if type(data) ~= 'table' then return false; end
    if next(data) == nil then return true; end
    if data.version ~= 1 or type(data.groups) ~= 'table' then return false; end
    local count = 0;
    for name, group in pairs(data.groups) do
        count = count + 1;
        if count > 128 or type(name) ~= 'string' or #name > 80 or type(group) ~= 'table' then return false; end
        for kind, record in pairs(group) do
            if (kind ~= 'dynamis' and kind ~= 'limbus') or type(record) ~= 'table'
                or not finite(record.ready_at) or not finite(record.character_id) or record.character_id % 1 ~= 0
                or not finite(record.observed_at) then return false; end
        end
    end
    return true;
end

function cooldowns.new(folder, options)
    options = options or {};
    return setmetatable({ folder = folder, path = folder .. 'account-cooldowns.json', read = options.read or store.read,
        write = options.write or store.write, report = options.report, own = {}, shared = {}, observed = {} }, methods);
end

function methods:problem(message)
    self.error = message;
    if message and self.reported ~= message then
        self.reported = message;
        if self.report then self.report('Account timers were not updated: ' .. message); end
    end
end

function methods:refresh(now, force)
    if self.group == '' or not self.group then return true; end
    if not force and self.checked and now >= self.checked and now - self.checked < 5 then return true; end
    self.checked = now;
    local data, problem = self.read(self.path);
    if not data or not valid(data) then
        self.failed_at = now;
        self:problem(problem or 'The saved account timer file is invalid. It was kept unchanged.');
        return false;
    end
    self.data = data;
    self.shared = data.groups and data.groups[self.group] or {};
    for kind, record in pairs(self.own) do
        if not self.shared[kind] or self.shared[kind].ready_at < record.ready_at then self.observed[kind] = nil; end
    end
    self.error, self.reported = nil, nil;
    return true;
end

function methods:select(id, settings, now)
    if not finite(id) or id % 1 ~= 0 then return; end
    local group = group_name(settings and settings.group);
    if self.id ~= id or self.group ~= group then
        self.id, self.group, self.checked, self.failed_at = id, group, nil, nil;
        self.own, self.shared, self.observed = {}, {}, {};
    end
    self.settings = settings or {};
    self:refresh(now, false);
end

function methods:observe(kind, ready_at, utc, now)
    if not self.id or (kind ~= 'dynamis' and kind ~= 'limbus') or not finite(ready_at) or not finite(utc) then return; end
    ready_at = math.floor(ready_at);
    self.own[kind] = { ready_at = ready_at, character_id = self.id, observed_at = math.floor(utc) };
    if self.group == '' or self.settings['share_' .. kind] == false or self.observed[kind] == ready_at then return; end
    if self.failed_at and now >= self.failed_at and now - self.failed_at < 5 then return; end
    if not self:refresh(now, true) then return; end
    local old = self.shared[kind];
    if old and old.ready_at >= ready_at then self.observed[kind] = ready_at; return; end
    local data = self.data;
    data.version, data.groups = 1, data.groups or {};
    if not data.groups[self.group] then
        local count = 0;
        for _ in pairs(data.groups) do count = count + 1; end
        if count >= 128 then
            self.failed_at = now;
            self:problem('Too many saved account groups. Use an existing group.');
            return;
        end
        data.groups[self.group] = {};
    end
    data.groups[self.group][kind] = self.own[kind];
    ashita.fs.create_dir(self.folder);
    local saved, problem = self.write(self.path, data);
    if saved then
        self.data, self.shared, self.observed[kind] = data, data.groups[self.group], ready_at;
        self.error, self.failed_at = nil, nil;
    else
        self.failed_at = now;
        self:problem(problem or 'The account timer could not be saved.');
    end
end

function methods:view(now, utc)
    if not finite(utc) then return { error = self.error }; end
    self:refresh(now, false);
    local result = { group = self.group, error = self.error };
    for _, kind in ipairs({ 'dynamis', 'limbus' }) do
        local record = self.own[kind];
        local shared = self.settings and self.settings['share_' .. kind] ~= false and self.shared[kind] or nil;
        if shared and (not record or shared.ready_at > record.ready_at) then record = shared; end
        if record then
            result[kind] = { ready_at = record.ready_at, deadline = record.ready_at,
                remaining = math.max(0, math.ceil(record.ready_at - utc)),
                shared = record.character_id ~= self.id, character_id = record.character_id,
                observed_at = record.observed_at, reminder = kind == 'limbus' };
        end
    end
    return result;
end

function methods:detach()
    self.id, self.group, self.checked, self.settings, self.failed_at = nil, nil, nil, nil, nil;
    self.own, self.shared, self.observed = {}, {}, {};
end

return cooldowns;
