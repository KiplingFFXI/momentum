local player = require('core.player');
local defaults = require('ui.defaults');
local count = 0;
local function equal(actual, expected, why)
    count = count + 1;
    assert(actual == expected, why .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual));
end

local interface, menu, header = 0x30000, 0x40000, 0x50000;
local words, reads, scans, fault = {}, {}, 0, nil;
ashita.memory.find = function(_, _, pattern)
    scans = scans + 1;
    if pattern == '8B4424046A016A0050B9????????E8????????F6D81BC040C3' then return 0x20000; end
    if pattern == '8B480C85C974??8B510885D274??3B05' then return 0x20020; end
    return 0;
end;
ashita.memory.read_uint32 = function(address)
    reads[#reads + 1] = address;
    if address == fault then error('Menu memory unavailable'); end
    return words[address] or 0;
end;
words[0x2000A], words[0x20020] = interface, interface + 0x54;
words[interface + 0x54], words[menu + 4] = menu, header;
local function word(text)
    local value = 0;
    for i = 1, 4 do value = value + (text:byte(i) or 0) * 256 ^ (i - 1); end
    return value;
end
local function focus(name)
    words[interface + 0x54], words[menu + 4] = menu, header;
    words[header + 0x46], words[header + 0x4A] = word('menu'), word('    ');
    words[header + 0x4E], words[header + 0x52] = word(name:sub(1, 4)), word(name:sub(5, 8));
    reads = {};
end
player.load();
equal(scans, 4, 'The option reuses the four existing player searches');
local flags = { map = false, event = false, game_ui = false, chat_log = true };
local function check_focus(name, want_map, want_log)
    focus(name);
    local hidden, log = player.hidden(flags);
    equal(hidden == true, want_map, name .. ' has the expected map hide result');
    equal(log == true, want_log, name .. ' has the expected expanded-log hide result');
end
check_focus('fulllog ', false, true);
check_focus('fulllog\0', false, true);
for _, name in ipairs({ 'fulllogx', 'full', 'inline', 'chatctrl', 'playermo', 'mcr1pall', 'status', 'map0' }) do
    check_focus(name, false, false);
end
flags.map = true;
check_focus('map0', true, false);
equal(#reads, 3, 'The existing map check still uses only three focus reads');
check_focus('fulllog ', false, true);
equal(#reads, 6, 'Combined map/log detection shares one bounded focus/header read');
flags.map, flags.chat_log = false, false;
focus('fulllog ');
player.hidden(flags);
equal(#reads, 0, 'Disabled map and log choices do not read menu memory');
flags.chat_log = true;
focus('fulllog ');
words[header + 0x46] = word('fake');
equal(select(2, player.hidden(flags)) == true, false, 'An unrelated header cannot masquerade as chat');
focus('fulllog ');
words[header + 0x4A] = 0;
equal(select(2, player.hidden(flags)) == true, false, 'The complete native menu prefix is required');
for _, bad in ipairs({ 1, -1, 0xFFFFFFFF, 1.5, math.huge }) do
    focus('fulllog ');
    words[interface + 0x54] = bad;
    equal(select(2, player.hidden(flags)) == true, false, 'Invalid focused-menu pointer leaves the bar visible');
    equal(#reads, 1, 'Invalid focused-menu pointer is never followed');
    focus('fulllog ');
    words[menu + 4] = bad;
    equal(select(2, player.hidden(flags)) == true, false, 'Invalid menu-header pointer leaves the bar visible');
    equal(#reads, 2, 'Invalid menu-header pointer is never followed');
end
for _, address in ipairs({ interface + 0x54, menu + 4, header + 0x4E, header + 0x52 }) do
    focus('fulllog ');
    fault = address;
    local ok, hidden, log = pcall(player.hidden, flags);
    equal(ok, true, 'A failed optional menu read does not disable Momentum');
    equal(hidden == true or log == true, false, 'A failed optional menu read does not hide the bar');
end
fault = nil;
words[0x20020] = interface + 0x58;
player.load();
focus('fulllog ');
equal(select(2, player.hidden(flags)) == true, false, 'An unverified focus-slot layout is not read');
equal(#reads, 0, 'Missing verified detection adds no repeated reads');
words[0x2000A], words[0x20020] = 0, 0x54;
player.load();
focus('fulllog ');
equal(select(2, player.hidden(flags)) == true, false, 'A low focus slot is never treated as game memory');
equal(#reads, 0, 'A zero interface plus matching offset is never dereferenced');
equal(player.capabilities().chat_log, false, 'A low focus slot does not advertise support');
words[0x2000A] = interface;
words[0x20020] = interface + 0x54;
player.load();
equal(player.capabilities().chat_log, true, 'The verified menu pointer reports expanded-log support');

local utc = 1800000000;
player.utc = function() return utc + MOCK.now; end;
os.time = function() return utc + math.floor(MOCK.now); end;
local stats = AshitaCore:GetMemoryManager():GetPlayer();
stats.GetStatusIcons = function() return { [0] = 251, [1] = 249 }; end;
stats.GetStatusTimers = function()
    local ending = ((utc + 600 - 1009810800) * 60) % 4294967296;
    return { [0] = ending, [1] = ending };
end;
local settings = defaults.make();
settings.visibility.map, settings.visibility.event, settings.visibility.game_ui = false, false, false;
settings.tracking.window = 0;
MOCK.settings_file = settings;
MOCK.load_addon();
local app = MOMENTUM_TEST;
local function frame(shown, why, seconds)
    MOCK.imgui_calls = {};
    MOCK.frame(seconds or 0.25);
    equal(app.state.broken, false, why .. ': addon stays healthy');
    local bars = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' and call[2] == '##momentum_bar' then bars = bars + 1; end
    end
    equal(bars > 0, shown, why);
end
focus('fulllog ');
frame(true, 'The default leaves the bar visible with the expanded log');
app.settings().visibility.chat_log = true;
for _, docked in ipairs({ false, true }) do
    app.settings().bar.docked = docked;
    for _, mode in ipairs({ 'chat', 'keep', 'always' }) do
        app.settings().visibility.mode = mode;
        focus('fulllog ');
        frame(mode == 'always', 'Expanded-log choice follows ' .. mode .. ' in either placement');
        focus('inline');
        frame(true, 'Opening the ordinary chat input is separate from the log choice');
        focus('status');
        frame(true, 'Other game menus remain independent');
    end
end
app.settings().visibility.mode = 'keep';
focus('fulllog ');
app.settings().preview.show = true;
frame(false, 'Sample preview respects the expanded-log hide choice');
app.settings().preview.show = false;
MOCK.fire('command', { command = '/momentum' });
frame(false, 'The bar hides while settings remain open');
equal(app.settings().window.open, true, 'Expanded log does not close Momentum settings');
local config_drawn = false;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'Begin' and call[2] == 'Momentum##settings' then config_drawn = true; end
end
equal(config_drawn, true, 'Settings actually render while the bar is hidden');
MOCK.key_escape = true;
frame(false, 'Escape closes settings while the expanded log is open');
equal(app.settings().window.open, false, 'Escape remains available');
MOCK.key_escape = false;
local function award(amount, chain)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, MOCK.player.server_id);
    MOCK.put(bytes, 8, 4, MOCK.player.server_id);
    MOCK.put(bytes, 16, 4, amount);
    MOCK.put(bytes, 20, 4, chain);
    MOCK.put(bytes, 24, 2, 8);
    MOCK.fire('packet_in', MOCK.packet(0x02D, bytes));
    MOCK.player.exp = MOCK.player.exp + amount;
end
award(200, 2);
frame(false, 'Hidden bar still receives an EXP chain');
local before = app.view(MOCK.now);
award(100, 0);
frame(false, 'Hidden bar continues observing the game', 3);
local after = app.view(MOCK.now);
equal(after.session_exp, before.session_exp + 100, 'Session EXP is recorded while the log is open');
equal(after.elapsed > before.elapsed, true, 'The session clock keeps running');
equal(after.paused, false, 'Expanded log does not pause the session');
equal(after.chain_left < before.chain_left and after.chain_left > 0, true, 'EXP chain keeps counting down');
equal(after.food_seconds < before.food_seconds, true, 'Food timer keeps counting down');
equal(after.dedication_seconds < before.dedication_seconds, true, 'Dedication timer keeps counting down');
focus('');
frame(true, 'Closing the log immediately restores the bar');
focus('fulllog ');
app.settings().visibility.chat_log = false;
frame(true, 'Turning the option off restores the bar immediately');
equal(#MOCK.commands, 0, 'The feature sends no game commands');
return { count = count };
