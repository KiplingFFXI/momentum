local defaults = require('ui.defaults');
local profiles = require('ui.profiles');
local modes = require('ui.modes');
local readouts = require('ui.readouts');
local imgui = require('imgui');
local window = require('ui.settings_window');
local count = 0;
local function eq(actual, expected, title)
    count = count + 1;
    assert(actual == expected, title .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function banks(settings)
    return { settings.display, settings.modes.exp, settings.modes.merits, settings.modes.previous_display,
        settings.modes.legacy_auto_display, settings.dynamis.layout, settings.dynamis.previous_display,
        settings.events.layouts.assault, settings.events.layouts.limbus, settings.events.layouts.bcnm,
        settings.events.layouts.ksnm, settings.events.layouts.enm, settings.events.previous_display };
end
local settings = defaults.make();
eq(settings.display.alignment, 'left', 'New layouts still start left aligned');
settings.modes.legacy_auto_display = defaults.copy(settings.display);
settings.dynamis.previous_display = defaults.copy(settings.display);
settings.events.previous_display = defaults.copy(settings.display);
for _, alignment in ipairs({ 'left', 'center', 'right', 'invalid' }) do
    for _, display in ipairs(banks(settings)) do display.alignment = alignment; end
    defaults.tidy(settings);
    for index, display in ipairs(banks(settings)) do
        eq(display.alignment, alignment == 'invalid' and 'left' or alignment, 'Saved bank ' .. index .. ' normalizes ' .. alignment);
    end
end
for _, mode in ipairs({ 'exp', 'merits', 'dynamis', 'assault', 'limbus', 'bcnm', 'ksnm', 'enm' }) do
    modes.select(settings, mode);
    settings.display.alignment = 'center';
    settings.display.labels.rate = mode .. ' rate';
    settings.display.groups_enabled = true;
    settings.display.groups.progress = 'right';
end
local copied = defaults.make();
profiles.apply(copied, profiles.capture(settings));
defaults.tidy(copied);
for _, mode in ipairs({ 'exp', 'merits', 'dynamis', 'assault', 'limbus', 'bcnm', 'ksnm', 'enm' }) do
    modes.select(copied, mode);
    eq(copied.display.alignment, 'center', mode .. ' restores centered alignment from its saved bank');
    eq(copied.display.labels.rate, mode .. ' rate', mode .. ' retains custom labels');
    eq(copied.display.groups_enabled, true, mode .. ' retains independent alignment groups');
    eq(copied.display.groups.progress, 'right', mode .. ' retains the selected group');
end
modes.select(copied, 'exp');
modes.select(copied, 'auto');
eq(copied.display.alignment, 'center', 'Automatic shares the centered EXP layout');

settings = defaults.make();
settings.window.open = true;
settings.window.sections['Display/Position and size'] = true;
local combos, disabled, disabled_stack = {}, false, {};
local next_open;
imgui.SetNextItemOpen = function(value) next_open = value; end;
imgui.CollapsingHeader = function() return next_open; end;
imgui.BeginDisabled = function(value) disabled_stack[#disabled_stack + 1] = disabled; disabled = disabled or value == true; end;
imgui.EndDisabled = function() disabled = table.remove(disabled_stack); end;
imgui.BeginCombo = function(label)
    if label == '##Readout alignment' then combos[#combos + 1] = { disabled = disabled }; return true; end
    return false;
end;
imgui.BeginPopup = function(label) return label == '##readout_catalog'; end;
local select = imgui.Selectable;
imgui.Selectable = function(label, ...)
    if disabled then return false; end
    return select(label, ...);
end;
local function draw(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end
    window.draw(settings, readouts.sample('Leveling'), {});
end
local original_order = table.concat(settings.display.order, ',');
local original_width = settings.bar.width;
draw('Center');
eq(settings.display.alignment, 'center', 'Readout alignment menu offers Center');
eq(table.concat(settings.display.order, ','), original_order, 'Centering keeps the chosen readout order');
eq(settings.bar.chat_alignment, 'left', 'Readout centering does not change chat anchoring');
eq(settings.bar.width, original_width, 'Readout centering does not change the saved width');
draw('Right');
eq(settings.display.alignment, 'right', 'Right alignment remains available');
draw('Left');
eq(settings.display.alignment, 'left', 'Left alignment remains available');
settings.display.groups_enabled = true;
draw('Center');
eq(combos[#combos].disabled, true, 'Global alignment is disabled while independent groups apply');
eq(settings.display.alignment, 'left', 'Disabled global control does not override groups');
settings.display.groups_enabled = false;
MOCK.clicks.Center = nil;
draw('Mog Satchel slots##add_satchel_slots');
eq(settings.display.enabled.satchel_slots, true, 'Storage catalog adds Mog Satchel slots');
eq(settings.display.enabled.inventory_slots, false, 'Adding Mog Satchel does not enable Inventory');
local found = false;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'TextDisabled' and call[2] == 'Storage' then found = true; end
end
eq(found, true, 'Optional bag readouts have a Storage catalog heading');
return { count = count };
