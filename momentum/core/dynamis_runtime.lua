local dynamis = require('core.dynamis');
local client = require('core.dynamis_client');
local store = require('core.file_store');
local history = require('ui.history');
local runtime = {};
local methods = {};
methods.__index = methods;

function runtime.new(folder, options)
    return setmetatable({ folder = folder, options = options or {}, core = dynamis.new() }, methods);
end

function methods:report(problem)
    if problem and problem ~= self.reported_error then
        self.reported_error = problem;
        if self.options.report then self.options.report('Dynamis history was not saved: ' .. problem); end
    end
end

function methods:select(id, now)
    if type(id) ~= 'number' or id <= 0 or id % 1 ~= 0 then return false; end
    if self.id == id then return true; end
    local saved, issue = self:save(now, true);
    if not saved then self:report(issue); end
    self.core = dynamis.new();
    self.observer = client.new(self.core, self.options);
    self.id, self.path = id, self.folder .. 'dynamis-' .. tostring(id) .. '.json';
    self.saved_error, self.blocked, self.save_at, self.reported_error = nil, false, now, nil;
    local data, problem = store.read(self.path);
    self.disk = data;
    if data and next(data) then
        if data.player_id ~= id then problem = 'Saved Dynamis data belongs to another character.';
        else
            local ok;
            ok, problem = self.core:restore(data, now, self.observer:utc(now));
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
        self.saved_error = problem or 'Another client changed this character\'s Dynamis history. Reload Momentum before saving again.';
        self.blocked = true;
        return false, self.saved_error;
    end
    ashita.fs.create_dir(self.folder);
    local payload = self.core:export();
    local ok;
    ok, problem = store.write(self.path, payload);
    if ok then
        self.disk, self.saved_revision, self.saved_error = payload, self.core.revision, nil;
    else self.saved_error = problem; end
    return ok, problem;
end

function methods:sample(snapshot, now, settings)
    if not snapshot or not snapshot.valid or not self:select(snapshot.id, now) then return; end
    local old_zone = self.observer.zone;
    self.observer:sample(snapshot, now, settings);
    if old_zone ~= self.observer.zone then self:save(now, true); end
end

function methods:packet(event, now, settings)
    local kind, value;
    if event.id == 0x00A then kind, value = client.parse(event); end
    if kind == 'zone' then
        if not self:select(value.id, now) then return; end
    end
    if not self.observer then return; end
    self.observer:packet(event, now, settings);
    if kind == 'zone' then self:save(now, true); end
end

function methods:view(now, settings)
    local utc = self.observer and self.observer:utc(now) or os.time();
    local view = self.core:view(now, utc, settings);
    view.saved_error = self.saved_error;
    view.clock_estimated = not self.observer or self.observer.clock_estimated;
    return view;
end

function methods:alerts(now, settings)
    return self.core:take_alerts(now, settings, self.observer and self.observer:utc(now) or os.time());
end

function methods:clear(now)
    if not self.core:clear_totals(now, self.observer and self.observer:utc(now) or os.time()) then
        return false, 'Wait for your Perpetual Hourglass to load first.';
    end
    return self:save(now, true);
end

function methods:detach(now)
    local saved, issue = self:save(now, true);
    if not saved then self:report(issue); end
    self.id, self.path, self.observer, self.saved_error, self.disk = nil, nil, nil, nil, nil;
    self.core = dynamis.new();
    return saved, issue;
end

return runtime;
