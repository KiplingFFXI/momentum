-- Optional local playback. The bundled Square Enix sounds are not covered by the GPL.
local ffi = require('ffi');
local bit = require('bit');
local directory_library;
local sound = {};
sound.BUILT_IN = addon.path:gsub('[\\/]+$', '') .. '\\sounds\\';
sound.FOLDER = AshitaCore:GetInstallPath() .. '\\config\\addons\\momentum\\sounds\\';
sound.WORKER = addon.path:gsub('[\\/]+$', '') .. '\\bin\\momentum-sound.exe';
sound.LAUNCHER = addon.path:gsub('[\\/]+$', '') .. '\\bin\\momentum-sound-launch.dll';
local playback = require('core.sound_worker').new(sound.WORKER);
local files, opened, failed, problem, playing = {}, nil, nil, nil, nil;
local trace;

local function file_label(name)
    if name == nil or name == '' then return '<none>'; end
    if name == 'FF VII Save.mp3' or name == 'FF IX Moogle.mp3' then return name; end
    return '<custom sound>';
end

local function log(event, fields)
    if not trace then return; end
    fields = fields or {};
    fields.selected, fields.opened, fields.failed = file_label(opened), file_label(opened), file_label(failed);
    pcall(trace, event, fields);
end

function sound.set_trace(callback, path)
    trace = type(callback) == 'function' and callback or nil;
    playback:set_trace(trace, path);
end

local function valid(name)
    if (type(name) ~= 'string' or name == '' or #name > 200 or name:find('[%c"\\/:]') or name:find('..', 1, true)) then return false; end
    local lower = name:lower();
    return lower:match('%.mp3$') ~= nil or lower:match('%.wav$') ~= nil;
end

function sound.make_folder()
    if (not ashita.fs.exists(sound.FOLDER)) then ashita.fs.create_dir(sound.FOLDER); end
end

local function directory_files(folder)
    if directory_library == nil then
        pcall(ffi.cdef, [[
            typedef struct {
                uint32_t dwFileAttributes;
                uint32_t ftCreationTime[2];
                uint32_t ftLastAccessTime[2];
                uint32_t ftLastWriteTime[2];
                uint32_t nFileSizeHigh;
                uint32_t nFileSizeLow;
                uint32_t dwReserved0;
                uint32_t dwReserved1;
                char cFileName[260];
                char cAlternateFileName[14];
            } momentum_find_data_a;
            void* __stdcall momentum_find_first_file_a(const char*, momentum_find_data_a*) __asm__("FindFirstFileA");
            int __stdcall momentum_find_next_file_a(void*, momentum_find_data_a*) __asm__("FindNextFileA");
            int __stdcall momentum_find_close(void*) __asm__("FindClose");
        ]]);
        local ok, library = pcall(ffi.load, 'kernel32');
        directory_library = ok and library or false;
    end
    if not directory_library then return {}; end
    local names, handle = {}, nil;
    -- Keep directory scans out of Ashita's regex and locale handling.
    pcall(function()
        local data = ffi.new('momentum_find_data_a[1]');
        handle = directory_library.momentum_find_first_file_a(folder .. '*', data);
        if handle == nil or handle == ffi.cast('void*', -1) then handle = nil; return; end
        repeat
            if bit.band(tonumber(data[0].dwFileAttributes), 0x10) == 0 then
                local name = ffi.string(data[0].cFileName, 260):match('^([^%z]*)%z');
                if name then names[#names + 1] = name; end
            end
        until directory_library.momentum_find_next_file_a(handle, data) == 0;
    end);
    if handle ~= nil then pcall(function() directory_library.momentum_find_close(handle); end); end
    return names;
end

function sound.refresh()
    log('sound.refresh.before');
    sound.make_folder();
    files = {};
    local taken = {};
    for _, folder in ipairs({ sound.BUILT_IN, sound.FOLDER }) do
        local found = {};
        if (ashita.fs.exists(folder)) then
            for _, name in ipairs(directory_files(folder)) do
                if (valid(name) and not taken[name:lower()]) then found[#found + 1] = name; taken[name:lower()] = true; end
            end
        end
        table.sort(found, function(a, b) return a:lower() < b:lower(); end);
        for _, name in ipairs(found) do files[#files + 1] = name; end
    end
    log('sound.refresh.after', { count = #files });
end

function sound.files() return files; end

function sound.find(word)
    local wanted = tostring(word):lower();
    for _, name in ipairs(files) do
        local lower = name:lower();
        if (lower == wanted or lower:gsub('%.%w+$', '') == wanted) then return name; end
    end
end

function sound.close(final)
    log('sound.close.before');
    local stopped, issue = playback:stop();
    if final then stopped = playback:shutdown(); end
    if not stopped then failed, problem = playing or opened, issue; end
    opened, playing = nil, nil;
    log('sound.close.after', { ok = stopped });
end

local function give_up(name)
    opened = nil;
    failed = name;
    problem = tostring(name) .. " won't play. Pick a .mp3 or .wav file from the sound list.";
    log('sound.failure');
    return false;
end

local function path_of(name)
    local path = sound.BUILT_IN .. name;
    if (not ashita.fs.exists(path)) then path = sound.FOLDER .. name; end
    return ashita.fs.exists(path) and path or nil;
end

function sound.use(name, retry)
    log('sound.use', { retry = retry == true });
    if (name == '') then opened, failed, problem = nil, nil, nil; return true; end
    if (name == failed and not retry) then return false; end
    if (name == opened) then
        if retry then failed, problem = nil, nil; end
        return true;
    end
    if not valid(name) or not path_of(name) then return give_up(name); end
    opened, failed, problem = name, nil, nil;
    log('sound.use.after', { ok = true });
    return true;
end

function sound.play(volume)
    if (opened == nil) then return false; end
    volume = tonumber(volume) or 100;
    if (volume ~= volume) then volume = 100; end
    volume = math.floor(math.max(0, math.min(100, volume)) * 10 + 0.5);
    log('sound.play.before', { volume = volume });
    local path = path_of(opened);
    if not path then return give_up(opened); end
    if not ashita.fs.exists(sound.WORKER) or not ashita.fs.exists(sound.LAUNCHER) then
        failed, problem = opened, 'The sound player is missing. Reinstall Momentum and try again.';
        log('sound.play.after', { ok = false });
        return false;
    end
    local launched, issue = playback:start(path, volume);
    if launched then playing, failed, problem = opened, nil, nil;
    else failed, problem = opened, issue or 'That sound could not play. Try another file.'; end
    log('sound.play.after', { ok = launched });
    return launched;
end

function sound.update(now)
    local result = playback:update(now);
    if result then
        if result.problem then failed, problem = playing or opened, result.problem; end
        if not result.launched then playing = nil; end
    end
end

function sound.is_open(name) return opened ~= nil and opened == name; end
function sound.problem(name) return name == failed and problem or nil; end

return sound;
