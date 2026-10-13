package.preload['core.chat'] = nil;
package.loaded['core.chat'] = nil;
local chat = require('core.chat');
local count = 0;
local function check(value, message)
    assert(value, message);
    count = count + 1;
end
local function near(left, right)
    return math.abs(left - right) < 0.000001;
end
local function fixture()
    local state = { bytes = {}, finds = 0, reads = 0, forbidden = 0, chat_match = 0x110000,
        scale_match = 0x120000, chat_table = 0x130000, scale_slot = 0x140000,
        scale_object = 0x230000, main = 0x240000, secondary = 0x250000 };
    function state:write(address, value, size)
        for offset = 0, size - 1 do
            self.bytes[address + offset] = value % 256;
            value = math.floor(value / 256);
        end
    end
    function state:window(address, x, y, right, bottom, active)
        for offset = 0, 13 do self.bytes[address + 0x40 + offset] = 0; end
        self:write(address + 0x40, x, 2); self:write(address + 0x42, y, 2);
        self:write(address + 0x44, right, 2); self:write(address + 0x46, bottom, 2);
        self:write(address + 0x4D, active, 1);
    end
    state:write(state.chat_match + 6, state.chat_table, 4);
    state:write(state.scale_match + 1, state.scale_slot, 4);
    state:write(state.chat_table, state.main, 4); state:write(state.chat_table + 4, state.secondary, 4);
    state:write(state.scale_slot, state.scale_object, 4);
    state:write(state.scale_object + 0x10, 1920, 2); state:write(state.scale_object + 0x12, 1080, 2);
    state:write(state.scale_object + 0x14, 1920, 2); state:write(state.scale_object + 0x16, 1080, 2);
    state:window(state.main, 14, 700, 994, 1050, 1);
    state:window(state.secondary, 1000, 850, 1600, 1040, 0);
    local backend = {};
    backend.range = function() return 0x100000, 0x100000; end;
    backend.find = function(pattern, usage)
        state.finds = state.finds + 1;
        if state.throw_find then error('scan failed'); end
        if usage > 0 then return state.duplicate and 0x180000 or 0; end
        if state.no_match then return 0; end
        return pattern == '85C0753B8B15' and state.chat_match or state.scale_match;
    end;
    backend.read = function(address, size)
        state.reads = state.reads + 1;
        if address < 0x10000 or address + size > 0x100000000 then state.forbidden = state.forbidden + 1; end
        if state.throw_read then error('read failed'); end
        if state.on_read then state.on_read(address, size); end
        local bytes = {};
        for offset = 0, size - 1 do
            local byte = state.bytes[address + offset];
            if byte == nil then return nil; end
            bytes[#bytes + 1] = string.char(byte);
        end
        local result = table.concat(bytes);
        return state.short_read and result:sub(2) or result;
    end;
    local reader = chat.new(backend);
    return reader, state, backend;
end

local r, s = fixture();
local result, reason = r:read(1920, 1080);
check(result == nil and type(reason) == 'string' and s.finds == 0 and s.reads == 0, 'Read before load stays unavailable without scanning.');
check(r:load(), 'Verified module operands load.');
check(s.finds == 4, 'Each signature is found once and checked for ambiguity at load.');
result, reason = r:read(1920, 1080);
check(result and reason == nil and result.x == 14 and result.y == 700 and result.width == 980 and result.height == 350,
    'A main window projects to its reported edges at equal resolutions.');
check(#result.windows == 1 and result.windows[1].index == 1, 'An inactive secondary window is omitted.');
check(s.finds == 4, 'Reading geometry never rescans the module.');
check(r:describe():find('Chat 1: L=14 T=700 R=994 B=1050', 1, true) and r:describe():find('Menu: 1920x1080', 1, true),
    'Diagnostics report raw geometry and menu dimensions without pointer values.');
local status = r:status(); status.native.windows[1].x = 900;
check(r:status().native.windows[1].x == 14, 'Diagnostic snapshots cannot mutate reader state.');
s:window(s.secondary, 1000, 850, 1600, 1040, 1);
result = r:read(1920, 1080);
check(#result.windows == 2 and result.windows[2].x == 1000 and result.windows[2].index == 2
    and result.windows[2].width == 600 and result.windows[2].height == 190,
    'Active secondary bounds are provided for collision avoidance.');
s:window(s.main, 60, 450, 1260, 950, 1);
result = r:read(1920, 1080);
check(result.x == 60 and result.y == 450 and result.width == 1200 and result.height == 500,
    'Native chat moves and resizes are observed without reload.');
s:write(s.scale_object + 0x14, 3840, 2); s:write(s.scale_object + 0x16, 2160, 2);
result = r:read(1920, 1080);
check(result.x == 30 and result.y == 225 and result.width == 600 and result.height == 250,
    'Projection follows changed menu resolution without caching its scale.');
result = r:read(960, 540);
check(result.x == 15 and near(result.y, 112.5) and result.width == 300 and result.height == 125,
    'Fractional scaled bounds stay exact so layout can round each docking edge in the safe direction.');

r, s = fixture();
s:window(s.main, 16, 821, 1086, 1044, 1);
check(r:load(), 'The captured client fixture loads.');
result, reason = r:read(1920, 1080);
check(result and reason == nil and result.x == 16 and result.y == 821 and result.width == 1070 and result.height == 223,
    'The observed client endpoints decode as a 1070 by 223 rectangle, not oversized dimensions.');
check(r:status().native.windows[1].right == 1086 and r:status().native.windows[1].bottom == 1044
    and r:status().native.windows[1].width == nil, 'Raw diagnostics keep explicit right and bottom endpoints.');
check(r:describe():find('Chat 1: L=16 T=821 R=1086 B=1044', 1, true),
    'Client diagnostics label all four endpoints.');
result = r:read(1280, 720);
check(near(result.x, 16 * 2 / 3) and near(result.y, 821 * 2 / 3)
    and near(result.width, 1070 * 2 / 3) and near(result.height, 223 * 2 / 3)
    and near(result.x + result.width, 724) and near(result.y + result.height, 696),
    'The observed rectangle scales by its endpoint differences without a second origin offset.');
s:window(s.secondary, 1086, 850, 1800, 1044, 1);
result = r:read(1280, 720);
check(#result.windows == 2 and near(result.windows[2].x, 724) and near(result.windows[2].width, 476)
    and near(result.windows[2].height, 194 * 2 / 3), 'Secondary endpoints use the same scaled projection.');

for _, endpoints in ipairs({ { 14, 1050 }, { 13, 1050 }, { 994, 700 }, { 994, 699 }, { 1921, 1050 }, { 994, 1081 } }) do
    r, s = fixture(); r:load();
    s:window(s.main, 14, 700, endpoints[1], endpoints[2], 1);
    check(r:read(1920, 1080) == nil, 'Zero, reversed, and out-of-menu main endpoints are rejected.');
end
r, s = fixture(); r:load(); s:window(s.main, 14, 700, 1920, 1080, 1);
result = r:read(1920, 1080);
check(result and result.width == 1906 and result.height == 380, 'Endpoints exactly on the menu boundary remain valid.');
r, s = fixture(); r:load(); s:window(s.secondary, 1000, 850, 999, 1040, 1);
check(r:read(1920, 1080) == nil, 'An active secondary window with reversed endpoints also fails closed.');

for _, change in ipairs({ 'no_match', 'duplicate', 'throw_find', 'throw_read', 'short_read' }) do
    r, s = fixture(); s[change] = true;
    local loaded, failure = r:load();
    check(not loaded and type(failure) == 'string', 'Missing, ambiguous, or unreadable signatures fail closed: ' .. change);
    check(r:read(1920, 1080) == nil, 'An unsuccessful load never supplies a rectangle.');
end
r, s = fixture(); s.chat_match = 0xFFFF0;
check(not r:load() and s.reads == 0, 'A scan result outside the module is never dereferenced.');
r, s = fixture(); s:write(s.chat_match + 6, 0xF00000, 4);
check(not r:load(), 'A chat global outside the verified module is rejected.');
r, s = fixture(); s:write(s.scale_match + 1, 0, 4);
check(not r:load(), 'A null scaling global is rejected.');
local bad_range;
r, s, bad_range = fixture(); bad_range.range = function() return nil, nil; end;
check(not r:load() and s.reads == 0 and s.finds == 0, 'An unavailable module does not trigger a scan or read.');
r, s, bad_range = fixture(); bad_range.range = function() error('no module'); end;
check(not r:load(), 'A module lookup error stays contained.');

for _, address in ipairs({ 0, 1, 0xFFFF, 0xFFFFFFFE }) do
    r, s = fixture(); check(r:load(), 'Pointer fixture loads.');
    s:write(s.chat_table, address, 4);
    check(r:read(1920, 1080) == nil and s.forbidden == 0, 'Bad native pointers never reach the memory backend.');
end
for _, change in ipairs({ 'throw_read', 'short_read' }) do
    r, s = fixture(); r:load(); check(r:read(1920, 1080), 'A prior valid read is available.');
    s[change] = true;
    check(r:read(1920, 1080) == nil and r:status().native == nil, 'Read failure clears prior bounds: ' .. change);
end
r, s = fixture(); r:load(); s.bytes[s.main + 0x40] = nil;
check(r:read(1920, 1080) == nil, 'Unreadable main-window memory fails closed.');
r, s = fixture(); r:load(); s.bytes[s.secondary + 0x40] = nil;
check(r:read(1920, 1080) == nil, 'Unreadable secondary-window state cannot silently bypass collision checks.');
r, s = fixture(); r:load(); s:write(s.chat_table + 4, 0, 4);
check(#r:read(1920, 1080).windows == 1, 'A null secondary window is a valid single-window layout.');
r, s = fixture(); r:load(); s:write(s.main + 0x4D, 0, 1);
check(r:read(1920, 1080) == nil, 'An inactive main window does not become a guessed screen dock.');
r, s = fixture(); r:load(); s:write(s.main + 0x4D, 255, 1);
check(r:read(1920, 1080) == nil, 'An invalid native bool is rejected.');

r, s = fixture(); r:load();
local visible, retained;
local reads_before = s.reads;
result, reason, visible, retained = r:read(1920, 1080, true);
local reads_per_snapshot = s.reads - reads_before;
check(result and visible == true and retained == nil, 'Active chat returns current bounds and confirmed visibility.');
s:write(s.main + 0x4D, 0, 1);
reads_before = s.reads;
result, reason, visible, retained = r:read(1920, 1080, true);
check(result == nil and type(reason) == 'string' and visible == false and retained and retained.x == 14
    and retained.width == 980, 'Closed chat keeps the old read result and separately offers its last verified anchor.');
check(s.reads - reads_before == reads_per_snapshot and s.finds == 4,
    'Closed chat adds no native reads or signature scans.');
check(r:status().visible == false and r:describe():find('Chat state: inactive', 1, true),
    'Diagnostics distinguish confirmed inactive chat from unknown state.');
retained.x = 999;
result, reason, visible, retained = r:read(960, 540, true);
check(result == nil and visible == false and retained.x == 7 and retained.width == 490,
    'Display scaling reprojects native retained bounds, and returned rectangles cannot change the cache.');
s:window(s.secondary, 100, 500, 800, 1060, 1);
result, reason, visible, retained = r:read(1920, 1080, true);
check(visible == false and #retained.windows == 2 and retained.windows[2].x == 100
    and retained.windows[2].y + retained.windows[2].height == 1060,
    'A newly opened or moved second window remains a current exclusion area while main chat is closed.');
s:write(s.secondary + 0x4D, 0, 1);
result, reason, visible, retained = r:read(1920, 1080, true);
check(#retained.windows == 1, 'An inactive second window does not linger in the retained anchor.');
s:window(s.main, 30, 650, 1030, 1040, 1);
result, reason, visible, retained = r:read(1920, 1080, true);
check(result.x == 30 and result.width == 1000 and visible == true and retained == nil,
    'Reopening chat immediately returns its current position and size.');
s:write(s.main + 0x4D, 0, 1);
result, reason, visible, retained = r:read(1920, 1080, true);
check(retained.x == 30 and retained.width == 1000, 'A later close uses the newly verified anchor.');
local reads_before_reset, finds_before_reset = s.reads, s.finds;
r:reset();
check(r:status().loaded and r:status().visible == nil and r:status().native == nil,
    'Runtime reset clears visibility and cached geometry while keeping the reader loaded.');
check(s.reads == reads_before_reset and s.finds == finds_before_reset, 'Runtime reset does not read or scan native memory.');
result, reason, visible, retained = r:read(1920, 1080, true);
check(visible == false and retained == nil, 'Closed chat cannot retain an anchor from before reset.');
s:write(s.main + 0x4D, 1, 1);
result, reason, visible, retained = r:read(1920, 1080, true);
check(visible == true and result.x == 30, 'Active chat recovers immediately after reset without rescanning.');
s:write(s.main + 0x4D, 0, 1);
result, reason, visible, retained = r:read(1920, 1080, true);
check(visible == false and retained.x == 30 and s.finds == finds_before_reset,
    'An anchor observed after reset can be retained on the next close.');
check(r:load(), 'Reloading the reader remains supported.');
result, reason, visible, retained = r:read(1920, 1080, true);
check(result == nil and visible == false and retained == nil,
    'A closed chat without a current-load observation never gets a guessed anchor.');

for _, change in ipairs({ 'throw_read', 'short_read', 'null_main', 'invalid_active', 'bad_main', 'bad_secondary', 'bad_dimensions' }) do
    r, s = fixture(); r:load(); r:read(1920, 1080, true);
    if change == 'null_main' then s:write(s.chat_table, 0, 4);
    elseif change == 'invalid_active' then s:write(s.main + 0x4D, 255, 1);
    elseif change == 'bad_main' then s:window(s.main, 14, 700, 14, 1050, 1);
    elseif change == 'bad_secondary' then s:window(s.secondary, 1000, 850, 999, 1040, 1);
    elseif change == 'bad_dimensions' then s:write(s.scale_object + 0x14, 0, 2);
    else s[change] = true; end
    result, reason, visible, retained = r:read(1920, 1080, true);
    check(result == nil and visible == nil and retained == nil, 'Invalid state is unknown, not closed: ' .. change);
    s.throw_read, s.short_read = false, false;
    s:write(s.chat_table, s.main, 4);
    s:write(s.scale_object + 0x14, 1920, 2);
    s:window(s.main, 14, 700, 994, 1050, 0);
    s:window(s.secondary, 1000, 850, 1600, 1040, 0);
    result, reason, visible, retained = r:read(1920, 1080, true);
    check(visible == false and retained == nil, 'A read failure clears the old anchor until chat is observed again: ' .. change);
end
for _, offset in ipairs({ 0x10, 0x12, 0x14, 0x16 }) do
    r, s = fixture(); r:load(); r:read(1920, 1080, true);
    s:write(s.main + 0x4D, 0, 1);
    local original = (offset == 0x10 or offset == 0x14) and 1920 or 1080;
    s:write(s.scale_object + offset, original + 100, 2);
    result, reason, visible, retained = r:read(1920, 1080, true);
    check(visible == false and retained == nil, 'A changed native resolution invalidates retained geometry: ' .. offset);
    s:write(s.scale_object + offset, original, 2);
    result, reason, visible, retained = r:read(1920, 1080, true);
    check(retained == nil, 'Returning to an old resolution cannot revive a cleared anchor: ' .. offset);
end
r, s = fixture(); r:load(); r:read(1920, 1080, true);
s:write(s.chat_table, s.secondary, 4);
result, reason, visible, retained = r:read(1920, 1080, true);
check(visible == false and retained == nil, 'A replacement main window cannot inherit another window\'s anchor.');
r, s = fixture(); r:load(); r:read(1920, 1080, true);
s:write(s.main + 0x4D, 0, 1);
result, reason, visible, retained = r:read(0, 1080, true);
check(visible == nil and retained == nil, 'Invalid display dimensions cannot expose retained geometry.');
result, reason, visible, retained = r:read(1920, 1080, true);
check(retained == nil, 'An invalid projection clears the retained anchor.');

local project, projections = chat.project, 0;
chat.project = function(...)
    projections = projections + 1;
    return project(...);
end;
r, s = fixture(); r:load(); r:read(1920, 1080);
s:write(s.main + 0x4D, 0, 1);
local projections_before, native_before = projections, s.reads;
result, reason, visible, retained = r:read(1920, 1080);
check(result == nil and visible == false and retained == nil,
    'Ordinary reads preserve closed visibility without returning an unused anchor.');
check(projections - projections_before == 1 and s.reads - native_before == reads_per_snapshot,
    'A closed-chat read without an anchor request projects only once with unchanged native reads.');
projections_before, native_before = projections, s.reads;
result, reason, visible, retained = r:read(1920, 1080, true);
check(visible == false and retained and retained.width == 980,
    'Enabling retained anchoring while chat is already closed can use its verified earlier position.');
check(projections - projections_before == 2 and s.reads - native_before == reads_per_snapshot,
    'Only an explicit anchor request adds the retained projection, without extra native reads.');
projections_before = projections;
result, reason, visible, retained = r:read(1920, 1080, false);
check(visible == false and retained == nil and projections - projections_before == 1,
    'An explicit false request also skips the retained projection.');
chat.project = project;
for _, failure in ipairs({ 'dimensions', 'pointer', 'unreadable' }) do
    r, s = fixture(); r:load(); r:read(1920, 1080);
    s:write(s.main + 0x4D, 0, 1);
    if failure == 'dimensions' then s:write(s.scale_object + 0x14, 2020, 2);
    elseif failure == 'pointer' then s:write(s.chat_table, s.secondary, 4);
    else s.throw_read = true; end
    result, reason, visible, retained = r:read(1920, 1080);
    check(result == nil and retained == nil, 'Unused anchoring still checks changed native state: ' .. failure);
    s.throw_read = false;
    s:write(s.chat_table, s.main, 4);
    s:write(s.scale_object + 0x14, 1920, 2);
    result, reason, visible, retained = r:read(1920, 1080, true);
    check(visible == false and retained == nil, 'A later anchor request cannot revive invalidated bounds: ' .. failure);
end
r, s = fixture(); r:load(); s:write(s.scale_slot, 0, 4);
check(r:read(1920, 1080) == nil, 'A disappearing scaling object is handled.');
r, s = fixture(); r:load(); s:write(s.scale_object + 0x16, 0, 2);
check(r:read(1920, 1080) == nil and r:describe():find('Menu: 1920x0', 1, true),
    'Zero menu dimensions fail closed but remain inspectable.');
r, s = fixture(); r:load(); s:write(s.main + 0x44, 65535, 2);
check(r:read(1920, 1080) == nil and r:describe():find('R=65535', 1, true),
    'Out-of-bounds raw geometry stays inspectable but cannot position the bar.');

for _, changed in ipairs({ 'chat', 'scale', 'dimensions' }) do
    r, s = fixture(); r:load();
    s.on_read = function(address)
        if address == s.main + 0x40 then
            if changed == 'chat' then s:write(s.chat_table, s.secondary, 4); end
            if changed == 'scale' then s:write(s.scale_slot, s.secondary, 4); end
            if changed == 'dimensions' then s:write(s.scale_object + 0x14, 1280, 2); end
        end
    end;
    result, reason = r:read(1920, 1080);
    check(result == nil and reason == 'The chat window moved or resized. Waiting for it to settle.', 'A changed ' .. changed .. ' snapshot is rejected.');
end

local base = { window_width = 1920, window_height = 1080, menu_width = 1920, menu_height = 1080,
    windows = { { x = 14, y = 700, right = 994, bottom = 1050 } } };
result = chat.project(base, 3840, 2160);
check(result.x == 28 and result.y == 1400 and result.width == 1960 and result.height == 700,
    'A high-density display projects each edge consistently.');
for _, bad in ipairs({ 0, -1, 0 / 0, math.huge, '1920', 0.5 }) do
    check(chat.project(base, bad, 1080) == nil, 'Invalid display dimensions are rejected.');
end
for _, key in ipairs({ 'x', 'y', 'right', 'bottom' }) do
    local before = base.windows[1][key]; base.windows[1][key] = -1;
    check(chat.project(base, 1920, 1080) == nil, 'Invalid native field is rejected: ' .. key);
    base.windows[1][key] = before;
end
base.windows[1].bottom = 1081;
check(chat.project(base, 1920, 1080) == nil, 'A bottom edge past the menu area is rejected.');
check(chat.project(nil, 1920, 1080) == nil, 'Missing native data remains unknown.');
base.windows[1] = { x = 16, y = 821, width = 1086, height = 1044 };
check(chat.project(base, 1920, 1080) == nil, 'Old dimension names are not accepted through a heuristic fallback.');

local function native_fixture(options)
    options = options or {};
    local _, state, backend = fixture();
    state.kernel_loads, state.process_calls, state.copy_calls = 0, 0, 0;
    ashita.memory.get_base = function(name)
        assert(name == 'FFXiMain.dll'); return 0x100000;
    end;
    ashita.memory.get_size = function(name)
        assert(name == 'FFXiMain.dll'); return 0x100000;
    end;
    ashita.memory.find = function(name, size, pattern, offset, usage)
        assert(name == 'FFXiMain.dll' and size == 0 and offset == 0);
        return backend.find(pattern, usage);
    end;
    local kernel = {
        GetCurrentProcess = function() state.process_calls = state.process_calls + 1; return 77; end,
        ReadProcessMemory = function(handle, address, buffer, size, bytes_read)
            assert(handle == 77);
            state.copy_calls = state.copy_calls + 1;
            if options.read_failure then return 0; end
            if options.read_throw then error('copy failed'); end
            local data = backend.read(address, size);
            if not data then return 0; end
            for index = 1, #data do buffer[index - 1] = data:byte(index); end
            bytes_read[0] = options.partial and size - 1 or size;
            return 1;
        end,
    };
    package.loaded.ffi = {
        sizeof = function() return options.pointer_size or 4; end,
        cdef = function(text)
            if options.declaration_error then error('declaration failed'); end
            assert(text:find('__stdcall ReadProcessMemory', 1, true));
        end,
        load = function(name)
            state.kernel_loads = state.kernel_loads + 1;
            assert(name == 'kernel32');
            if options.library_error then error('library unavailable'); end
            return kernel;
        end,
        new = function() return { [0] = 0 }; end,
        cast = function(kind, address) assert(kind == 'const void*'); return address; end,
        string = function(buffer, size)
            local result = {};
            for index = 0, size - 1 do result[#result + 1] = string.char(buffer[index]); end
            return table.concat(result);
        end,
    };
    return chat.new(), state;
end
r, s = native_fixture();
check(s.kernel_loads == 0 and s.copy_calls == 0, 'Import and construction do not access native memory.');
check(r:load() and s.process_calls == 1 and s.kernel_loads == 1, 'Native reads use only the current-process handle.');
result = r:read(1920, 1080);
check(result and result.x == 14 and result.height == 350 and s.copy_calls > 0,
    'The native adapter decodes successful local-buffer copies.');
for _, options in ipairs({ { read_failure = true }, { partial = true }, { read_throw = true },
    { declaration_error = true }, { library_error = true }, { pointer_size = 8 } }) do
    r, s = native_fixture(options);
    check(not r:load(), 'Native binding or copy failure prevents a usable geometry reader.');
    check(r:read(1920, 1080) == nil, 'Failed native reads never publish a rectangle.');
end
return { count = count };
