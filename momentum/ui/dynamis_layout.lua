local history = require('ui.history');
local layouts = {};

function layouts.switch(settings, active)
    local options = settings.dynamis;
    if options.layout_active == active then return false; end
    if active then
        options.previous_display = history.copy(settings.display);
        settings.display = history.copy(options.layout);
    else
        options.layout = history.copy(settings.display);
        if type(options.previous_display) == 'table' then settings.display = history.copy(options.previous_display); end
        options.previous_display = nil;
    end
    options.layout_active = active;
    return true;
end

function layouts.capture(result)
    local options = result.dynamis;
    if not options then return result; end
    if options.layout_active and type(options.previous_display) == 'table' then
        options.layout = result.display;
        result.display = options.previous_display;
    end
    options.previous_display, options.layout_active = nil, false;
    return result;
end

return layouts;
