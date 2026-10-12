-- Optional local playback. The bundled Square Enix sounds are not covered by the GPL.
local ffi = require('ffi');
pcall(ffi.cdef, 'unsigned long __stdcall mciSendStringA(const char *command, char *answer, unsigned int size, void *window);');
local loaded, winmm = pcall(ffi.load, 'winmm');
local sound = {};
sound.BUILT_IN = addon.path:gsub('[\\/]+$', '') .. '\\sounds\\';
sound.FOLDER = AshitaCore:GetInstallPath() .. '\\config\\addons\\momentum\\sounds\\';
local alias = 'momentum_food_sound';
local files, opened, level, failed, problem = {}, nil, nil, nil, nil;

local function mci(command)
    if (not loaded) then return false; end
    local ok, result = pcall(winmm.mciSendStringA, command, nil, 0, nil);
    return ok and result == 0;
end

local function valid(name)
    if (type(name) ~= 'string' or name == '' or #name > 200 or name:find('[%c"\\/:]') or name:find('..', 1, true)) then return false; end
    local lower = name:lower();
    return lower:match('%.mp3$') ~= nil or lower:match('%.wav$') ~= nil;
end

function sound.make_folder()
    if (not ashita.fs.exists(sound.FOLDER)) then ashita.fs.create_dir(sound.FOLDER); end
end

function sound.refresh()
    sound.make_folder();
    files = {};
    local taken = {};
    for _, folder in ipairs({ sound.BUILT_IN, sound.FOLDER }) do
        local found = {};
        if (ashita.fs.exists(folder)) then
            for _, name in ipairs(ashita.fs.get_directory(folder, '.*', false) or {}) do
                if (valid(name) and not taken[name:lower()]) then found[#found + 1] = name; taken[name:lower()] = true; end
            end
        end
        table.sort(found, function(a, b) return a:lower() < b:lower(); end);
        for _, name in ipairs(found) do files[#files + 1] = name; end
    end
end

function sound.files() return files; end

function sound.find(word)
    local wanted = tostring(word):lower();
    for _, name in ipairs(files) do
        local lower = name:lower();
        if (lower == wanted or lower:gsub('%.%w+$', '') == wanted) then return name; end
    end
end

function sound.close()
    if (opened ~= nil) then mci('close ' .. alias); end
    opened, level = nil, nil;
end

local function give_up(name)
    sound.close();
    failed = name;
    problem = tostring(name) .. " won't play. Pick a .mp3 or .wav file from the sound list.";
    return false;
end

local function open(name)
    if (not valid(name)) then return give_up(name); end
    local path = sound.BUILT_IN .. name;
    if (not ashita.fs.exists(path)) then path = sound.FOLDER .. name; end
    if (not ashita.fs.exists(path)) then return give_up(name); end
    mci('close ' .. alias);
    opened, level = nil, nil;
    if (not mci(('open "%s" type mpegvideo alias %s'):format(path, alias))) then return give_up(name); end
    opened, failed, problem = name, nil, nil;
    return true;
end

function sound.use(name, retry)
    if (name == '') then sound.close(); failed, problem = nil, nil; return true; end
    if (name == opened) then return true; end
    if (name == failed and not retry) then return false; end
    return open(name);
end

local function start(volume)
    if (volume ~= level) then
        if (not mci(('setaudio %s volume to %d'):format(alias, volume))) then return false; end
        level = volume;
    end
    return mci('play ' .. alias .. ' from 0');
end

function sound.play(volume)
    if (opened == nil) then return false; end
    volume = tonumber(volume) or 100;
    if (volume ~= volume) then volume = 100; end
    volume = math.floor(math.max(0, math.min(100, volume)) * 10 + 0.5);
    local name = opened;
    if (start(volume)) then return true; end
    -- A changed sound device or callback thread can require one fresh handle.
    return open(name) and (start(volume) or give_up(name));
end

function sound.is_open(name) return opened ~= nil and opened == name; end
function sound.problem(name) return name == failed and problem or nil; end

return sound;
