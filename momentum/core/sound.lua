-- Optional local playback. The bundled Square Enix sounds are not covered by the GPL.
local ffi = require('ffi');
local bit = require('bit');
local paths = require('core.sound_paths');
local directory_library;
local sound = {};
local addon_path = paths.utf8(addon.path) or addon.path;
local install_path = paths.utf8(AshitaCore:GetInstallPath()) or AshitaCore:GetInstallPath();
sound.BUILT_IN = addon_path:gsub('[\\/]+$', '') .. '\\sounds\\';
sound.FOLDER = install_path .. '\\config\\addons\\momentum\\sounds\\';
sound.WORKER = addon_path:gsub('[\\/]+$', '') .. '\\bin\\momentum-sound.exe';
sound.LAUNCHER = addon_path:gsub('[\\/]+$', '') .. '\\bin\\momentum-sound-launch.dll';
local playback = require('core.sound_worker').new(sound.WORKER);
local files, opened, failed, problem, playing = {}, nil, nil, nil, nil;
local listed = false;
local locations, saved_copies = {}, {};
local failures, failure_order = {}, {};
local aliases, alias_order, unicode_failures = {}, {}, 0;
local trace;

local function failure_key(name)
    return type(name) == 'string' and name:lower() or tostring(name);
end

local function forget_aliases()
    aliases, alias_order = {}, {};
end

local function failed_key(name)
    local key = failure_key(name);
    if failures[key] then return key; end
    local unicode = key:find('[\128-\255]') ~= nil;
    if not unicode and unicode_failures == 0 then return nil; end
    if aliases[key] ~= nil then return aliases[key] or nil; end
    local found;
    for _, other in ipairs(failure_order) do
        if (unicode or other:find('[\128-\255]')) and paths.same_name(key, other) then found = other; break; end
    end
    aliases[key] = found or false;
    alias_order[#alias_order + 1] = key;
    if #alias_order > 128 then aliases[table.remove(alias_order, 1)] = nil; end
    return found;
end

local function remember_failure(name, message)
    message = message or 'That sound could not play. Try another file.';
    local key = failed_key(name) or failure_key(name);
    if not failures[key] then
        failure_order[#failure_order + 1] = key;
        if key:find('[\128-\255]') then unicode_failures = unicode_failures + 1; end
        if #failure_order > 64 then
            local oldest = table.remove(failure_order, 1);
            failures[oldest] = nil;
            if oldest:find('[\128-\255]') then unicode_failures = unicode_failures - 1; end
        end
    end
    failures[key], failed, problem = message, name, message;
    forget_aliases();
end

local function clear_failure(name)
    local key = failed_key(name);
    if not key then return; end
    local clear_trace = failed_key(failed) == key;
    failures[key] = nil;
    for index = #failure_order, 1, -1 do
        if failure_order[index] == key then table.remove(failure_order, index); break; end
    end
    if key:find('[\128-\255]') then unicode_failures = unicode_failures - 1; end
    forget_aliases();
    if clear_trace then failed, problem = nil, nil; end
end

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
    if (type(name) ~= 'string' or name == '' or name:find('[%c"\\/:]') or name:find('..', 1, true)) then return false; end
    if #name > 200 then
        local _, characters = name:gsub('[^\128-\191]', '');
        if characters > 200 then return false; end
    end
    local lower = name:lower();
    return lower:match('%.mp3$') ~= nil or lower:match('%.wav$') ~= nil;
end

function sound.make_folder()
    return paths.make_folder(sound.FOLDER);
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
                uint16_t cFileName[260];
                uint16_t cAlternateFileName[14];
            } momentum_find_data_w;
            void* __stdcall momentum_find_first_file_w(const uint16_t*, momentum_find_data_w*) __asm__("FindFirstFileW");
            int __stdcall momentum_find_next_file_w(void*, momentum_find_data_w*) __asm__("FindNextFileW");
            int __stdcall momentum_find_close(void*) __asm__("FindClose");
        ]]);
        directory_library = paths.library() or false;
    end
    if not directory_library then return {}; end
    local names, handle = {}, nil;
    -- Keep directory scans out of Ashita's regex and locale handling.
    pcall(function()
        local data = ffi.new('momentum_find_data_w[1]');
        local pattern = paths.wide(directory_library, folder .. '*');
        if not pattern then return; end
        handle = directory_library.momentum_find_first_file_w(pattern, data);
        if handle == nil or handle == ffi.cast('void*', -1) then handle = nil; return; end
        repeat
            if bit.band(tonumber(data[0].dwFileAttributes), 0x10) == 0 then
                local name = paths.text(directory_library, data[0].cFileName, 260);
                if name then names[#names + 1] = name; end
            end
        until directory_library.momentum_find_next_file_w(handle, data) == 0;
    end);
    if handle ~= nil then pcall(function() directory_library.momentum_find_close(handle); end); end
    return names;
end

function sound.refresh(retry)
    log('sound.refresh.before');
    sound.make_folder();
    files = {};
    locations, saved_copies = {}, {};
    if retry ~= false then
        failures, failure_order, failed, problem, unicode_failures = {}, {}, nil, nil, 0;
        forget_aliases();
    end
    local taken = {};
    for _, folder in ipairs({ sound.BUILT_IN, sound.FOLDER }) do
        local found = {};
        if (paths.exists(folder)) then
            for _, name in ipairs(directory_files(folder)) do
                if (valid(name) and not taken[name:lower()]) then found[#found + 1] = name; taken[name:lower()] = true; end
            end
        end
        table.sort(found, function(a, b) return a:lower() < b:lower(); end);
        for _, name in ipairs(found) do files[#files + 1] = name; end
    end
    listed = true;
    log('sound.refresh.after', { count = #files });
end

function sound.invalidate()
    listed = false;
    locations, saved_copies = {}, {};
end

function sound.files()
    if not listed then sound.refresh(false); end
    return files;
end

function sound.find(word)
    local wanted = (paths.utf8(tostring(word)) or tostring(word)):lower();
    for _, name in ipairs(sound.files()) do
        local lower = name:lower();
        if (lower == wanted or lower:gsub('%.%w+$', '') == wanted) then return name; end
    end
end

function sound.close(final)
    log('sound.close.before');
    local stopped, issue = playback:stop();
    if final then stopped = playback:shutdown(); end
    if not stopped then remember_failure(playing or opened, issue); end
    opened, playing = nil, nil;
    log('sound.close.after', { ok = stopped });
end

local function give_up(name)
    opened = nil;
    remember_failure(name, tostring(name) .. " won't play. Pick a .mp3 or .wav file from the sound list.");
    log('sound.failure');
    return false;
end

local function path_of(name)
    local path = sound.BUILT_IN .. name;
    if paths.exists(path) then return path; end
    path = sound.FOLDER .. name;
    return paths.exists(path) and path or nil;
end

function sound.location(name)
    name = paths.utf8(name);
    if not valid(name) then return { kind = 'missing', can_save = false }; end
    if locations[name] then return locations[name]; end
    local path = path_of(name);
    local kind = 'missing';
    if path == sound.BUILT_IN .. name then
        local lower = name:lower();
        kind = (lower == 'ff vii save.mp3' or lower == 'ff ix moogle.mp3') and 'bundled' or 'addon';
    elseif path then kind = 'permanent'; end
    local saved = kind == 'addon' and saved_copies[name:lower()] == true;
    local permanent = kind == 'addon' and paths.attributes(sound.FOLDER .. name) or nil;
    local exists = permanent ~= nil and bit.band(permanent, 0x10) == 0;
    local result = { kind = kind, path = path, can_save = kind == 'addon' and not saved and not exists,
        saved_copy = saved, permanent_exists = exists };
    locations[name] = result;
    return result;
end

function sound.save_custom(name)
    name = paths.utf8(name);
    if not valid(name) or sound.location(name).kind ~= 'addon' then
        return false, 'Choose a custom sound from the addon folder first.';
    end
    local library = paths.library();
    if not library then return false, 'Sound copying is unavailable. Copy the file into the permanent folder yourself.'; end
    local collision = 'A file with this name already exists in the permanent folder. Rename one of the files and try again.';
    local ok, copied, problem = pcall(function()
        local source, destination = sound.BUILT_IN .. name, sound.FOLDER .. name;
        local value = paths.attributes(source);
        if not value or bit.band(value, 0x10) ~= 0 then
            return false, 'That sound is missing or is a folder. Press Refresh and choose a custom sound file.';
        end
        local existing, code = paths.attributes(destination);
        if existing then return false, collision; end
        if code ~= 2 and code ~= 3 then return false, 'The permanent folder could not be checked. No files were changed.'; end
        sound.make_folder();
        local folder = paths.attributes(sound.FOLDER);
        if not folder or bit.band(folder, 0x10) == 0 then
            return false, 'The permanent folder is unavailable. No files were changed.';
        end
        local source_w, destination_w = paths.wide(library, source), paths.wide(library, destination);
        if not source_w or not destination_w then return false, 'That sound filename could not be read. Rename it and try again.'; end
        if library.momentum_copy_sound_file_w(source_w, destination_w, 1) == 0 then
            code = tonumber(library.momentum_sound_path_error());
            if code == 80 or code == 183 then return false, collision; end
            return false, 'Could not copy that sound. Your original file was kept. Check that the permanent folder is writable, then try again.';
        end
        locations, saved_copies[name:lower()] = {}, true;
        return true, 'Saved a copy in the permanent folder.';
    end);
    if not ok then return false, 'Could not copy that sound. Your original file was kept. Copy it into the permanent folder yourself.'; end
    return copied, problem;
end

function sound.use(name, retry)
    log('sound.use', { retry = retry == true });
    name = paths.utf8(name);
    if (name == '') then opened, failed, problem = nil, nil, nil; return true; end
    if failed_key(name) and not retry then return false; end
    if retry then clear_failure(name); end
    if not valid(name) then return give_up(name); end
    if (name == opened) then
        return true;
    end
    if not path_of(name) then return give_up(name); end
    opened = name;
    log('sound.use.after', { ok = true });
    return true;
end

function sound.play(volume)
    if opened == nil or failed_key(opened) then return false; end
    volume = tonumber(volume) or 100;
    if (volume ~= volume) then volume = 100; end
    volume = math.floor(math.max(0, math.min(100, volume)) * 10 + 0.5);
    log('sound.play.before', { volume = volume });
    local path = path_of(opened);
    if not path then return give_up(opened); end
    if not paths.exists(sound.WORKER) or not paths.exists(sound.LAUNCHER) then
        remember_failure(opened, 'The sound player is missing. Reinstall Momentum and try again.');
        log('sound.play.after', { ok = false });
        return false;
    end
    local launched, issue = playback:start(path, volume);
    if launched then playing = opened; clear_failure(opened);
    else remember_failure(opened, issue or 'That sound could not play. Try another file.'); end
    log('sound.play.after', { ok = launched });
    return launched;
end

function sound.update(now)
    local result = playback:update(now);
    if result then
        if result.problem then remember_failure(playing or opened, result.problem); end
        if not result.launched then playing = nil; end
    end
end

function sound.is_open(name) return opened ~= nil and opened == paths.utf8(name); end
function sound.problem(name)
    local key = failed_key(paths.utf8(name));
    return key and failures[key] or nil;
end

return sound;
