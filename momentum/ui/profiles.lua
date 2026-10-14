local store = require('core.file_store');
local history = require('ui.history');
local profiles = {};
local excluded = { window = true, job_links = true, shared = true, preview = true, sessions = true, planner = true };

function profiles.capture(settings)
    local result = {};
    for key, value in pairs(settings) do
        if (not excluded[key]) then result[key] = history.copy(value); end
    end
    return require('ui.modes').capture(result);
end

function profiles.apply(settings, profile)
    if profile.modes == nil and type(profile.display) == 'table' and settings.modes then
        if settings.modes.selected ~= 'auto' then require('ui.modes').select(settings, 'auto'); end
        settings.modes = { selected = 'auto', active = 'exp', layout_version = 0, auto = {}, exp = {}, merits = {}, previous_display = {} };
    end
    if settings.dynamis and settings.dynamis.layout_active then
        require('ui.dynamis_layout').switch(settings, false);
    end
    if profile.appearance_version == nil then settings.appearance_version = 0; end
    for key, value in pairs(profile) do
        if (not excluded[key] and settings[key] ~= nil and type(settings[key]) == type(value)) then
            settings[key] = history.copy(value);
        end
    end
    if type(profile.bar) == 'table' and type(profile.visibility) ~= 'table' then
        settings.visibility.mode = nil;
    end
end

function profiles.new(folder)
    local self = { path = folder .. 'profiles.json', folder = folder };
    function self:names()
        local data, err = store.read(self.path);
        if (data == nil) then return {}, err; end
        local names = {};
        for name, value in pairs(data) do
            if (type(name) == 'string' and type(value) == 'table') then names[#names + 1] = name; end
        end
        table.sort(names);
        return names;
    end
    function self:save(name, settings)
        name = type(name) == 'string' and name:match('^%s*(.-)%s*$') or '';
        if (#name == 0 or #name > 40 or name:find('[^\32-\126]') or name:find('##', 1, true)
            or name:lower() == 'none') then
            return false, 'Use 1 to 40 plain characters without ##. Choose a name other than None, which turns off job profiles.';
        end
        local data, err = store.read(self.path);
        if (data == nil) then return false, err; end
        data[name] = profiles.capture(settings);
        ashita.fs.create_dir(self.folder);
        return store.write(self.path, data);
    end
    function self:load(name, settings)
        local data, err = store.read(self.path);
        if (data == nil) then return false, err; end
        if (type(data[name]) ~= 'table') then return false, 'That profile was not found.'; end
        profiles.apply(settings, data[name]);
        return true;
    end
    function self:delete(name)
        local data, err = store.read(self.path);
        if (data == nil) then return false, err; end
        if (data[name] == nil) then return false, 'That profile was not found.'; end
        data[name] = nil;
        return store.write(self.path, data);
    end
    return self;
end

return profiles;
