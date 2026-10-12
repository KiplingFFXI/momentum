local json = require('json');
local ffi = require('ffi');
local store = {};
local serial = 0;

if (ffi.os == 'Windows') then
    pcall(ffi.cdef, [[
        unsigned long __stdcall GetCurrentProcessId(void);
        int __stdcall MoveFileExA(const char*, const char*, unsigned long);
    ]]);
end

function store.read(path)
    local file = io.open(path, 'rb');
    if (file == nil) then
        if (ashita.fs.exists(path)) then return nil, 'The saved file could not be opened.'; end
        return {};
    end
    local text = file:read('*a');
    file:close();
    local ok, value = pcall(json.decode, text);
    if (not ok or type(value) ~= 'table') then return nil, 'The saved file could not be read. It was kept unchanged.'; end
    return value;
end

function store.write(path, value)
    local ok, text = pcall(json.encode, value);
    if (not ok) then return false, 'These changes could not be saved.'; end
    serial = serial + 1;
    local process = ffi.os == 'Windows' and tonumber(ffi.C.GetCurrentProcessId()) or 0;
    local temp = ('%s.%d.%d.tmp'):format(path, process, serial);
    local file = io.open(temp, 'wb');
    if (file == nil) then return false, 'The file could not be saved in the Momentum settings folder.'; end
    local wrote, result = pcall(file.write, file, text);
    local closed, closing = pcall(file.close, file);
    if (not wrote or not result or not closed or not closing) then
        os.remove(temp);
        return false, 'The changes could not be saved. Your previous file was kept.';
    end
    local moved;
    if (ffi.os == 'Windows') then
        ok, result = pcall(ffi.C.MoveFileExA, temp, path, 9);
        moved = ok and result ~= 0;
    else
        ok, result = pcall(os.rename, temp, path);
        moved = ok and result ~= nil;
    end
    if (not moved) then os.remove(temp); return false, 'The saved file could not be replaced.'; end
    return true;
end

return store;
