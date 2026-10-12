local defaults = require('ui.defaults');
local readouts = require('ui.readouts');
local history = require('ui.history');
local player = require('core.player');
local hud = require('ui.hud');
local count = 0;
local function equal(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end
local function check(value, label) equal(not not value, true, label); end
local function close(actual, expected, label)
    count = count + 1;
    assert(type(actual) == 'number' and math.abs(actual - expected) < 0.000001,
        label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end

local utc, dedication_deadline, ring_deadline = 1800000000, 150, 150;
local original_time = os.time;
os.time = function() return utc + math.floor(MOCK.now); end;
player.utc = function() return utc + MOCK.now; end;
local memory = AshitaCore:GetMemoryManager();
local stats = memory:GetPlayer();
stats.GetStatusIcons = function() return { [0] = MOCK.now < dedication_deadline and 249 or 255 }; end;
stats.GetStatusTimers = function()
    return { [0] = ((utc + dedication_deadline - 1009810800) * 60) % 4294967296 };
end;
local ring_item;
local function set_ring()
    local bytes = MOCK.bytes(24);
    MOCK.put(bytes, 0, 1, 1);
    MOCK.put(bytes, 1, 1, 6);
    MOCK.put(bytes, 3, 1, 0x90);
    MOCK.put(bytes, 4, 4, utc + ring_deadline - 1009810800);
    ring_item = { Id = 15762, Count = 1, Flags = 0, Extra = MOCK.packet(0, bytes).data };
end
set_ring();
local inventory = {
    GetContainerCountMax = function(_, container) return container == 0 and 1 or 0; end,
    GetContainerItem = function(_, container, slot) return container == 0 and slot == 1 and ring_item or nil; end,
};
local get_memory = AshitaCore.GetMemoryManager;
AshitaCore.GetMemoryManager = function(...)
    local manager = get_memory(...);
    manager.GetInventory = function() return inventory; end;
    return manager;
end;
local settings = defaults.make();
settings.window.open, settings.window.tab = true, 'Session';
settings.bar.docked, settings.bar.auto_width = false, false;
settings.bar.x, settings.bar.y, settings.bar.width, settings.bar.height = 20, 700, 1400, 24;
settings.display.order = { 'rate', 'eta', 'dedication', 'dedication_budget', 'ring' };
for id in pairs(settings.display.enabled) do settings.display.enabled[id] = false; end
for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true; end
settings.tracking.window = 0;
for _, event in pairs(settings.alerts.events) do event.visual, event.sound = false, false; end
for _, id in ipairs({ 'dedication_end', 'ring_ready' }) do
    settings.alerts.events[id].visual, settings.alerts.events[id].cooldown = true, 0;
end
settings.alerts.quiet_paused = false;
MOCK.settings_file = settings;
local drawn;
local draw = hud.draw;
hud.draw = function(current, view, context)
    local changed = draw(current, view, context);
    drawn = { view = history.copy(view), parts = {} };
    for _, part in ipairs(readouts.cached(current, view)) do drawn.parts[part.id] = part.value; end
    return changed;
end;
dofile(ADDON_DIR .. '/momentum.lua');
MOCK.fire('load');
local app = MOMENTUM_TEST;
local delivered = { dedication_end = 0, ring_ready = 0 };
local take = app.notifications.take;
app.notifications.take = function(self, ...)
    local events = take(self, ...);
    for _, event in ipairs(events) do delivered[event.id] = (delivered[event.id] or 0) + 1; end
    return events;
end;
local function frame(seconds)
    MOCK.imgui_calls = {};
    MOCK.frame(seconds or 0);
    equal(app.state.broken, false, 'Full entry render remains healthy');
end
local function command(text) MOCK.fire('command', { command = '/momentum ' .. text }); frame(); end
local function button_reset() MOCK.clicks['Reset session'] = true; frame(); frame(); end
local function loss_packet()
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, MOCK.player.server_id);
    MOCK.put(bytes, 8, 4, MOCK.player.server_id);
    MOCK.put(bytes, 12, 4, 249);
    MOCK.put(bytes, 24, 2, 206);
    return MOCK.packet(0x029, bytes);
end
local loss_sent, last_loss = false, nil;
local function advance(seconds)
    for _ = 1, seconds do
        MOCK.now = MOCK.now + 1;
        if not loss_sent and MOCK.now >= dedication_deadline then
            last_loss, loss_sent = loss_packet(), true;
            MOCK.fire('packet_in', last_loss);
        end
        MOCK.imgui_calls = {};
        MOCK.frame(0);
    end
end
local function timers(label)
    local view = app.view(MOCK.now);
    equal(view.dedication, true, label .. ': Dedication stays active');
    close(view.dedication_seconds + MOCK.now, dedication_deadline, label .. ': Dedication expiry stays fixed');
    equal(drawn.parts.dedication, 'Dedication ' .. readouts.format_time(dedication_deadline - MOCK.now),
        label .. ': cached Dedication timer follows the same deadline');
    equal(view.rings.available, true, label .. ': owned ring remains available');
    equal(#view.rings.entries, 1, label .. ': one real inventory ring is found');
    local ring = view.rings.entries[1];
    equal(ring.id, 15762, label .. ': inventory identity stays');
    equal(ring.charges, 6, label .. ': charges stay');
    equal(ring.ready, false, label .. ': recast does not finish early');
    close(ring.recast + MOCK.now, ring_deadline, label .. ': inventory recast expiry stays fixed');
    check(drawn.parts.ring:find(readouts.format_time(ring_deadline - MOCK.now), 1, true),
        label .. ': cached ring timer follows the same deadline');
end
local function cleared(label)
    local view = app.view(MOCK.now);
    equal(view.session_exp, 0, label .. ': session EXP clears');
    equal(view.net_exp, 0, label .. ': net EXP clears');
    equal(view.rate, nil, label .. ': EXP/HR clears');
    equal(view.eta, nil, label .. ': Next clears');
    equal(drawn.parts.rate, '--', label .. ': cached EXP/HR clears');
    equal(drawn.parts.eta, '--', label .. ': cached Next clears');
end
local function expired(label)
    local view = app.view(MOCK.now);
    equal(view.dedication, false, label .. ': expired Dedication stays inactive');
    equal(view.dedication_seconds, nil, label .. ': expired Dedication has no restarted timer');
    equal(drawn.parts.dedication, 'No Dedication', label .. ': effect loss reaches the bar');
    equal(view.rings.entries[1].recast, 0, label .. ': finished recast stays at zero');
    equal(view.rings.entries[1].ready, true, label .. ': ring is ready');
    check(drawn.parts.ring:find('recast ready', 1, true), label .. ': ready ring reaches the bar');
end

frame();
timers('Initial client timers');
local reward = MOCK.bytes(28);
MOCK.put(reward, 4, 4, MOCK.player.server_id);
MOCK.put(reward, 8, 4, MOCK.player.server_id);
MOCK.put(reward, 16, 4, 200);
MOCK.put(reward, 24, 2, 8);
MOCK.fire('packet_in', MOCK.packet(0x02D, reward));
MOCK.player.exp = MOCK.player.exp + 200;
app.sample(MOCK.now);
advance(61);
frame();
check(drawn.view.rate > 0 and drawn.view.eta > 0, 'Real EXP awards establish EXP/HR and Next before reset');
timers('Before reset');

local message = table.concat({ 'MOM1', MOCK.player.server_id, MOCK.player.zone, MOCK.player.main_job,
    50, 50, 1, os.time(), 0, 0, 15, 1, 700, 50, dedication_deadline - MOCK.now, 1 }, '|');
local status = MOCK.bytes(23 + #message + 1);
MOCK.put(status, 4, 1, 29);
MOCK.put(status, 6, 2, MOCK.player.zone);
for i = 1, #'Momentum' do status[7 + i] = ('Momentum'):byte(i); end
for i = 1, #message do status[22 + i] = message:byte(i); end
local report = MOCK.packet(0x017, status);
MOCK.fire('packet_in', report);
equal(report.blocked, true, 'Fresh optional Dedication status is accepted');
frame();
equal(app.view(MOCK.now).dedication_pool, 700, 'Fresh report supplies the bonus EXP left');
button_reset();
cleared('Button reset');
timers('Button reset');
equal(app.view(MOCK.now).dedication_pool, 700, 'Reset keeps fresh server Dedication data');
command('reset');
cleared('Repeated command reset');
timers('Repeated command reset');
command('pause');
advance(3);
frame();
equal(app.view(MOCK.now).paused, true, 'Pause command pauses session accounting');
timers('Paused session');
command('reset');
cleared('Paused reset');
timers('Paused reset');
equal(app.view(MOCK.now).dedication_pool, 700, 'Paused reset retains the still-fresh server report');
command('resume');
advance(1);
frame();
equal(app.view(MOCK.now).paused, false, 'Resume command resumes session accounting');
timers('Resumed session');
button_reset();
timers('Repeated button reset');
advance(9);
frame();
equal(app.view(MOCK.now).dedication_pool, nil, 'Resets do not extend server report freshness');
timers('Client timers after the optional report becomes stale');

command('pause');
advance(dedication_deadline - MOCK.now - 1);
frame();
timers('One second before both effects finish');
button_reset();
cleared('Reset immediately before expiry');
timers('Reset immediately before expiry');
advance(1);
frame();
expired('Natural expiry while paused');
equal(delivered.dedication_end, 1, 'Confirmed Dedication loss still alerts while pause muting is off');
equal(delivered.ring_ready, 1, 'Actual ring ready transition still alerts while pause muting is off');
local notice = app.view(MOCK.now).notice;
check(notice and notice.text:find('Dedication ended.', 1, true), 'Dedication loss notice is shown');
check(notice and notice.text:find('recast finished.', 1, true), 'Ring ready notice is shown');
local notice_text, notice_expiry = notice.text, notice.expires;
command('reset');
expired('Reset after expiry');
equal(app.view(MOCK.now).notice.text, notice_text, 'Reset keeps the existing effect notices');
equal(app.view(MOCK.now).notice.expires, notice_expiry, 'Reset does not extend effect notices');
MOCK.fire('packet_in', last_loss);
frame();
equal(delivered.dedication_end, 1, 'Duplicate Dedication loss cannot alert again after reset');
equal(delivered.ring_ready, 1, 'Reset cannot repeat the ready ring alert');
advance(6);
command('reset');
expired('Later reset after expiry');
equal(app.view(MOCK.now).notice, nil, 'Expired notices are not resurrected by reset');

dedication_deadline, ring_deadline, loss_sent = MOCK.now + 8, MOCK.now + 8, false;
set_ring();
app.settings().alerts.quiet_paused = true;
advance(1);
frame();
timers('New effect and recast with pause muting on');
button_reset();
timers('Muted paused button reset');
advance(2);
command('reset');
timers('Muted paused command reset');
advance(dedication_deadline - MOCK.now);
frame();
expired('Muted expiry while paused');
equal(delivered.dedication_end, 1, 'Pause muting suppresses the new Dedication loss alert');
equal(delivered.ring_ready, 1, 'Pause muting suppresses the new ring ready alert');
equal(app.view(MOCK.now).notice, nil, 'Muted effect alerts show no notice');
command('reset');
command('resume');
advance(2);
frame();
expired('Resume after muted expiry');
equal(delivered.dedication_end, 1, 'Resume does not replay a muted Dedication loss');
equal(delivered.ring_ready, 1, 'Resume does not replay a muted ring ready alert');
equal(#MOCK.commands, 0, 'Session controls send no gameplay commands');
os.time = original_time;
return { count = count };
