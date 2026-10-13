local history = require('ui.history');
local defaults = require('ui.defaults');
local dynamis = require('ui.dynamis_layout');
local modes = {};
modes.names = { auto = 'Automatic', exp = 'EXP', merits = 'Merits', dynamis = 'Dynamis' };

local function saved(display)
    return type(display) == 'table' and next(display) ~= nil;
end

function modes.select(settings, selected)
    if selected == 'lp' then selected = 'merits'; end
    if not modes.names[selected] then return false, 'Choose Automatic, EXP, Merits, or Dynamis.'; end
    local options = settings.modes;
    local previous = options.selected;
    if previous == selected then return true; end
    dynamis.switch(settings, false);
    if previous == 'exp' or previous == 'merits' then options[previous] = history.copy(settings.display); end
    if previous == 'auto' then
        options.previous_display = history.copy(settings.display);
        local normal = settings.display.preset == 'Merits' and 'merits' or 'exp';
        if not saved(options[normal]) then options[normal] = history.copy(settings.display); end
    end
    if selected == 'auto' then
        if saved(options.previous_display) then settings.display = history.copy(options.previous_display); end
        options.previous_display = {};
    elseif selected == 'dynamis' then
        dynamis.switch(settings, true);
    else
        if saved(options[selected]) then settings.display = history.copy(options[selected]);
        else
            settings.display = history.copy(settings.display);
            defaults.apply_starter(settings, selected == 'merits' and 'Merits' or 'Leveling');
        end
        settings.display.mode = selected == 'merits' and 'lp' or 'exp';
    end
    options.selected = selected;
    return true;
end

return modes;
