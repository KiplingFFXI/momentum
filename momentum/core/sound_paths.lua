local ffi = require('ffi');
local paths = {};
local native_library;

function paths.library()
    if native_library ~= nil then return native_library or nil; end
    pcall(ffi.cdef, [[
        int __stdcall momentum_sound_multibyte_to_wide(uint32_t, uint32_t, const char*, int, uint16_t*, int) __asm__("MultiByteToWideChar");
        int __stdcall momentum_sound_wide_to_multibyte(uint32_t, uint32_t, const uint16_t*, int, char*, int, const char*, int*) __asm__("WideCharToMultiByte");
        uint32_t __stdcall momentum_sound_attributes_w(const uint16_t*) __asm__("GetFileAttributesW");
        uint32_t __stdcall momentum_sound_path_error(void) __asm__("GetLastError");
        int __stdcall momentum_sound_create_directory_w(const uint16_t*, void*) __asm__("CreateDirectoryW");
        int __stdcall momentum_copy_sound_file_w(const uint16_t*, const uint16_t*, int) __asm__("CopyFileW");
        int __stdcall momentum_sound_compare_names_w(const uint16_t*, int, const uint16_t*, int, int) __asm__("CompareStringOrdinal");
    ]]);
    local ok, library = pcall(ffi.load, 'kernel32');
    native_library = ok and library or false;
    return native_library or nil;
end

local function valid_utf8(value)
    local index = 1;
    while index <= #value do
        local first = value:byte(index);
        local length = first < 0x80 and 1 or first >= 0xC2 and first <= 0xDF and 2
            or first >= 0xE0 and first <= 0xEF and 3 or first >= 0xF0 and first <= 0xF4 and 4 or nil;
        if not length or index + length - 1 > #value then return false; end
        for offset = 1, length - 1 do
            local byte = value:byte(index + offset);
            if byte < 0x80 or byte > 0xBF then return false; end
        end
        local second = value:byte(index + 1);
        if length == 3 and (first == 0xE0 and second < 0xA0 or first == 0xED and second > 0x9F)
            or length == 4 and (first == 0xF0 and second < 0x90 or first == 0xF4 and second > 0x8F) then return false; end
        index = index + length;
    end
    return true;
end

function paths.text(library, value, capacity)
    local length = 0;
    while length < capacity and value[length] ~= 0 do length = length + 1; end
    if length == capacity then return nil; end
    if length == 0 then return ''; end
    local size = library.momentum_sound_wide_to_multibyte(65001, 0, value, length, nil, 0, nil, nil);
    if size <= 0 or size > capacity * 4 then return nil; end
    local output = ffi.new('char[?]', size);
    if library.momentum_sound_wide_to_multibyte(65001, 0, value, length, output, size, nil, nil) ~= size then return nil; end
    return ffi.string(output, size);
end

-- New filenames are UTF-8. Keep existing filenames saved in the Windows codepage usable.
function paths.utf8(value)
    if type(value) ~= 'string' or #value > 32000 or value:find('%z') then return nil; end
    if valid_utf8(value) then return value; end
    local library = paths.library();
    if not library then return nil; end
    local count = library.momentum_sound_multibyte_to_wide(0, 0, value, -1, nil, 0);
    if count <= 0 or count > 32767 then return nil; end
    local wide = ffi.new('uint16_t[?]', count);
    if library.momentum_sound_multibyte_to_wide(0, 0, value, -1, wide, count) ~= count then return nil; end
    return paths.text(library, wide, count);
end

function paths.wide(library, value)
    value = paths.utf8(value);
    if not value then return nil; end
    local count = library.momentum_sound_multibyte_to_wide(65001, 8, value, -1, nil, 0);
    if count <= 0 or count > 32767 then return nil; end
    local output = ffi.new('uint16_t[?]', count);
    if library.momentum_sound_multibyte_to_wide(65001, 8, value, -1, output, count) ~= count then return nil; end
    return output;
end

function paths.attributes(path)
    local library = paths.library();
    if not library then return nil; end
    local wide = paths.wide(library, path);
    if not wide then return nil; end
    local value = tonumber(library.momentum_sound_attributes_w(wide));
    if value == nil or value == 4294967295 or value == -1 then
        return nil, tonumber(library.momentum_sound_path_error());
    end
    return value;
end

function paths.exists(path)
    return paths.attributes(path) ~= nil;
end

function paths.same_name(left, right)
    if left == right then return true; end
    if not left:find('[\128-\255]') and not right:find('[\128-\255]') then return left:lower() == right:lower(); end
    local library = paths.library();
    if not library then return false; end
    local ok, result = pcall(function()
        local a, b = paths.wide(library, left), paths.wide(library, right);
        return a and b and library.momentum_sound_compare_names_w(a, -1, b, -1, 1);
    end);
    return ok and result == 2;
end

function paths.make_folder(path)
    local value = paths.attributes(path);
    if value then return value % 32 >= 16; end
    local parent = path:gsub('[\\/]+$', ''):match('^(.*)[\\/]');
    if not parent or parent == path or parent == '' or not paths.make_folder(parent) then return false; end
    local library = paths.library();
    local wide = library and paths.wide(library, path);
    if not wide then return false; end
    if library.momentum_sound_create_directory_w(wide, nil) ~= 0 then return true; end
    value = paths.attributes(path);
    return value ~= nil and value % 32 >= 16;
end

return paths;
