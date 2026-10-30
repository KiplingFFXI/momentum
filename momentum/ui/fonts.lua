local imgui = require('imgui');
local fonts = {};
local faces = {};
local attempted = {};
local choices = { 'Ashita', 'Segoe UI', 'Arial', 'Tahoma', 'Verdana', 'Calibri', 'Consolas' };
local files = { ['Segoe UI'] = 'segoeui.ttf', Arial = 'arial.ttf', Tahoma = 'tahoma.ttf',
    Verdana = 'verdana.ttf', Calibri = 'calibri.ttf', Consolas = 'consola.ttf' };

function fonts.names() return choices; end

-- Load the selected font between frames. Ashita needs no extra font.
function fonts.load(name)
    local file = files[name];
    if file == nil or attempted[name] then return true; end
    local io = imgui.GetIO();
    if io and io.Fonts and io.Fonts.Locked == true then return false; end
    attempted[name] = true;
    local folder = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\';
    local path = folder .. file;
    if (ashita.fs.exists(path)) then
        local ok, face = pcall(imgui.AddFontFromFileTTF, path, 18);
        if (ok) then faces[name] = face; end
    end
    return true;
end

function fonts.push(name, size)
    imgui.PushFont(faces[name] or imgui.GetFont(), size or 18);
    return true;
end

function fonts.pop(pushed)
    if (pushed) then imgui.PopFont(); end
end

function fonts.failed(name) return files[name] ~= nil and faces[name] == nil; end

return fonts;
