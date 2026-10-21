local history = require('ui.history');
local layouts = {};
layouts.names = { assault = 'Assault', limbus = 'Limbus', bcnm = 'BCNM', ksnm = 'KSNM', enm = 'ENM' };

function layouts.store(settings)
    local options = settings.events;
    if options and layouts.names[options.active_kind] then
        options.layouts[options.active_kind] = history.copy(settings.display);
    end
end

function layouts.switch(settings, kind)
    local options = settings.events;
    kind = layouts.names[kind] and kind or nil;
    if options.active_kind == kind then return false; end
    layouts.store(settings);
    if options.active_kind then
        if type(options.previous_display) == 'table' then settings.display = history.copy(options.previous_display); end
        options.previous_display = nil;
    end
    options.active_kind = kind;
    if kind then
        options.previous_display = history.copy(settings.display);
        settings.display = history.copy(options.layouts[kind]);
    end
    return true;
end

function layouts.capture(settings)
    local options = settings.events;
    if not options then return settings; end
    layouts.store(settings);
    if options.active_kind and type(options.previous_display) == 'table' then settings.display = options.previous_display; end
    options.active_kind, options.previous_display = nil, nil;
    return settings;
end

return layouts;
