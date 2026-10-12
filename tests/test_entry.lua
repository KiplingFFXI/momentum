local count = 0;
local function check(value, message)
    count = count + 1;
    assert(value, message);
end
local function equal(actual, expected, message)
    check(actual == expected, (message or 'Unexpected value') .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local function command(text)
    local event = { command = text, blocked = false };
    MOCK.fire('command', event);
    return event;
end
local function battle(amount, message, actor, target, chain)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, actor or 1001);
    MOCK.put(bytes, 8, 4, target or 1001);
    MOCK.put(bytes, 16, 4, amount);
    MOCK.put(bytes, 20, 4, chain or 0);
    MOCK.put(bytes, 24, 2, message or 8);
    return MOCK.packet(0x02D, bytes);
end
local function pack_bits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local index = math.floor((offset + i) / 8);
        bytes[index] = bytes[index] + math.floor(value / 2 ^ i) % 2 * 2 ^ ((offset + i) % 8);
    end
end
local function item(amount, actor, target, message)
    local bytes = MOCK.bytes(40);
    pack_bits(bytes, 40, 32, actor or 1001);
    pack_bits(bytes, 72, 6, 1);
    pack_bits(bytes, 82, 4, 5);
    pack_bits(bytes, 150, 32, target or 1001);
    pack_bits(bytes, 182, 4, 1);
    pack_bits(bytes, 186 + 27, 17, amount);
    pack_bits(bytes, 186 + 44, 10, message or 105);
    return MOCK.packet(0x028, bytes);
end
local function food_end(actor, target, effect, message)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, actor or 1001);
    MOCK.put(bytes, 8, 4, target or 1001);
    MOCK.put(bytes, 12, 4, effect or 251);
    MOCK.put(bytes, 24, 2, message or 206);
    return MOCK.packet(0x029, bytes);
end
local function play_count()
    local total = 0;
    for _, value in ipairs(MOCK.mci or {}) do if value:match('^play ') then total = total + 1; end end
    return total;
end

local packets = require('core.packets');
for size = 0, 27 do
    local event = battle(200);
    event.data, event.size = event.data:sub(1, size), size;
    equal(#packets.awards(event, 1001), 0, 'Truncated reward');
end
for _, message in ipairs({ 8, 253, 371, 372 }) do
    local found = packets.awards(battle(200, message, 1001, 1001, 4), 1001);
    equal(#found, 1, 'Supported reward');
    equal(found[1].amount, 200, 'Reward amount');
    equal(found[1].chain, 4, 'Chain number');
    equal(found[1].kind, message < 300 and 'exp' or 'lp', 'Reward kind');
end
for _, flag in ipairs({ 'blocked', 'blocked_original', 'injected', 'is_injected' }) do
    local event = battle(200);
    event[flag] = true;
    equal(#packets.awards(event, 1001), 0, 'Ignore ' .. flag);
end
equal(#packets.awards(battle(200, 8, 1002), 1001), 0, 'Other actor');
equal(#packets.awards(battle(200, 8, 1001, 1002), 1001), 0, 'Other target');
equal(#packets.awards(battle(0), 1001), 0, 'Zero reward');
equal(#packets.awards(battle(200, 999), 1001), 0, 'Unrelated message');
equal(#packets.awards(battle(200), 0), 0, 'No player id');
equal(#packets.awards(item(750), 1001), 1, 'EXP item recognized');
equal(packets.awards(item(750), 1001)[1].source, 'item', 'EXP item source');
equal(#packets.awards(item(750, 1002), 1001), 0, 'Other player item');
equal(#packets.awards(item(750, 1001, 1002), 1001), 0, 'Item for another target');
equal(#packets.awards(item(750, 1001, 1001, 103), 1001), 0, 'Unrelated item result');
for size = 0, 34 do
    local event = item(750);
    event.data, event.size = event.data:sub(1, size), size;
    equal(#packets.awards(event, 1001), 0, 'Truncated item action');
end

dofile(ADDON_DIR .. '/momentum.lua');
MOCK.fire('load');
local app = MOMENTUM_TEST;
check(app ~= nil, 'Test seam exists only in test mode');
check(app.tracker():view(0, app.settings()).valid, 'Client values seeded on load');
equal(#MOCK.commands, 0, 'No game commands on load');
equal(play_count(), 0, 'No audio played on load');
equal(app.settings().alerts.food_enabled, false, 'Food alert is off by default');
equal(command('/something_else').blocked, false, 'Other commands pass through');
check(command('/momentum').blocked, 'Addon command consumed');
check(app.settings().window.open, 'Settings open');
command('/momentum');
equal(app.settings().window.open, false, 'Settings close');
command('/momentum lock'); check(app.settings().bar.locked, 'Lock');
command('/momentum unlock'); equal(app.settings().bar.locked, false, 'Unlock');
local hud = require('ui.hud');
local shown_rect = hud.bounds(app.settings(), app.tracker():view(0, app.settings()), { chat = MOCK.chat });
command('/momentum lock');
command('/momentum free'); equal(app.settings().bar.docked, false, 'Free placement');
equal(app.settings().bar.locked, false, 'Choosing free placement enables moving and resizing a previously locked bar');
equal(app.settings().bar.snap, false, 'Explicit free placement disables snapping');
equal(app.settings().bar.auto_width, false, 'Explicit free placement freezes its drawn width');
equal(app.settings().bar.x, shown_rect.x, 'Free command keeps the drawn horizontal position');
equal(app.settings().bar.y, shown_rect.y, 'Free command keeps the drawn vertical position');
equal(app.settings().bar.width, shown_rect.width, 'Free command keeps the drawn width');
equal(app.settings().bar.height, shown_rect.height, 'Free command keeps the drawn height');
command('/momentum lock');
equal(app.settings().bar.locked, true, 'Free placement can still be explicitly locked afterward');
command('/momentum free');
equal(app.settings().bar.locked, false, 'Selecting free placement again unlocks a free bar');
command('/momentum dock top'); check(app.settings().bar.docked, 'Top docking');
equal(app.settings().bar.anchor, 'top', 'Top command selects the upper chat edge');
equal(app.settings().bar.snap, true, 'Explicit anchoring enables snapping');
command('/momentum dock'); equal(app.settings().bar.anchor, 'top', 'Plain dock keeps the selected edge');
command('/momentum dock invalid'); equal(app.settings().bar.anchor, 'top', 'Invalid edge leaves placement unchanged');
command('/momentum dock bottom'); equal(app.settings().bar.anchor, 'bottom', 'Bottom command selects the lower chat edge');
app.settings().bar.start = 80;
command('/momentum free'); equal(app.settings().bar.start, 80, 'Free placement keeps the saved starting point');
command('/momentum dock'); equal(app.settings().bar.start, 80, 'Reattaching restores the starting point');
app.settings().bar.start = 0;
local saved_chat = MOCK.chat;
MOCK.chat = nil;
app.settings().bar.auto_width = true;
command('/momentum free');
check(not app.settings().bar.docked and not app.settings().bar.snap and not app.settings().bar.auto_width,
    'Free placement remains independent when chat bounds are unavailable');
MOCK.chat = saved_chat;
command('/momentum dock bottom');
command('/momentum hide'); check(app.state.hidden, 'Hide bar');
command('/momentum show'); equal(app.state.hidden, false, 'Show bar');
command('/momentum preview'); check(app.settings().preview.show, 'Preview on');
command('/momentum preview'); equal(app.settings().preview.show, false, 'Preview off');
command('/momentum pause'); check(app.tracker():view(0, app.settings()).paused, 'Pause session');
command('/momentum resume'); equal(app.tracker():view(0, app.settings()).paused, false, 'Resume session');

local copy = require('ui.history').copy;
local same = require('ui.history').equal;
local before = copy(app.settings());
local saves = MOCK.saved;
command('/momentum unknown');
check(same(before, app.settings()), 'Unknown command leaves settings unchanged');
equal(MOCK.saved, saves, 'Unknown command does not save');
command('/momentum order rate progress job');
equal(app.settings().display.order[1], 'rate', 'Explicit order first');
equal(app.settings().display.order[2], 'progress', 'Explicit order second');
equal(app.settings().display.order[3], 'job', 'Explicit order third');
equal(#app.settings().display.order, #require('ui.defaults').READOUTS, 'All readouts retained');
before = copy(app.settings());
command('/momentum order job job');
check(same(before, app.settings()), 'Duplicate order rejected');
command('/momentum order invented');
check(same(before, app.settings()), 'Unknown readout rejected');
command('/momentum undo');
equal(app.settings().display.order[1], 'job', 'Undo restores previous order');
command('/momentum divider /');
equal(app.settings().display.divider, '/', 'Custom divider');
command('/momentum divider " / "');
equal(app.settings().display.divider, ' / ', 'Quoted divider keeps spaces');
command('/momentum divider /');
command('/momentum mode lp'); equal(app.settings().display.mode, 'lp', 'Manual LP view');
command('/momentum mode exp'); equal(app.settings().display.mode, 'exp', 'Manual EXP view');
command('/momentum mode auto'); equal(app.settings().display.mode, 'auto', 'Automatic view');

MOCK.now = 1;
local event = battle(200, 253, 1001, 1001, 4);
MOCK.fire('packet_in', event);
MOCK.fire('packet_in', event);
equal(app.tracker():view(1, app.settings()).session_exp, 200, 'Same receive packet counted once');
MOCK.fire('packet_in', battle(200));
equal(app.tracker():view(1, app.settings()).session_exp, 400, 'Two identical rewards remain separate');
MOCK.player.exp = MOCK.player.exp + 400;
MOCK.now = 2;
app.sample(2);
MOCK.now = 3;
MOCK.fire('packet_in', item(750));
MOCK.player.exp = MOCK.player.exp + 750;
MOCK.now = 4;
app.sample(4);
equal(app.tracker():view(65, app.settings()).session_exp, 1150, 'Reward and item totals');
check(app.tracker():view(65, app.settings()).rate > 0, 'Rate starts after one minute');

command('/momentum profile save My Layout');
local names = app.services.profile_names();
equal(names[1], 'My Layout', 'Profile saved');
command('/momentum divider +');
command('/momentum profile load My Layout');
equal(app.settings().display.divider, '/', 'Profile restored');
app.services.job_link(1, 'My Layout');
equal(app.settings().job_links['1'], 'My Layout', 'Job profile linked');
check(app.services.shared(true), 'Shared appearance enabled');
check(app.settings().shared, 'Shared setting applied');
app.services.job_link(1, 'Another layout');
equal(app.state.own.job_links['1'], 'Another layout', 'Shared job link saved to own settings');
app.services.undo();
equal(app.settings().job_links['1'], 'My Layout', 'Undo restores active shared job link');
equal(app.state.own.job_links['1'], 'My Layout', 'Undo restores persisted own job link');
check(app.services.shared(false), 'Shared appearance disabled');
equal(app.settings().shared, false, 'Own appearance restored');
command('/momentum profile delete My Layout');
equal(#app.services.profile_names(), 0, 'Profile deleted');

command('/momentum reset');
equal(app.tracker():view(MOCK.now, app.settings()).session_exp, 0, 'Session cleared');
equal(app.settings().display.divider, '/', 'Session reset keeps display');
for _, tab in ipairs({ 'Display', 'Tracking', 'Appearance', 'Preview', 'Session', 'Profiles' }) do
    app.settings().window.open = true;
    app.settings().window.tab = tab;
    MOCK.frame(0.25);
    check(not app.state.broken, 'Settings draw: ' .. tab .. ' (' .. tostring(MOCK.printed[#MOCK.printed]) .. ')');
end
MOCK.settings.switch_character(require('ui.defaults').make());
equal(app.tracker():view(MOCK.now, app.settings()).session_exp, 0, 'Character change starts fresh session');
equal(app.settings().display.divider, require('ui.defaults').make().display.divider, 'Character appearance remains separate');
command('/momentum divider *');
app.settings().window.open = true;
app.settings().window.tab = 'Session';
app.settings().preview.show = true;
app.services.undo();
equal(app.settings().display.divider, require('ui.defaults').make().display.divider, 'Undo restores the last layout edit');
equal(app.settings().window.tab, 'Session', 'Undo keeps the current settings page');
check(app.settings().preview.show, 'Undo keeps preview mode');
app.settings().preview.show = false;

check(app.services.sound_play(), 'Explicit Play works while alert is off');
equal(play_count(), 1, 'Explicit Play produces one audio request');
MOCK.player.buffs = { 251 };
app.sample(MOCK.now);
app.settings().alerts.food_enabled = true;
app.sample(MOCK.now);
equal(play_count(), 1, 'Enabling the food alert stays quiet');
local ended = food_end();
MOCK.fire('packet_in', ended);
equal(play_count(), 1, 'Packet callback queues playback for the render callback');
MOCK.frame(0.05);
equal(play_count(), 2, 'Own food-end message plays once');
MOCK.fire('packet_in', ended);
MOCK.frame(0.05);
equal(play_count(), 2, 'Repeated food-end packet stays quiet');
MOCK.player.buffs = {};
app.sample(MOCK.now);
MOCK.player.buffs = { 251 };
app.sample(MOCK.now);
for _, packet in ipairs({ food_end(1002), food_end(1001, 1002), food_end(1001, 1001, 249), food_end(1001, 1001, 251, 204) }) do
    MOCK.fire('packet_in', packet);
end
local injected = food_end(); injected.injected = true; MOCK.fire('packet_in', injected);
MOCK.frame(0.05);
equal(play_count(), 2, 'Unrelated and injected status messages stay quiet');
app.settings().alerts.food_enabled = false;
MOCK.frame(0.25);
equal(require('core.sound').is_open(app.settings().alerts.food_sound), false, 'Disabling closes the audio handle');
MOCK.fire('packet_in', food_end());
MOCK.frame(0.05);
equal(play_count(), 2, 'Disabled food-end notification stays quiet');
app.settings().alerts.food_enabled = true;
app.sample(MOCK.now);
local zone = MOCK.bytes(12); MOCK.put(zone, 4, 4, 1001);
MOCK.fire('packet_in', MOCK.packet(0x00A, zone));
MOCK.fire('packet_in', food_end());
MOCK.frame(0.05);
equal(play_count(), 2, 'Zoning clears pending food state');
MOCK.fire('packet_in', MOCK.packet(0x061, MOCK.bytes(96)));
app.sample(MOCK.now);
equal(play_count(), 2, 'Returning from zoning stays quiet');
app.settings().alerts.food_enabled = false;
app.sample(MOCK.now);
MOCK.player.buffs = {};

local retained_defaults = require('ui.defaults').make();
local partial_character = { display = retained_defaults.display, bar = retained_defaults.bar };
MOCK.settings.current = partial_character;
for _, callback in pairs(MOCK.settings.callbacks) do callback(partial_character); end
check(app.settings() == partial_character, 'Settings library keeps its cached root table');
command('/momentum divider +');
command('/momentum free');
equal(retained_defaults.display.divider, require('ui.defaults').make().display.divider, 'Aliased default display is detached');
equal(retained_defaults.bar.docked, true, 'Aliased default placement is detached');
check(app.settings().display ~= retained_defaults.display, 'Nested display table belongs to active character');

local legacy = require('ui.defaults').make();
legacy.appearance_version = nil;
legacy.bar.width, legacy.bar.height, legacy.bar.x, legacy.bar.full_width = 900, 36, 100, true;
legacy.style.font, legacy.style.font_size, legacy.style.rounding = 'Ashita', 16, 0;
legacy.display.labels.remaining = 'To go';
local profile_folder = AshitaCore:GetInstallPath() .. '\\config\\addons\\momentum\\';
check(require('ui.profiles').new(profile_folder):save('Legacy layout', legacy), 'Legacy profile fixture saved');
check(app.services.load_profile('Legacy layout'), 'Legacy profile loads through entry');
equal(app.settings().bar.width, 640, 'Legacy profile width migrates');
equal(app.settings().bar.height, require('ui.defaults').make().bar.height, 'Legacy profile height migrates');
equal(app.settings().display.labels.remaining, 'TNL', 'Legacy profile label migrates');
equal(app.settings().appearance_version, 2, 'Legacy profile gets migration marker');
check(app.services.delete_profile('Legacy layout'), 'Legacy profile fixture removed');
check(require('core.file_store').write(profile_folder .. 'shared_layout.json', { enabled = true, layout = legacy }), 'Legacy shared fixture saved');
app.settings().window.open = false;
app.state.shared_at = -100;
MOCK.frame(3);
check(not app.state.broken, 'Legacy shared layout draws');
check(app.settings().shared, 'Legacy shared layout applied');
equal(app.settings().bar.width, 640, 'Legacy shared width migrates');
equal(app.settings().bar.height, require('ui.defaults').make().bar.height, 'Legacy shared height migrates');
equal(app.settings().display.labels.remaining, 'TNL', 'Legacy shared label migrates');
equal(app.settings().appearance_version, 2, 'Legacy shared gets migration marker');
check(app.services.shared(false), 'Legacy shared appearance disabled');
app.settings().alerts.food_enabled, app.settings().alerts.food_volume = true, 37;
app.settings().alerts.events.level.visual, app.settings().alerts.events.level.sound = true, true;
app.settings().alerts.events.level.file, app.settings().alerts.events.level.volume = 'FF VII Save.mp3', 42;
app.settings().alerts.events.level.cooldown = 180;
app.settings().alerts.quiet_events = false;
local alerts_before_tracking_reset = copy(app.settings().alerts);
app.settings().tracking.window, app.settings().tracking.rate_basis = 180, 'net';
app.settings().display.mode, app.settings().visibility.map = 'lp', false;
check(app.services.reset_section('tracking'), 'Tracking section resets');
check(same(app.settings().alerts, alerts_before_tracking_reset), 'Tracking reset preserves all settings now owned by Alerts');
equal(app.settings().tracking.window, require('ui.defaults').make().tracking.window, 'Tracking reset restores rate window');
equal(app.settings().tracking.rate_basis, 'earned', 'Tracking reset restores rate basis');
equal(app.settings().display.mode, 'auto', 'Tracking reset restores its progress mode');
equal(app.settings().visibility.map, true, 'Tracking reset restores its visibility choices');
check(app.services.reset_section('alerts'), 'Alerts section resets separately');
check(same(app.settings().alerts, require('ui.defaults').make().alerts), 'Alerts reset restores food and event settings');
MOCK.fire('unload');
equal(require('core.sound').is_open('FF VII Save.mp3'), false, 'Unload closes sound');
equal(#MOCK.commands, 0, 'No gameplay commands during integration test');

return count .. ' entry, packet, command and persistence checks';
