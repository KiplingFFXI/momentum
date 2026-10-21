local history = require('ui.history');
local defaults = require('ui.defaults');
local dynamis = require('ui.dynamis_layout');
local events = require('ui.event_layout');
local modes = {};
modes.names = { auto = 'Automatic', exp = 'EXP', merits = 'Merits', dynamis = 'Dynamis',
    assault = 'Assault', limbus = 'Limbus', bcnm = 'BCNM', ksnm = 'KSNM', enm = 'ENM' };

local function saved(display)
    return type(display) == 'table' and next(display) ~= nil;
end

local function normal_display(settings)
    if settings.events and settings.events.active_kind and saved(settings.events.previous_display) then return settings.events.previous_display; end
    if settings.dynamis.layout_active and saved(settings.dynamis.previous_display) then return settings.dynamis.previous_display; end
    return settings.display;
end

local function set_normal(settings, display)
    if settings.events and settings.events.active_kind then settings.events.previous_display = display;
    elseif settings.dynamis.layout_active then settings.dynamis.previous_display = display;
    else settings.display = display; end
end

local function preferences(settings, display)
    local options = settings.modes;
    if options.selected == 'auto' then
        options.auto.mode, options.auto.auto_layout = display.mode, display.auto_layout;
    end
end

local function apply_preferences(settings, display)
    local options = settings.modes;
    display.auto_layout = options.auto.auto_layout;
    display.mode = options.selected == 'exp' and 'exp' or options.selected == 'merits' and 'lp' or options.auto.mode;
end

function modes.prepare(settings)
    local options = settings.modes;
    if options.layout_version == 1 then return false; end
    local display = normal_display(settings);
    local automatic = saved(options.previous_display) and options.previous_display or display;
    options.auto = { mode = automatic.mode or 'auto', auto_layout = automatic.auto_layout == true };
    local active = options.selected == 'exp' and 'exp' or options.selected == 'merits' and 'merits'
        or display.preset == 'Merits' and 'merits' or 'exp';
    if options.selected == 'exp' or options.selected == 'merits' or not saved(options[active]) then
        options[active] = history.copy(display);
    elseif not history.equal(display, options[active]) then
        -- Keep the old Automatic layout if it differs from the saved mode.
        if not saved(options.previous_display) then options.previous_display = history.copy(display);
        elseif not saved(options.legacy_auto_display) then options.legacy_auto_display = history.copy(display); end
        display = history.copy(options[active]);
        set_normal(settings, display);
    end
    options.active, options.layout_version = active, 1;
    apply_preferences(settings, display);
    return true;
end

function modes.store(settings)
    modes.prepare(settings);
    events.store(settings);
    local display = normal_display(settings);
    preferences(settings, display);
    settings.modes[settings.modes.active] = history.copy(display);
end

local function activate(settings, active, force, stored)
    local options = settings.modes;
    if not force and options.active == active then return false; end
    if not stored then modes.store(settings); end
    local display;
    if saved(options[active]) then display = history.copy(options[active]);
    else
        display = history.copy(normal_display(settings));
        defaults.apply_starter({ display = display }, active == 'merits' and 'Merits' or 'Leveling');
    end
    apply_preferences(settings, display);
    options.active = active;
    set_normal(settings, display);
    return true;
end

function modes.automatic(settings, earning_mode)
    modes.prepare(settings);
    if settings.modes.selected ~= 'auto' or settings.dynamis.layout_active or settings.events and settings.events.active_kind then return false; end
    preferences(settings, settings.display);
    if not settings.display.auto_layout or not earning_mode then return false; end
    return activate(settings, earning_mode == 'lp' and 'merits' or 'exp');
end

function modes.select(settings, selected)
    if selected == 'lp' then selected = 'merits'; end
    if not modes.names[selected] then return false, 'Choose Automatic, EXP, Merits, Dynamis, Assault, Limbus, BCNM, KSNM, or ENM.'; end
    modes.prepare(settings);
    local options = settings.modes;
    local previous = options.selected;
    if previous == selected then return true; end
    modes.store(settings);
    if settings.events then events.switch(settings, nil); end
    dynamis.switch(settings, false);
    options.selected = selected;
    local active = selected == 'exp' or selected == 'merits';
    activate(settings, active and selected or options.active, true, true);
    if selected == 'dynamis' then dynamis.switch(settings, true); end
    if events.names[selected] then events.switch(settings, selected); end
    return true;
end

function modes.event(settings, kind)
    if not settings.events then return false; end
    local selected = settings.modes.selected;
    if selected ~= 'auto' then return events.switch(settings, events.names[selected] and selected or nil); end
    local options = settings.events;
    local active = options.enabled and options.auto_layout and events.names[kind] and kind or nil;
    if active then dynamis.switch(settings, false); end
    return events.switch(settings, active);
end

function modes.capture(settings)
    modes.store(settings);
    events.capture(settings);
    return dynamis.capture(settings);
end

return modes;
