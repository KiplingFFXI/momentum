local store = require('core.file_store');
local history = require('ui.history');
local profiles = {};
local excluded = { window = true, job_links = true, shared = true, preview = true, sessions = true, planner = true };

function profiles.capture(settings)
    local result = {};
    for key, value in pairs(settings) do
        if (not excluded[key]) then result[key] = history.copy(value); end
    end
    return result;
end

function profiles.apply(settings, profile)
    if profile.appearance_version == nil then settings.appearance_version = 0; end
    for key, value in pairs(profile) do
        if (not excluded[key] and settings[key] ~= nil and type(settings[key]) == type(value)) then
            settings[key] = history.copy(value);
        end
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
