local events = require('core.events');
local client = require('core.events_client');
local store = require('core.file_store');
local history = require('ui.history');
local runtime = {};
local methods = {};
methods.__index = methods;

function runtime.new(folder, options)
    return setmetatable({ folder = folder, options = options or {}, core = events.new() }, methods);
end

function methods:report(problem)
    if problem and problem ~= self.reported_error then
        self.reported_error = problem;
        if self.options.report then self.options.report('Event history was not saved: ' .. problem); end
    end
end

function methods:select(id, now)
    if type(id) ~= 'number' or id <= 0 or id % 1 ~= 0 then return false; end
    if self.id == id then return true; end
    local saved, issue = self:save(now, true);
    if not saved then self:report(issue); end
    self.core = events.new();
    self.observer = client.new(self.core, self.options);
    self.id, self.path = id, self.folder .. 'events-' .. tostring(id) .. '.json';
    self.saved_error, self.blocked, self.save_at, self.reported_error = nil, false, now, nil;
    self.core:context(id, 0, now, self.observer:utc(now), false);
    local data, problem = store.read(self.path);
    self.disk = data;
    if data and next(data) then
        if data.player_id ~= id then problem = 'Saved event data belongs to another character.';
        else
            local ok;
            ok, problem = self.core:restore(data, self.observer:utc(now));
            if ok then problem = nil; end
        end
    end
    if problem then self.saved_error, self.blocked = problem .. ' Your saved file was kept.', true; end
    self.saved_revision = self.core.revision;
    return true;
end

function methods:save(now, force)
    if not self.id or self.blocked then return self.saved_error == nil, self.saved_error; end
    if self.core.revision == self.saved_revision then return true; end
    if not force and self.save_at and now >= self.save_at and now - self.save_at < 30 then return true; end
    self.save_at = now;
    local data, problem = store.read(self.path);
    if not data or not history.equal(data, self.disk) then
        self.saved_error = problem or 'Another client changed this character\'s event history. Reload Momentum before saving again.';
        self.blocked = true;
        return false, self.saved_error;
    end
    ashita.fs.create_dir(self.folder);
    local payload = self.core:export(self.observer:utc(now));
    local ok;
    ok, problem = store.write(self.path, payload);
    if ok then self.disk, self.saved_revision, self.saved_error = payload, self.core.revision, nil;
    else self.saved_error = problem; end
    return ok, problem;
end

function methods:sample(snapshot, now, settings)
    if not snapshot or not snapshot.valid or not self:select(snapshot.id, now) then return; end
    local zone = self.observer.zone;
    self.observer:sample(snapshot, now, settings);
    if zone ~= self.observer.zone then self:save(now, true); end
end

function methods:packet(event, now, settings)
    if event.id == 0x00A then
        local kind, value = client.parse(event);
        if kind ~= 'zone' or not self:select(value.id, now) then return; end
    end
    if not self.observer then return; end
    self.observer:packet(event, now, settings);
    if event.id == 0x00A then self:save(now, true); end
end

function methods:outgoing(event, now, settings)
    if self.observer then self.observer:outgoing(event, now, settings); end
end

function methods:award(value, now, settings)
    if self.observer and (not settings.events or settings.events.enabled ~= false) then
        self.core:award(value, now, self.observer:utc(now));
    end
end

function methods:view(now, settings)
    local view = self.core:view(now, self.observer and self.observer:utc(now) or os.time(), settings);
    view.saved_error = self.saved_error;
    return view;
end

function methods:alerts(now, settings)
    return self.core:take_alerts(now, self.observer and self.observer:utc(now) or os.time(), settings);
end

function methods:clear(now)
    self.core:clear(now, self.observer and self.observer:utc(now) or os.time());
    return self:save(now, true);
end

function methods:detach(now)
    local saved, issue = self:save(now, true);
    if not saved then self:report(issue); end
    self.id, self.path, self.observer, self.saved_error, self.disk = nil, nil, nil, nil, nil;
    self.core = events.new();
    return saved, issue;
end

return runtime;
