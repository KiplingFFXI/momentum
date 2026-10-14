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

local utc, food_deadline = 1800000000, 600;
local original_time = os.time;
os.time = function() return utc + math.floor(MOCK.now); end;
player.utc = function() return utc + MOCK.now; end;
local stats = AshitaCore:GetMemoryManager():GetPlayer();
stats.GetStatusIcons = function() return { [0] = 251 }; end;
stats.GetStatusTimers = function() return { [0] = ((utc + food_deadline - 1009810800) * 60) % 4294967296 }; end;
local settings = defaults.make();
settings.window.open, settings.window.tab = true, 'Session';
settings.bar.docked, settings.bar.auto_width = false, false;
settings.bar.x, settings.bar.y, settings.bar.width, settings.bar.height = 20, 700, 1400, 24;
settings.display.order = { 'rate', 'eta', 'chain', 'chain_time', 'best_chain', 'food' };
for id in pairs(settings.display.enabled) do settings.display.enabled[id] = false; end
for _, id in ipairs(settings.display.order) do settings.display.enabled[id] = true; end
settings.tracking.window = 0;
settings.alerts.events.chain_soon.visual, settings.alerts.events.food_soon.visual = true, true;
settings.alerts.events.chain_soon.cooldown, settings.alerts.events.food_soon.cooldown = 0, 0;
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
MOCK.load_addon();
MOCK.fire('load');
local app = MOMENTUM_TEST;
local function frame(seconds)
    MOCK.imgui_calls = {};
    MOCK.frame(seconds or 0);
    equal(app.state.broken, false, 'Full entry render remains healthy');
end
local function advance(seconds)
    for _ = 1, seconds do MOCK.frame(1); end
end
local function command_reset() MOCK.fire('command', { command = '/momentum reset' }); frame(); end
local function button_reset() MOCK.clicks['Reset session'] = true; frame(); frame(); end
local function award(amount, chain)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, MOCK.player.server_id);
    MOCK.put(bytes, 8, 4, MOCK.player.server_id);
    MOCK.put(bytes, 16, 4, amount);
    MOCK.put(bytes, 20, 4, chain);
    MOCK.put(bytes, 24, 2, 8);
    MOCK.fire('packet_in', MOCK.packet(0x02D, bytes));
    MOCK.player.exp = MOCK.player.exp + amount;
    app.sample(MOCK.now);
    frame();
end
local function timers(chain, deadline, label, source)
    local view = app.view(MOCK.now);
    equal(view.chain, chain, label .. ': chain number stays');
    equal(view.chain_source, source or 'local', label .. ': chain source stays');
    close(view.chain_left, deadline - MOCK.now, label .. ': original chain deadline stays');
    equal(view.food, true, label .. ': food effect stays active');
    close(view.food_seconds, food_deadline - MOCK.now, label .. ': original food expiry stays');
    equal(drawn.parts.chain_time, (source == 'server' and '' or '~') .. readouts.format_time(deadline - MOCK.now),
        label .. ': cached chain timer follows the same deadline');
    check(drawn.parts.food:find(readouts.format_time(food_deadline - MOCK.now), 1, true), label .. ': food readout keeps counting');
end
local function cleared(label)
    local view = app.view(MOCK.now);
    equal(view.session_exp, 0, label .. ': session EXP clears');
    equal(view.net_exp, 0, label .. ': net EXP clears');
    equal(view.rate, nil, label .. ': EXP/HR clears');
    equal(view.eta, nil, label .. ': Next clears');
    equal(view.elapsed, 0, label .. ': elapsed time clears');
    equal(view.best_chain, 0, label .. ': session best chain clears');
    equal(drawn.parts.rate, '--', label .. ': cleared EXP/HR reaches cached readout');
    equal(drawn.parts.eta, '--', label .. ': cleared Next reaches cached readout');
end

frame();
award(200, 2);
local chain_started = app.view(MOCK.now).chain_started;
local chain_window = app.view(MOCK.now).chain_window;
local deadline = chain_started + chain_window;
equal(chain_window, 180, 'Real chain-2 packet starts Phoenix level-50 countdown');
advance(61);
frame();
check(drawn.view.rate > 0 and drawn.view.eta > 0, 'Real EXP rate and Next exist before reset');
equal(drawn.view.best_chain, 2, 'Original session recorded its best chain');
local old_id = app.services.session_current().id;
button_reset();
cleared('Button reset');
timers(2, deadline, 'Button reset');
equal(app.view(MOCK.now).chain_started, chain_started, 'Button reset does not change chain start time');
equal(app.view(MOCK.now).chain_window, chain_window, 'Button reset does not change Phoenix window');
local archived;
for _, row in ipairs(app.services.session_history()) do if row.id == old_id then archived = row; end end
equal(archived.best_chain, 2, 'Previous session keeps its best chain in history');
equal(archived.session_exp, 200, 'Previous session keeps its EXP in history');
button_reset();
cleared('Repeated reset');
timers(2, deadline, 'Repeated reset');

app.services.session_pause(true);
advance(3);
frame();
timers(2, deadline, 'Paused session before reset');
command_reset();
cleared('Paused command reset');
equal(app.view(MOCK.now).paused, true, 'Paused reset keeps the pause choice');
timers(2, deadline, 'Paused command reset');
app.services.session_pause(false);
frame(1);
timers(2, deadline, 'Resumed session before another reward');
award(150, 3);
equal(app.view(MOCK.now).chain, 3, 'Next qualifying packet advances the surviving chain');
equal(app.view(MOCK.now).best_chain, 3, 'New session best begins with the next qualifying packet');
equal(app.view(MOCK.now).session_exp, 150, 'Only the new qualifying reward enters the new session');
equal(app.view(MOCK.now).chain_window, 120, 'Advanced chain uses its own Phoenix window');
deadline = app.view(MOCK.now).chain_started + app.view(MOCK.now).chain_window;

app.settings().alerts.food_soon_seconds = food_deadline - deadline + 10;
advance(deadline - MOCK.now - 11);
frame();
close(app.view(MOCK.now).chain_left, 11, 'Fixture reaches one second before the warning');
command_reset();
cleared('Warning-edge reset');
timers(3, deadline, 'Warning-edge reset');
frame(1);
local notice = app.view(MOCK.now).notice;
check(notice and notice.text:find('EXP chain', 1, true), 'Reset preserves the live EXP-chain warning crossing');
check(notice and notice.text:find('Food effect', 1, true), 'Reset preserves the live food warning crossing');
close(app.view(MOCK.now).chain_left, 10, 'Warning does not extend the chain timer');
local warning_text = notice.text;
command_reset();
equal(app.view(MOCK.now).notice.text, warning_text, 'Reset keeps the existing food and chain warning visible');
timers(3, deadline, 'Visible-warning reset');
advance(11);
frame();
equal(app.view(MOCK.now).chain_left, nil, 'Chain estimate expires at its original deadline');
command_reset();
equal(app.view(MOCK.now).chain_left, nil, 'Reset cannot restart an expired chain estimate');
equal(drawn.parts.chain_time, '--', 'Expired timer stays empty on the bar after reset');
close(app.view(MOCK.now).food_seconds, food_deadline - MOCK.now, 'Food continues after chain expiry and reset');

local server_deadline = MOCK.now + 45;
local message = table.concat({ 'MOMC1', MOCK.player.server_id, MOCK.player.zone, MOCK.player.main_job,
    50, 50, 1, os.time(), 1, 1, 4, 100000, 145000 }, '|');
local bytes = MOCK.bytes(23 + #message + 1);
MOCK.put(bytes, 4, 1, 29);
MOCK.put(bytes, 6, 2, MOCK.player.zone);
for i = 1, #'Momentum' do bytes[7 + i] = ('Momentum'):byte(i); end
for i = 1, #message do bytes[22 + i] = message:byte(i); end
local report = MOCK.packet(0x017, bytes);
MOCK.fire('packet_in', report);
equal(report.blocked, true, 'Optional server chain report is accepted');
frame();
timers(4, server_deadline, 'Server chain before reset', 'server');
command_reset();
cleared('Server chain reset');
timers(4, server_deadline, 'Server chain reset', 'server');
frame(1);
timers(4, server_deadline, 'Server chain next second', 'server');

local isolated = require('core.tracker').new();
isolated:observe(history.copy(app.state.snapshot), MOCK.now);
isolated:award({ kind = 'exp', amount = 1, chain = 2, source = 'battle' }, MOCK.now);
check(isolated:view(MOCK.now, app.settings()).chain_left ~= nil, 'Default-reset fixture has a local chain');
isolated:reset(MOCK.now);
equal(isolated:view(MOCK.now, app.settings()).chain_left, nil, 'Default tracker reset still clears chain timing');
equal(isolated:view(MOCK.now, app.settings()).best_chain, 0, 'Default tracker reset clears session best');
local function paused_chain()
    local tracker = require('core.tracker').new();
    local snapshot = history.copy(app.state.snapshot);
    tracker:observe(snapshot, MOCK.now);
    tracker:award({ kind = 'exp', amount = 1, chain = 2, source = 'battle' }, MOCK.now);
    tracker:pause(MOCK.now, true);
    check(tracker:view(MOCK.now, app.settings()).chain_left ~= nil, 'Paused invalidation fixture starts with a live chain');
    return tracker, snapshot;
end
local moved, moved_snapshot = paused_chain();
moved_snapshot.zone = moved_snapshot.zone + 1;
moved:observe(moved_snapshot, MOCK.now + 1);
equal(moved:view(MOCK.now + 1, app.settings()).chain_left, nil,
    'A paused zone change detected from status still clears the chain without a zone packet');
local defeated, defeated_snapshot = paused_chain();
defeated_snapshot.dead = true;
defeated:observe(defeated_snapshot, MOCK.now + 1);
equal(defeated:view(MOCK.now + 1, app.settings()).chain_left, nil,
    'Death clears a chain even when pause has removed the progress baseline');
local paused_defeat, paused_snapshot = paused_chain();
paused_defeat:observe(paused_snapshot, MOCK.now + 1);
check(paused_defeat:view(MOCK.now + 1, app.settings()).chain_left ~= nil,
    'A healthy paused sample keeps the active chain');
paused_snapshot.dead = true;
paused_defeat:observe(paused_snapshot, MOCK.now + 2);
equal(paused_defeat:view(MOCK.now + 2, app.settings()).chain_left, nil,
    'Death after a healthy paused sample still clears the active chain');
local zone = MOCK.bytes(8);
MOCK.put(zone, 4, 4, MOCK.player.server_id);
MOCK.fire('packet_in', MOCK.packet(0x00A, zone));
equal(app.view(MOCK.now).chain_left, nil, 'Zoning still invalidates retained local and server chain timing');
equal(app.view(MOCK.now).food_seconds, nil, 'Zoning discards stale food timing until fresh status arrives');
MOCK.fire('packet_in', MOCK.packet(0x061, MOCK.bytes(96)));
frame(1);
equal(app.view(MOCK.now).chain_left, nil, 'Fresh post-zone status does not restore the old chain');
close(app.view(MOCK.now).food_seconds, food_deadline - MOCK.now, 'Fresh post-zone status rereads the current food timer');
equal(#MOCK.commands, 0, 'Timer preservation sends no gameplay commands');
os.time = original_time;
return { count = count };
