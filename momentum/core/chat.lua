local chat = {};
local reader = {};
reader.__index = reader;

-- Native layout offsets: github.com/Windower/packages at fa326785d1fd58488e1507d9949b4baac82ffa91,
-- libraries/memory/types.lua, lines 333-349 and 476-479. Scaling follows Ashita's CYmdb fields.
-- The Phoenix client reports left, top, right, bottom at 0x40-0x46.
local CHAT_PATTERN = '85C0753B8B15';
local SCALE_PATTERN = 'A1????????85C05E74????80';

local function integer(value)
    return type(value) == 'number' and value == value and value ~= math.huge
        and value ~= -math.huge and value == math.floor(value);
end

local function span(address, size)
    return integer(address) and integer(size) and address >= 0x10000 and size > 0
        and address + size <= 0x100000000;
end

local function u16(data, offset)
    local low, high = data:byte(offset + 1, offset + 2);
    return low + high * 256;
end

local function u32(data, offset)
    return u16(data, offset) + u16(data, offset + 2) * 65536;
end

local function copy(value)
    if type(value) ~= 'table' then return value; end
    local result = {};
    for key, item in pairs(value) do result[key] = copy(item); end
    return result;
end

local function native_backend()
    local ok, ffi = pcall(require, 'ffi');
    local sized, pointer_size = false, nil;
    if ok then sized, pointer_size = pcall(ffi.sizeof, 'void*'); end
    if not sized or pointer_size ~= 4 then return nil, 'Chat snapping needs the 32-bit FFXI client.'; end
    local ready, kernel, process = pcall(function()
        ffi.cdef[[
            int __stdcall ReadProcessMemory(void*, const void*, void*, size_t, size_t*);
            void* __stdcall GetCurrentProcess(void);
        ]];
        local library = ffi.load('kernel32');
        return library, library.GetCurrentProcess();
    end);
    if not ready then return nil, 'Momentum cannot read your chat window yet.'; end
    return {
        range = function()
            return ashita.memory.get_base('FFXiMain.dll'), ashita.memory.get_size('FFXiMain.dll');
        end,
        find = function(pattern, usage)
            return ashita.memory.find('FFXiMain.dll', 0, pattern, 0, usage);
        end,
        read = function(address, size)
            local buffer, read_count = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]');
            local result = kernel.ReadProcessMemory(process, ffi.cast('const void*', address), buffer, size, read_count);
            if result == 0 or tonumber(read_count[0]) ~= size then return nil; end
            return ffi.string(buffer, size);
        end,
    };
end

function chat.new(backend)
    return setmetatable({ backend = backend, loaded = false, reason = 'The chat window position and size have not loaded yet.' }, reader);
end

function reader:reset()
    self.last, self.last_display, self.retained, self.visible = nil, nil, nil, nil;
    if self.loaded then self.reason = 'The chat window position and size have not loaded yet.'; end
end

function reader:bytes(address, size)
    if not span(address, size) then return nil; end
    local ok, value = pcall(self.backend.read, address, size);
    if not ok or type(value) ~= 'string' or #value ~= size then return nil; end
    return value;
end

function reader:in_module(address, size)
    return span(address, size) and address >= self.base and address + size <= self.base + self.size;
end

function reader:operand(pattern, offset)
    local ok, match = pcall(self.backend.find, pattern, 0);
    if not ok or not self:in_module(match, offset + 4) then return nil; end
    local checked, duplicate = pcall(self.backend.find, pattern, 1);
    if not checked or (duplicate ~= nil and duplicate ~= 0) then return nil; end
    local bytes = self:bytes(match + offset, 4);
    if not bytes then return nil; end
    local address = u32(bytes, 0);
    return self:in_module(address, 4) and address or nil;
end

function reader:load()
    self.loaded, self.last, self.retained, self.visible = false, nil, nil, nil;
    if not self.backend then
        self.backend, self.reason = native_backend();
        if not self.backend then return false, self.reason; end
    end
    local ok, base, size = pcall(self.backend.range);
    if not ok or not span(base, size) then
        self.reason = 'The game client is not ready yet.';
        return false, self.reason;
    end
    self.base, self.size = base, size;
    self.chat_table, self.scale_slot = nil, nil;
    self.chat_table = self:operand(CHAT_PATTERN, 6);
    if self.chat_table and self:in_module(self.chat_table, 8) then self.scale_slot = self:operand(SCALE_PATTERN, 1); end
    if not self.chat_table or not self:in_module(self.chat_table, 8) or not self.scale_slot then
        self.reason = 'Momentum could not find your chat window position and size.';
        return false, self.reason;
    end
    self.loaded, self.reason = true, nil;
    return true;
end

function reader:snapshot()
    if not self.loaded then return nil, self.reason; end
    local pointers = self:bytes(self.chat_table, 8);
    local scale_pointer = self:bytes(self.scale_slot, 4);
    if not pointers or not scale_pointer then return nil, 'The chat window position and size are not ready yet.'; end
    local scale_address = u32(scale_pointer, 0);
    if not span(scale_address, 0x18) then return nil, 'The game menu size is not available yet.'; end
    local dimensions = self:bytes(scale_address + 0x10, 8);
    if not dimensions then return nil, 'The game menu size is not available yet.'; end
    local snapshot = {
        window_width = u16(dimensions, 0), window_height = u16(dimensions, 2),
        menu_width = u16(dimensions, 4), menu_height = u16(dimensions, 6), windows = {},
    };
    for index = 1, 2 do
        local address = u32(pointers, (index - 1) * 4);
        if address ~= 0 then
            if not span(address, 0x4E) then return nil, 'Momentum cannot find a chat window.'; end
            local data = self:bytes(address + 0x40, 14);
            if not data then return nil, 'Momentum cannot find a chat window.'; end
            local active = data:byte(14);
            if active ~= 0 and active ~= 1 then return nil, 'The chat window is not ready yet.'; end
            if index == 1 then snapshot.main_active = active == 1; end
            if active == 1 then
                snapshot.windows[index] = {
                    x = u16(data, 0), y = u16(data, 2), right = u16(data, 4), bottom = u16(data, 6),
                };
            end
        end
    end
    if self:bytes(self.chat_table, 8) ~= pointers or self:bytes(self.scale_slot, 4) ~= scale_pointer
        or self:bytes(scale_address + 0x10, 8) ~= dimensions then
        return nil, 'The chat window moved or resized. Waiting for it to settle.';
    end
    return snapshot, nil, pointers:sub(1, 4) .. scale_pointer;
end

-- Keep menu-to-screen conversion separate from the native reads.
function chat.project(snapshot, display_width, display_height)
    if type(snapshot) ~= 'table' or not integer(display_width) or not integer(display_height)
        or display_width <= 0 or display_height <= 0 then return nil, 'The game window size is not available yet.'; end
    local menu_width, menu_height = snapshot.menu_width, snapshot.menu_height;
    if not integer(menu_width) or not integer(menu_height) or menu_width <= 0 or menu_height <= 0
        or not integer(snapshot.window_width) or not integer(snapshot.window_height)
        or snapshot.window_width <= 0 or snapshot.window_height <= 0 then
        return nil, 'The game menu size is not available yet.';
    end
    if type(snapshot.windows) ~= 'table' then
        return nil, 'The main chat window is not active.';
    end
    local scale_x, scale_y = display_width / menu_width, display_height / menu_height;
    local windows = {};
    for index = 1, 2 do
        local window = snapshot.windows[index];
        if window then
            if type(window) ~= 'table' or not integer(window.x) or not integer(window.y)
                or not integer(window.right) or not integer(window.bottom) or window.x < 0 or window.y < 0
                or window.right <= window.x or window.bottom <= window.y or window.right > menu_width
                or window.bottom > menu_height then
                return nil, 'The reported chat window is outside the game menu area.';
            end
            windows[#windows + 1] = { x = window.x * scale_x, y = window.y * scale_y,
                width = (window.right - window.x) * scale_x, height = (window.bottom - window.y) * scale_y, index = index };
        end
    end
    if not snapshot.windows[1] then return nil, 'The main chat window is not active.', true; end
    local main = windows[1];
    return { x = main.x, y = main.y, width = main.width, height = main.height, windows = windows }, nil, true;
end

function reader:read(display_width, display_height, keep_anchor)
    local snapshot, reason, identity = self:snapshot();
    self.last = snapshot;
    self.last_display = { width = display_width, height = display_height };
    local result, valid, retained;
    self.visible = nil;
    if snapshot then result, reason, valid = chat.project(snapshot, display_width, display_height); end
    if valid then self.visible = snapshot.main_active; end
    if result and self.visible == true then
        self.retained = self.retained or {};
        self.retained.native, self.retained.identity = snapshot, identity;
    elseif self.visible == false and self.retained then
        local saved = self.retained.native;
        if self.retained.identity ~= identity or saved.menu_width ~= snapshot.menu_width
            or saved.menu_height ~= snapshot.menu_height or saved.window_width ~= snapshot.window_width
            or saved.window_height ~= snapshot.window_height then
            self.retained = nil;
        elseif keep_anchor == true then
            -- Keep the last chat edge while closed, but protect the current second window.
            local anchored = copy(snapshot);
            anchored.windows[1] = saved.windows[1];
            retained = chat.project(anchored, display_width, display_height);
            if not retained then self.retained = nil; end
        end
    else
        self.retained = nil;
    end
    self.reason = reason;
    return result, reason, self.visible, retained;
end

function reader:status()
    return { loaded = self.loaded, reason = self.reason, visible = self.visible, native = copy(self.last) };
end

function reader:describe()
    if not self.last then return self.reason or 'The chat window position and size are not available yet.'; end
    local parts = {};
    if self.reason then parts[#parts + 1] = self.reason; end
    parts[#parts + 1] = 'Chat state: ' .. (self.visible == true and 'active' or self.visible == false and 'inactive' or 'unknown');
    for index = 1, 2 do
        local window = self.last.windows[index];
        parts[#parts + 1] = window and string.format('Chat %d: L=%d T=%d R=%d B=%d', index, window.x, window.y, window.right, window.bottom)
            or string.format('Chat %d: inactive', index);
    end
    parts[#parts + 1] = string.format('Menu: %dx%d', self.last.menu_width, self.last.menu_height);
    parts[#parts + 1] = string.format('Window: %dx%d', self.last.window_width, self.last.window_height);
    parts[#parts + 1] = string.format('Display: %s x %s', tostring(self.last_display.width), tostring(self.last_display.height));
    return table.concat(parts, '; ');
end

local current = chat.new();
function chat.load() return current:load(); end
function chat.reset() return current:reset(); end
function chat.read(width, height, keep_anchor) return current:read(width, height, keep_anchor); end
function chat.status() return current:status(); end
function chat.describe() return current:describe(); end

return chat;
