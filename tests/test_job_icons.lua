local count = 0;
local function check(value, message)
    assert(value, message);
    count = count + 1;
end

local expected = {
    12511, 12512, 13855, 13856, 12513, 12514, 12515, 12516,
    12517, 13857, 12518, 13868, 13869, 12519, 12520, 15265,
    15266, 15267, 16138, 16140, 27786, 27787,
};

local function setup(options)
    options = options or {};
    local state = { reads = {}, creates = 0, released = 0, imports = 0 };
    package.loaded['ui.job_icons'], package.loaded.d3d8 = nil, nil;
    package.loaded.ffi = {
        new = function () return {}; end,
        cast = function (kind, value)
            return kind == 'uint32_t' and value.id or value;
        end,
        C = {
            S_OK = 0, D3DFMT_A8R8G8B8 = 21, D3DPOOL_MANAGED = 1, D3DX_DEFAULT = -1,
            D3DXCreateTextureFromFileInMemoryEx = function (...)
                local args = { ... };
                state.creates = state.creates + 1;
                state.arguments = args;
                if options.create_error then error('Decode failed'); end
                if options.create_failure then return -1; end
                if not options.null_texture then
                    args[15][0] = {
                        id = 1000 + state.creates,
                        Release = function ()
                            state.released = state.released + 1;
                            if options.release_error then error('Release failed'); end
                        end,
                    };
                end
                return 0;
            end,
        },
    };
    package.preload.d3d8 = function ()
        state.imports = state.imports + 1;
        if options.library_error then error('Unavailable'); end
        return { get_device = function () if not options.no_device then return 17; end end };
    end;
    AshitaCore.GetResourceManager = function ()
        return { GetItemById = function (_, id)
            state.reads[#state.reads + 1] = id;
            if options.resource_error then error('Missing resource'); end
            if options.missing then return nil; end
            if options.no_bitmap then return { ImageSize = 24 }; end
            return { Bitmap = 'picture', ImageSize = options.image_size or 24 };
        end };
    end;
    return require('ui.job_icons'), state;
end

local icons, state = setup();
check(state.imports == 0, 'Import stays lazy.');
check(icons.prepare(), 'Definitions can be prepared.');
check(state.imports == 1 and state.creates == 0, 'Preparing does not create pictures.');
for job, item in ipairs(expected) do
    local texture = icons.texture(job);
    check(texture == 1000 + job, 'Every job has a numeric draw texture.');
    check(state.reads[job] == item, 'Every job uses the expected artifact head.');
    check(icons.texture(job) == texture and state.creates == job, 'Repeated frames reuse the texture.');
end
check(state.arguments[1] == 17 and state.arguments[2] == 'picture' and state.arguments[3] == 24,
    'The resource bitmap and size reach Direct3D.');
check(state.arguments[6] == 1 and state.arguments[9] == 1 and state.arguments[12] == 0xFF000000,
    'Managed textures use one mip level and a black color key.');
for _, value in ipairs({ -1, 0, 23, 1.5, '1', math.huge }) do
    check(icons.texture(value) == nil, 'Invalid job ids have no icon.');
end
check(icons.texture(nil) == nil and icons.texture(0 / 0) == nil, 'Missing and invalid numeric jobs are safe.');
check(#state.reads == 22, 'Invalid jobs never query client resources.');
icons.destroy();
check(state.released == 22, 'Unload releases all retained textures.');
icons.destroy();
check(state.released == 22, 'Repeated unload does not release twice.');
check(icons.texture(1) == 1023, 'A fresh lifecycle can load again.');
icons.destroy();

for _, options in ipairs({
    { library_error = true }, { resource_error = true }, { missing = true },
    { no_bitmap = true }, { image_size = 0 }, { image_size = -1 },
    { image_size = 'bad' }, { no_device = true }, { create_error = true },
    { create_failure = true }, { null_texture = true },
}) do
    icons, state = setup(options);
    check(icons.texture(1) == nil, 'An unavailable picture falls back to text.');
    local reads, creates, imports = #state.reads, state.creates, state.imports;
    check(icons.texture(1) == nil and #state.reads == reads and state.creates == creates
        and state.imports == imports, 'Failures are cached between frames.');
    icons.destroy();
    check(state.released == 0, 'Failed loads have no texture to release.');
end

icons, state = setup({ release_error = true });
icons.texture(1);
icons.texture(2);
icons.destroy();
check(state.released == 2, 'One failed release does not skip the next texture.');
icons.destroy();
check(state.released == 2, 'Failed releases are not retried after unload.');

return { count = count };
