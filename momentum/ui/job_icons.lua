-- Each job uses its artifact head picture from the player's game client.
local ffi = require('ffi');

local icons = {};
local items = {
    12511, 12512, 13855, 13856, 12513, 12514, 12515, 12516,
    12517, 13857, 12518, 13868, 13869, 12519, 12520, 15265,
    15266, 15267, 16138, 16140, 27786, 27787,
};
local loaded, retained = {}, {};
local d3d8 = nil;

local function library()
    if d3d8 == nil then
        local ok, value = pcall(require, 'd3d8');
        d3d8 = ok and value or false;
    end
    return d3d8 or nil;
end

-- Load the Direct3D definitions before the first picture is needed.
function icons.prepare()
    return library() ~= nil;
end

local function read_picture(item)
    local lib = library();
    if lib == nil then return nil; end
    local resources = AshitaCore:GetResourceManager();
    local entry = resources and resources:GetItemById(item) or nil;
    local size = entry and tonumber(entry.ImageSize) or nil;
    if entry == nil or entry.Bitmap == nil or size == nil or size <= 0 then return nil; end
    local device = lib.get_device();
    if device == nil then return nil; end

    local out = ffi.new('IDirect3DTexture8*[1]');
    local result = ffi.C.D3DXCreateTextureFromFileInMemoryEx(device, entry.Bitmap, size,
        0xFFFFFFFF, 0xFFFFFFFF, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
        ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil, out);
    if result ~= ffi.C.S_OK or out[0] == nil then return nil; end
    local texture = ffi.cast('IDirect3DTexture8*', out[0]);
    retained[#retained + 1] = texture;
    return tonumber(ffi.cast('uint32_t', texture));
end

-- A missing picture stays missing until unload, so a steady frame never retries it.
function icons.texture(job)
    if type(job) ~= 'number' or job ~= math.floor(job) or items[job] == nil then return nil; end
    if loaded[job] == nil then
        local ok, texture = pcall(read_picture, items[job]);
        loaded[job] = ok and texture or false;
    end
    return loaded[job] or nil;
end

-- Call after drawing has stopped. Each retained texture is released once.
function icons.destroy()
    for _, texture in ipairs(retained) do
        pcall(function () texture:Release(); end);
    end
    loaded, retained, d3d8 = {}, {}, nil;
end

return icons;
