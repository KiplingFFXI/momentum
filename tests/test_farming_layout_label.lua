local defaults = require('ui.defaults');
local modes = require('ui.modes');
local window = require('ui.settings_window');
local readouts = require('ui.readouts');
local settings = defaults.make();
defaults.tidy(settings);
settings.farming.auto_layout = true;
assert(modes.automatic(settings, 'exp'));
assert(settings.modes.selected == 'auto' and settings.modes.active == 'farming');
settings.window.open, settings.window.tab = true, 'Display';
window.draw(settings, readouts.sample('Farming'), {});
local farming, exp = false, false;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'TextUnformatted' then
        farming = farming or call[2] == 'Editing Farming layout';
        exp = exp or call[2] == 'Editing EXP layout';
    end
end
assert(farming and not exp, 'Automatic names the Farming bank that receives the edits');
return { count = 1 };
