local defaults = require('ui.defaults');
local notifications = require('core.notifications');
local count = 0;
local function eq(actual, expected, title)
    count = count + 1;
    assert(actual == expected, title .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local ids = { 'event_time', 'event_extension', 'event_objective', 'event_clear', 'event_failure', 'event_drop', 'event_ready' };
local settings, engine = defaults.make(), notifications.new();
for _, id in ipairs(ids) do
    settings.alerts.events[id].visual = true;
    eq(engine:event({ id = id, message = id }, 1, settings, false), true, id .. ' has a validated event route');
end
eq(#engine:take(1, false), #ids, 'Every supported event reaches the notification queue');
for _, id in ipairs({ 'level', 'dyna_time', 'event_unknown' }) do
    eq(engine:event({ id = id, message = 'Wrong route' }, 2, settings, false), false, id .. ' is rejected by the event route');
end
eq(engine:event({ id = 'event_time' }, 2, settings, false), false, 'A missing event message is rejected');
eq(engine:event({ id = 'event_time', message = 'Invalid time' }, 0 / 0, settings, false), false, 'Invalid event time is rejected');
eq(engine:dynamis({ id = 'event_time', message = 'Wrong route' }, 2, settings, false), false, 'Dynamis keeps its own event allowlist');
engine:preview('event_time', 'Test event warning', 2);
engine:take(2, true);
eq(engine:view(2).text, 'Test event warning', 'Quiet mode keeps an explicit visual preview');

local sound = require('core.sound');
local plays, selected = {}, nil;
sound.use = function(file) selected = file; return true; end;
sound.play = function(volume) plays[#plays + 1] = { file = selected, volume = volume }; return true; end;
require('ui.hud').draw = function() return false; end;
require('ui.settings_window').draw = function() return false; end;
MOCK.load_addon();
local app = MOMENTUM_TEST;
settings = app.settings();
local wanted = next(require('data.event_rules').items);
settings.events.wanted[wanted] = true;
local function queue(id)
    app.events.core:queue(id, 'Observed ' .. id, { item_id = wanted });
end
local function frame(seconds)
    MOCK.frame(seconds or 1.1);
    eq(app.state.broken, false, 'Event notification rendering stays healthy');
end
for index, id in ipairs(ids) do
    local row = settings.alerts.events[id];
    row.visual, row.sound, row.cooldown = true, true, 2;
    row.file, row.volume = 'FF VII Save.mp3', index * 10;
    queue(id);
    frame();
    local notice = app.view(MOCK.now).notice;
    eq(notice and notice.id, id, id .. ' reaches the actual render pipeline');
    eq(notice and notice.text, 'Observed ' .. id, id .. ' keeps its observed message');
    eq(#plays, index, id .. ' plays its enabled sound');
    eq(plays[index].file, row.file, id .. ' keeps its selected sound');
    eq(plays[index].volume, row.volume, id .. ' keeps its selected volume');
end
local previous = #plays;
queue('event_ready');
frame(0.25);
eq(#plays, previous, 'A repeated event respects its per-alert cooldown');
queue('event_ready');
frame(2.1);
eq(#plays, previous + 1, 'A fresh event can notify after its cooldown');

previous = #plays;
app.services.session_pause(true);
for _, id in ipairs(ids) do queue(id); end
frame();
eq(#plays, previous, 'Paused-session quiet mode suppresses every event sound');
eq(app.view(MOCK.now).notice, nil, 'Paused-session quiet mode clears automatic event notices');
app.services.session_pause(false);
frame();
eq(#plays, previous, 'Paused events are consumed without replay on resume');
MOCK.player.status = 4;
for _, id in ipairs(ids) do queue(id); end
frame();
eq(#plays, previous, 'Cutscene quiet mode suppresses every event sound');
eq(app.view(MOCK.now).notice, nil, 'Cutscene quiet mode suppresses automatic event notices');
MOCK.player.status = 0;
frame();
eq(#plays, previous, 'Cutscene events are not replayed afterward');

settings.alerts.quiet_paused = false;
settings.alerts.events.event_ready.cooldown = 0;
app.services.session_pause(true);
queue('event_ready');
frame();
eq(#plays, previous + 1, 'Players can keep event alerts enabled while their session is paused');
eq(app.view(MOCK.now).notice.id, 'event_ready', 'The allowed paused notice is shown');
settings.alerts.events.event_ready.visual, settings.alerts.events.event_ready.sound = false, false;
queue('event_ready');
frame(6);
eq(#plays, previous + 1, 'Disabled event alerts stay silent');
eq(app.view(MOCK.now).notice, nil, 'Disabled event alerts do not create a notice');
eq(#MOCK.commands, 0, 'Event alerts send no gameplay commands');
return { count = count };
