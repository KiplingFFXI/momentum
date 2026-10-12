local imgui = require('imgui');
local fonts = {};
local faces = {};
local choices = { 'Ashita', 'Segoe UI', 'Arial', 'Tahoma', 'Verdana', 'Calibri', 'Consolas' };
local files = { ['Segoe UI'] = 'segoeui.ttf', Arial = 'arial.ttf', Tahoma = 'tahoma.ttf',
    Verdana = 'verdana.ttf', Calibri = 'calibri.ttf', Consolas = 'consola.ttf' };

function fonts.names() return choices; end

-- Font files are loaded before drawing starts. A menu choice only selects one.
function fonts.load()
    local folder = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\';
    for name, file in pairs(files) do
        local path = folder .. file;
        if (ashita.fs.exists(path)) then
            local ok, face = pcall(imgui.AddFontFromFileTTF, path, 18);
            if (ok) then faces[name] = face; end
        end
    end
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
