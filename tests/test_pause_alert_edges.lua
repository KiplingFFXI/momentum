local defaults = require('ui.defaults');
local history = require('ui.history');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function check(value, label) equal(not not value, true, label); end
local settings = defaults.make();
for _, event in pairs(settings.alerts.events) do event.visual, event.sound = false, false; end
for _, id in ipairs({ 'dedication_end', 'no_exp' }) do
    settings.alerts.events[id].visual, settings.alerts.events[id].cooldown = true, 0;
end
MOCK.settings_file = settings;
MOCK.player.buffs = { 249 };
MOCK.load_addon();
MOCK.fire('load');
local app = MOMENTUM_TEST;
local delivered = { dedication_end = 0, no_exp = 0 };
local take = app.notifications.take;
app.notifications.take = function(self, ...)
    local events = take(self, ...);
    for _, event in ipairs(events) do delivered[event.id] = (delivered[event.id] or 0) + 1; end
    return events;
end;
local function frame(seconds)
    MOCK.imgui_calls = {};
    MOCK.frame(seconds or 0);
    equal(app.state.broken, false, 'Entry remains healthy');
end
local function command(name)
    local event = { command = '/momentum ' .. name };
    MOCK.fire('command', event);
    equal(event.blocked, true, 'Actual ' .. name .. ' command is handled');
end
local function immediate_frame()
    local sampled = app.state.sampled;
    frame(0.01);
    equal(app.state.sampled, sampled, 'Alert is rendered before another player sample');
end
local function message(effect, id)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, MOCK.player.server_id);
    MOCK.put(bytes, 8, 4, MOCK.player.server_id);
    MOCK.put(bytes, 12, 4, effect);
    MOCK.put(bytes, 24, 2, id);
    MOCK.fire('packet_in', MOCK.packet(0x029, bytes));
end
local function new_dedication()
    MOCK.player.buffs = {};
    frame(0.25);
    MOCK.player.buffs = { 249 };
    frame(0.25);
    equal(app.view(MOCK.now).dedication, true, 'A fresh observed Dedication effect is active');
end
frame();
for _, quiet in ipairs({ true, false }) do
    local label = quiet and 'Pause muting on' or 'Pause muting off';
    app.settings().alerts.quiet_paused = quiet;
    command('resume');
    new_dedication();
    command('pause');
    frame(0.25);
    equal(app.notifications.before.paused, true, label .. ': fixture has sampled its paused state');
    local before = history.copy(app.notifications.before);
    local sampled, seen = app.notifications.sampled, app.notifications.dedication_seen;
    local queue, enabled, cooldowns = app.notifications.queue, app.notifications.enabled, app.notifications.last;
    command('resume');
    equal(app.view(MOCK.now).paused, false, label .. ': session resumes immediately');
    before.paused = false;
    check(history.equal(app.notifications.before, before), label .. ': only the cached pause choice changes');
    equal(app.notifications.sampled, sampled, label .. ': resuming does not refresh observation age');
    equal(app.notifications.dedication_seen, seen, label .. ': resuming does not rearm Dedication');
    equal(app.notifications.queue, queue, label .. ': resuming preserves queued alerts');
    equal(app.notifications.enabled, enabled, label .. ': resuming preserves armed settings');
    equal(app.notifications.last, cooldowns, label .. ': resuming preserves cooldowns');
    local losses, reasons = delivered.dedication_end, delivered.no_exp;
    message(249, 206);
    immediate_frame();
    equal(delivered.dedication_end, losses + 1, label .. ': loss immediately after resume is delivered');
    equal(app.view(MOCK.now).notice.text, 'Dedication ended.', label .. ': loss notice is visible');
    message(0, 37);
    immediate_frame();
    equal(delivered.no_exp, reasons + 1, label .. ': immediate server EXP reason also uses resumed state');

    new_dedication();
    losses = delivered.dedication_end;
    command('pause');
    message(249, 206);
    immediate_frame();
    equal(delivered.dedication_end, losses + (quiet and 0 or 1),
        label .. ': loss immediately after pause respects the selected muting');
    if quiet then equal(app.view(MOCK.now).notice, nil, label .. ': paused alert stays invisible'); end
    command('resume');
    immediate_frame();
    equal(delivered.dedication_end, losses + (quiet and 0 or 1), label .. ': resume does not replay an old loss');

    new_dedication();
    losses = delivered.dedication_end;
    message(249, 206);
    equal(#app.notifications.queue, 1, label .. ': a real loss waits for the next render');
    queue = app.notifications.queue;
    command('pause');
    equal(app.notifications.queue, queue, label .. ': pausing preserves the existing queue');
    equal(#queue, 1, label .. ': pausing does not consume queued alerts early');
    immediate_frame();
    equal(delivered.dedication_end, losses + (quiet and 0 or 1),
        label .. ': queued alert delivery obeys the current pause choice');
    command('resume');
    immediate_frame();
    equal(delivered.dedication_end, losses + (quiet and 0 or 1), label .. ': queue is delivered or muted only once');
end

new_dedication();
local sampled, losses = app.notifications.sampled, delivered.dedication_end;
MOCK.now = MOCK.now + 3;
command('pause');
command('resume');
equal(app.notifications.sampled, sampled, 'Pause and resume cannot make a stale observation current');
message(249, 206);
equal(#app.notifications.queue, 0, 'A loss without a recent observation is still rejected');
frame();
equal(delivered.dedication_end, losses, 'A stale loss is not delivered after the next sample');
equal(#MOCK.commands, 0, 'Session controls never send gameplay commands');
return { count = count };
