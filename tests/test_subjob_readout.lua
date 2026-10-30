local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local player = require('core.player');
local tracker = require('core.tracker');
local modes = require('ui.modes');
local profiles = require('ui.profiles');
local imgui = require('imgui');
local count = 0;
local function eq(actual, expected, title)
    count = count + 1;
    assert(actual == expected, title .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end

local stats = AshitaCore:GetMemoryManager():GetPlayer();
local get_subjob, get_sublevel = stats.GetSubJob, stats.GetSubJobLevel;
local job_reads, level_reads = 0, 0;
stats.GetSubJob = function (...) job_reads = job_reads + 1; return get_subjob(...); end;
stats.GetSubJobLevel = function (...) level_reads = level_reads + 1; return get_sublevel(...); end;
local settings, view = defaults.make(), readouts.sample('Leveling');
eq(settings.display.show_subjob, false, 'The existing compact job reading stays the default');
player.read();
player.read(false);
eq(job_reads, 0, 'A disabled option performs no subjob reads');
eq(level_reads, 0, 'A disabled option performs no subjob level reads');
local snapshot = player.read(true);
eq(snapshot.subjob, 13, 'The current support job comes from the client');
eq(snapshot.subjob_name, 'NIN', 'The support job uses its game abbreviation');
eq(snapshot.subjob_level, 25, 'The support job uses the current capped level');
eq(job_reads, 1, 'An enabled sample reads the support job once');
eq(level_reads, 1, 'An enabled sample reads the support level once');
MOCK.player.sub_job, MOCK.player.sub_level = 0, 0;
snapshot = player.read(true);
eq(snapshot.subjob, nil, 'No support job or a support job restriction does not invent a job');
eq(level_reads, 1, 'No support job skips the level getter');
MOCK.player.sub_job, MOCK.player.sub_level = 13, 0;
eq(player.read(true).subjob_level, nil, 'An unavailable support level stays unknown');
MOCK.player.sub_job = 23;
eq(player.read(true).subjob, nil, 'An unsupported support job stays unknown');
MOCK.player.sub_job, MOCK.player.sub_level = 13, 25;

settings.display.order = { 'job' };
settings.display.enabled.job = true;
view.subjob, view.subjob_name, view.subjob_level = 13, 'NIN', 30;
eq(readouts.cached(settings, view)[1].value, 'WAR 61', 'The off setting preserves the original job text');
settings.display.show_subjob = true;
eq(readouts.cached(settings, view)[1].value, 'WAR 61 / NIN 30', 'Turning on the option immediately refreshes the reading');
local before = readouts.cached(settings, view);
eq(readouts.cached(settings, view), before, 'Unchanged support data keeps the formatted cache');
view.subjob, view.subjob_name, view.subjob_level = 6, 'THF', 25;
eq(readouts.cached(settings, view)[1].value, 'WAR 61 / THF 25', 'Changing only support job refreshes the cached line');
view.effective_level, view.subjob_level = 40, 20;
eq(readouts.cached(settings, view)[1].value, 'WAR 61 (sync 40) / THF 20', 'Sync uses the current support level and keeps the main sync note');
view.subjob_level = 19;
eq(readouts.cached(settings, view)[1].value, 'WAR 61 (sync 40) / THF 19', 'A support level change refreshes the cached line');
settings.display.show_subjob = false;
eq(readouts.cached(settings, view)[1].value, 'WAR 61 (sync 40)', 'Turning the option off removes the suffix immediately');
settings.display.show_subjob = true;
view.subjob, view.subjob_name, view.subjob_level = nil, nil, nil;
eq(readouts.cached(settings, view)[1].value, 'WAR 61 (sync 40)', 'Missing support data leaves the main job usable');
view.valid = false;
eq(readouts.cached(settings, view)[1].value, '--', 'Unknown character state does not leak a previous support job');
view = readouts.sample('Leveling');
eq(readouts.cached(settings, view, true)[1].value, 'WAR 61 / NIN 30', 'The sample preview includes support job and level');

local state = tracker.new();
snapshot = player.read(true);
state:observe(snapshot, 1);
eq(state:view(1).subjob_level, 25, 'The tracker passes current support data to the view');
state:pause(2, true);
MOCK.player.sub_job, MOCK.player.sub_level = 6, 24;
state:observe(player.read(true), 3);
eq(state:view(3).subjob_name, 'THF', 'Support job changes continue while the EXP session is paused');
eq(state:view(3).subjob_level, 24, 'Support level changes continue while paused');
state:reset(4, true);
eq(state:view(4).subjob_level, 24, 'Session reset keeps current support data');

local icon_available = true;
package.loaded['ui.job_icons'] = { texture = function () return icon_available and 42 or nil; end };
package.loaded['ui.hud'] = nil;
local hud = require('ui.hud');
settings.bar.docked, settings.bar.auto_width = false, false;
settings.bar.x, settings.bar.y, settings.bar.width = 20, 100, 600;
local function drawn_job()
    MOCK.imgui_calls = {};
    hud.draw(settings, view, { now = 5 });
    local text, pictures = {}, 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddText' then text[#text + 1] = call[6]; end
        if call[1] == 'draw:AddImage' then pictures = pictures + 1; end
    end
    return table.concat(text), pictures;
end
local text, pictures = drawn_job();
eq(text, '(WAR) 61 / NIN 30', 'The main job icon keeps both job names and levels');
eq(pictures, 1, 'The optional support job does not add another icon');
icon_available = false;
text, pictures = drawn_job();
eq(text, 'WAR 61 / NIN 30', 'The fallback text includes the same support information');
eq(pictures, 0, 'The fallback does not require a job texture');

settings = defaults.make();
modes.select(settings, 'exp');
settings.display.show_subjob = true;
modes.select(settings, 'merits');
settings.display.show_subjob = false;
modes.select(settings, 'exp');
eq(settings.display.show_subjob, true, 'EXP keeps its enabled support option');
modes.select(settings, 'auto');
eq(settings.display.show_subjob, true, 'Automatic keeps the saved EXP choice');
local restored = defaults.make();
profiles.apply(restored, profiles.capture(settings));
defaults.tidy(restored);
eq(restored.display.show_subjob, true, 'Profiles preserve the enabled support option');
modes.select(restored, 'merits');
eq(restored.display.show_subjob, false, 'Profiles preserve a separate Merits choice');
restored.display.show_subjob = 'invalid';
defaults.tidy(restored);
eq(restored.display.show_subjob, false, 'Invalid saved values use the default');

settings = defaults.make();
settings.window.open = true;
settings.window.sections['Display/Selected readout'] = true;
local window = require('ui.settings_window');
MOCK.clicks['01  Job and level'] = true;
window.draw(settings, view, {});
MOCK.clicks['Show subjob and level'] = true;
window.draw(settings, view, {});
eq(settings.display.show_subjob, true, 'Selecting Job and level exposes the support-job checkbox');
return { count = count };
