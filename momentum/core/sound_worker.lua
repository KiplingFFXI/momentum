local ffi = require('ffi');
local paths = require('core.sound_paths');
local worker = {};
local methods = {};
methods.__index = methods;
local ACTIVE = 259;
local native_library;

local function quote(value)
    local output, slashes = { '"' }, 0;
    for index = 1, #value do
        local character = value:sub(index, index);
        if character == '\\' then slashes = slashes + 1;
        else
            output[#output + 1] = string.rep('\\', character == '"' and slashes * 2 + 1 or slashes) .. character;
            slashes = 0;
        end
    end
    output[#output + 1] = string.rep('\\', slashes * 2) .. '"';
    return table.concat(output);
end

local function native()
    if native_library ~= nil then return native_library or nil; end
    pcall(ffi.cdef, [[
        typedef struct {
            uint32_t cb;
            uint16_t *lpReserved, *lpDesktop, *lpTitle;
            uint32_t dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
            uint16_t wShowWindow, cbReserved2;
            uint8_t *lpReserved2;
            void *hStdInput, *hStdOutput, *hStdError;
        } momentum_sound_startup_w;
        typedef struct { void *hProcess, *hThread; uint32_t dwProcessId, dwThreadId; } momentum_sound_process_info;
        void* __cdecl momentum_launch_begin(const uint16_t*, const uint16_t*);
        int __cdecl momentum_launch_poll(void*, momentum_sound_process_info*, uint32_t*, uint32_t*);
        void __cdecl momentum_launch_cancel(void*);
        void __cdecl momentum_launch_release(void*);
        int __stdcall momentum_sound_multibyte_to_wide(uint32_t, uint32_t, const char*, int, uint16_t*, int) __asm__("MultiByteToWideChar");
        uint32_t __stdcall momentum_sound_current_process_id(void) __asm__("GetCurrentProcessId");
        int __stdcall momentum_sound_exit_code(void*, uint32_t*) __asm__("GetExitCodeProcess");
        int __stdcall momentum_sound_terminate(void*, uint32_t) __asm__("TerminateProcess");
        int __stdcall momentum_sound_close_handle(void*) __asm__("CloseHandle");
        uint32_t __stdcall momentum_sound_last_error(void) __asm__("GetLastError");
        void* __stdcall momentum_sound_load_library_w(const uint16_t*) __asm__("LoadLibraryW");
        void* __stdcall momentum_sound_proc_address(void*, const char*) __asm__("GetProcAddress");
        int __stdcall momentum_sound_free_library(void*) __asm__("FreeLibrary");
    ]]);
    local ok, library = pcall(ffi.load, 'kernel32');
    native_library = ok and library or false;
    return native_library or nil;
end

local function error_code(library)
    local ok, value = pcall(function() return tonumber(library.momentum_sound_last_error()); end);
    return ok and value or nil;
end

function worker.new(path, options)
    options = options or {};
    path = paths.utf8(path) or path;
    local folder = path:match('^(.*[\\/])') or '';
    return setmetatable({ path = path, launcher_path = folder .. 'momentum-sound-launch.dll',
        backend = options.backend, trace = options.trace, log_path = '' }, methods);
end

function methods:set_trace(callback, path)
    self.trace = type(callback) == 'function' and callback or nil;
    self.log_path = paths.utf8(path) or '';
end

function methods:log(event, fields)
    if self.trace then pcall(self.trace, event, fields or {}); end
end

function methods:library()
    return self.backend or native();
end

function methods:owned()
    return self.request ~= nil or self.process ~= nil or self.thread ~= nil;
end

function methods:launcher()
    if self.launcher_library ~= nil then return self.launcher_library or nil; end
    local ok, library = pcall(function()
        if not self.launcher_path:find('[\128-\255]') then return ffi.load(self.launcher_path); end
        local system = self:library();
        local path = system and paths.wide(system, self.launcher_path);
        local handle = path and system.momentum_sound_load_library_w(path);
        if handle == nil then return nil; end
        handle = ffi.gc(handle, system.momentum_sound_free_library);
        local result = { handle = handle };
        for name, signature in pairs({
            momentum_launch_begin = 'void* (__cdecl *)(const uint16_t*, const uint16_t*)',
            momentum_launch_poll = 'int (__cdecl *)(void*, momentum_sound_process_info*, uint32_t*, uint32_t*)',
            momentum_launch_cancel = 'void (__cdecl *)(void*)',
            momentum_launch_release = 'void (__cdecl *)(void*)',
        }) do
            local address = system.momentum_sound_proc_address(handle, name);
            if address == nil then return nil; end
            result[name] = ffi.cast(signature, address);
        end
        return result;
    end);
    self.launcher_library = ok and library or false;
    return self.launcher_library or nil;
end

function methods:release_request()
    if not self.request then return true; end
    local launcher = self:launcher();
    if not launcher then return false; end
    local ok = pcall(launcher.momentum_launch_release, self.request);
    if not ok then return false; end
    if ffi.gc then ffi.gc(self.request, nil); end
    self.request = nil;
    return true;
end

function methods:poll_request()
    local launcher = self:launcher();
    if not launcher then return false, 'Sound playback is unavailable. Reload Momentum and try again.'; end
    local info, code, elapsed = ffi.new('momentum_sound_process_info[1]'), ffi.new('uint32_t[1]'), ffi.new('uint32_t[1]');
    local ok, result = pcall(launcher.momentum_launch_poll, self.request, info, code, elapsed);
    if not ok then return false, 'The sound could not start. Reload Momentum and try again.'; end
    if result == 0 then return nil; end
    self:log('worker.launch.completed', { ok = result == 1, code = tonumber(code[0]), duration_ms = tonumber(elapsed[0]) });
    if result == 1 then
        self.process, self.thread, self.termination_requested = info[0].hProcess, info[0].hThread, nil;
    end
    local released = self:release_request();
    if not released then return false, 'The sound could not close. Try again.'; end
    if result ~= 1 then
        if tonumber(code[0]) == 1223 then return false; end
        return false, 'The sound could not start. Reload Momentum and try again.';
    end
    self:close_handle('thread', self:library());
    return true;
end

function methods:close_handle(key, library)
    if not self[key] then return true; end
    self:log('worker.close.before', { operation = key });
    local ok, result = pcall(library.momentum_sound_close_handle, self[key]);
    self:log('worker.close.after', { operation = key, ok = ok and result ~= 0, code = ok and result == 0 and error_code(library) or nil });
    if ok and result ~= 0 then self[key] = nil; return true; end
    return false;
end

function methods:exit_code(library)
    if not self.process then return 0; end
    local code = ffi.new('uint32_t[1]');
    local ok, result = pcall(library.momentum_sound_exit_code, self.process, code);
    if not ok or result == 0 then
        self:log('worker.poll.failed', { ok = false, code = error_code(library) });
        return nil;
    end
    return tonumber(code[0]);
end

function methods:stop(keep_pending)
    if not keep_pending then self.pending = nil; end
    if not self:owned() then self.stopping = nil; return true; end
    local library = self:library();
    if not library then return false, 'The previous sound could not close. Try again.'; end
    self.stopping = true;
    if self.request then
        local launcher = self:launcher();
        if not launcher then return false, 'The previous sound could not close. Try again.'; end
        local cancelled = pcall(launcher.momentum_launch_cancel, self.request);
        if not cancelled then return false, 'The previous sound could not close. Try again.'; end
        local ready = self:poll_request();
        if self.request or ready == nil then return false, 'The previous sound is still closing. Try again.'; end
    end
    if self.process then
        local code = self:exit_code(library);
        if code == ACTIVE and not self.termination_requested then
            self:log('worker.stop.before');
            local ok, result = pcall(library.momentum_sound_terminate, self.process, 1);
            if ok and result ~= 0 then self.termination_requested = true; end
            self:log('worker.stop.after', { ok = ok and result ~= 0, code = ok and result == 0 and error_code(library) or nil });
            code = self:exit_code(library);
        end
        if code == nil or code == ACTIVE then return false, 'The previous sound is still closing. Try again.'; end
    end
    local thread_closed = self:close_handle('thread', library);
    local process_closed = self:close_handle('process', library);
    if not thread_closed or not process_closed then return false, 'The previous sound could not close. Try again.'; end
    self.stopping, self.checked, self.termination_requested = nil, nil, nil;
    return true;
end

function methods:start(path, volume)
    if type(path) ~= 'string' or path == '' or #path > 32000 or path:find('%z')
        or type(volume) ~= 'number' or volume ~= volume or volume < 0 or volume > 1000 or volume % 1 ~= 0 then
        return false, 'That sound could not play. Try another file.';
    end
    path = paths.utf8(path);
    if not path then return false, 'That sound filename could not be read. Try another file.'; end
    local stopped, problem = self:stop();
    if not stopped then
        self.pending = { path = path, volume = volume };
        self:log('worker.queued');
        return true;
    end
    local library = self:library();
    if not library then return false, 'Sound playback is unavailable. Reload Momentum and try again.'; end
    local ok, result = pcall(function()
        local parent = tonumber(library.momentum_sound_current_process_id());
        if not parent or parent <= 0 or parent > 4294967295 or parent % 1 ~= 0 then return false; end
        local command = quote(self.path) .. ' ' .. quote(path) .. ' ' .. tostring(volume) .. ' ' .. tostring(parent) .. ' ' .. quote(self.log_path);
        local application, arguments = paths.wide(library, self.path), paths.wide(library, command);
        if not application or not arguments then return false; end
        local launcher = self:launcher();
        if not launcher then return false; end
        self:log('worker.launch.before', { volume = volume, phase = 'submit' });
        local request = launcher.momentum_launch_begin(application, arguments);
        self:log('worker.launch.after', { ok = request ~= nil, phase = 'submit' });
        if request == nil then return false; end
        if ffi.gc then
            request = ffi.gc(request, function(value) launcher.momentum_launch_release(value); end);
        end
        self.request, self.checked, self.termination_requested = request, nil, nil;
        return true;
    end);
    if not ok or not result then return false, 'The sound could not start. Reload Momentum and try again.'; end
    return true;
end

function methods:update(now)
    if not self:owned() then return nil; end
    if type(now) ~= 'number' or now ~= now then return nil; end
    if self.checked and now >= self.checked and now - self.checked < 0.25 then return nil; end
    self.checked = now;
    if self.stopping then
        local pending = self.pending;
        local closed = self:stop(true);
        if not closed then return nil; end
        self.pending = nil;
        if pending then
            local launched, problem = self:start(pending.path, pending.volume);
            return { launched = launched, problem = problem };
        end
        return { cancelled = true };
    end
    if self.request then
        local launched, problem = self:poll_request();
        if launched == nil then return nil; end
        return { launched = launched, problem = problem };
    end
    local library = self:library();
    if not library then return nil; end
    local code = self:exit_code(library);
    if code == nil or code == ACTIVE then return nil; end
    self:log('worker.exit', { code = code, ok = code == 0 });
    local thread_closed = self:close_handle('thread', library);
    local process_closed = self:close_handle('process', library);
    if not thread_closed or not process_closed then self.stopping = true; end
    return { code = code, problem = code ~= 0 and 'That sound could not play. Try another file.' or nil };
end

function methods:shutdown()
    self.pending = nil;
    if not self:owned() then return true; end
    local library = self:library();
    if not library then return false; end
    if not self:release_request() then return false; end
    if self.process then
        local code = self:exit_code(library);
        if (code == ACTIVE or code == nil) and not self.termination_requested then
            local ok, result = pcall(library.momentum_sound_terminate, self.process, 1);
            self:log('worker.shutdown', { ok = ok and result ~= 0 });
            if not ok or result == 0 then return false; end
            self.termination_requested = true;
        end
    end
    local thread_closed = self:close_handle('thread', library);
    local process_closed = self:close_handle('process', library);
    if thread_closed and process_closed then self.termination_requested = nil; end
    return thread_closed and process_closed;
end

return worker;
