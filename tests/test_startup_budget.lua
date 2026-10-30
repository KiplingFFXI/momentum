local count = 0;
local function check(value, message)
    count = count + 1;
    assert(value, message);
end
local function equal(actual, expected, message)
    check(actual == expected, message .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end

local scans, reads = {}, 0;
local utc = 1800000000;
local clock_pattern = '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3';
ashita.memory.find = function(_, _, pattern)
    scans[#scans + 1] = 'player:' .. pattern;
    return pattern == clock_pattern and 0x100 or 0;
end;
ashita.memory.read_uint32 = function(address)
    if address == 0x100 then return 0x200; end
    if address == 0x200 then return 0x300; end
    if address == 0x30C then return utc + MOCK.now; end
    return 0;
end;
local memory = AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager = function() return memory; end;
memory.GetInventory = function()
    return { GetContainerItem = function()
        reads = reads + 1;
        return { Id = 65535, Count = 1000 };
    end };
end;

-- Exercise the real chat loader while leaving drawing on the normal chat fixture.
local drawing_chat = require('core.chat');
package.preload['core.chat'], package.loaded['core.chat'] = nil, nil;
local real_chat = require('core.chat');
local function bytes32(value)
    local bytes = {};
    for index = 1, 4 do
        bytes[index] = string.char(value % 256);
        value = math.floor(value / 256);
    end
    return table.concat(bytes);
end
local reader = real_chat.new({
    range = function() return 0x100000, 0x100000; end,
    find = function(pattern, usage)
        scans[#scans + 1] = 'chat:' .. pattern .. ':' .. tostring(usage);
        if usage == 1 then return 0; end
        return pattern == '85C0753B8B15' and 0x110000 or 0x120000;
    end,
    read = function(address, size)
        if size ~= 4 then return nil; end
        if address == 0x110006 then return bytes32(0x130000); end
        if address == 0x120001 then return bytes32(0x140000); end
    end,
});
drawing_chat.load = function(pause) return reader:load(pause); end;
package.loaded['core.chat'] = drawing_chat;

local function packet(id, bytes)
    MOCK.fire('packet_in', MOCK.packet(id, bytes));
end
local function money(amount)
    local bytes = MOCK.bytes(20);
    MOCK.put(bytes, 4, 4, amount);
    packet(0x01E, bytes);
end
local function timer(seconds)
    local bytes = MOCK.bytes(40);
    MOCK.put(bytes, 4, 4, 1);
    MOCK.put(bytes, 8, 4, utc - 1009810800);
    MOCK.put(bytes, 12, 4, seconds);
    MOCK.put(bytes, 36, 1, 1);
    packet(0x075, bytes);
end
local function scene(seconds, backbuffer)
    MOCK.now = MOCK.now + (seconds or 1 / 60);
    local before = #scans;
    MOCK.fire('d3d_beginscene', backbuffer ~= false);
    check(#scans - before <= 1, 'Each back-buffer callback performs at most one client search');
end

MOCK.settings_file = require('ui.defaults').make();
MOCK.settings_file.appearance_version, MOCK.settings_file.style.palette_version = 2, 1;
MOCK.settings_file.style.font = 'Ashita';
local dedication_alert = MOCK.settings_file.alerts.events.dedication_end;
dedication_alert.visual, dedication_alert.sound, dedication_alert.file = true, true, 'FF VII Save.mp3';
MOCK.player.buffs = { 249 };
MOCK.login_status, MOCK.player.zone = 0, 144;
dofile(ADDON_DIR .. '/momentum.lua');
MOCK.fire('load');
local zone = MOCK.bytes(60);
MOCK.put(zone, 4, 4, MOCK.player.server_id);
MOCK.put(zone, 48, 2, MOCK.player.zone);
MOCK.put(zone, 56, 4, utc);
packet(0x00A, zone);
local area = require('data.event_rules').areas[MOCK.player.zone];
local fight;
for _, value in pairs(area.battles) do if value.kind == 'bcnm' then fight = value; break; end end
local entry = MOCK.bytes(28);
MOCK.put(entry, 4, 4, MOCK.player.server_id);
MOCK.put(entry, 12, 4, fight.index);
MOCK.put(entry, 26, 2, area.messages.ENTERING_THE_BATTLEFIELD_FOR);
packet(0x02A, entry);
timer(900);
equal(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_events, 2, 'Entry and native timer wait for the runtime');
MOCK.login_status = 2;
scene(0);
scene(2.75);
check(MOMENTUM_TEST == nil and #scans == 0, 'The full character settling period still applies');
scene(0.25);
local app = MOMENTUM_TEST;
check(app and app.state.startup_seeded and not app.state.resources_ready, 'Tracking starts before client searches finish');
local view = app.view(MOCK.now);
check(view.events.active and view.events.kind == 'bcnm', 'Buffered entry context is applied before live packets');
equal(view.events.remaining, 897, 'The buffered countdown keeps its original receipt time');
equal(view.gil.current, 1000, 'The starting gil balance is established before new packets');
equal(view.gil.gained, 0, 'The initial balance is not income');
check(reads > 0, 'The initial balance came from current inventory state');

local pending_scans = #scans;
scene(1 / 60, false);
equal(#scans, pending_scans, 'Off-screen scenes do not advance startup');
MOCK.zoning = true;
scene();
equal(#scans, pending_scans, 'Zoning pauses startup work');
MOCK.zoning, MOCK.login_status = false, 0;
scene();
equal(#scans, pending_scans, 'Logged-out state pauses startup work');
MOCK.login_status = 2;
MOCK.fire('command', { command = '/momentum hide' });
equal(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands, 1, 'Commands wait for the bar resources');
money(1200); money(1100);
MOCK.player.exp = MOCK.player.exp + 100;
packet(0x061, MOCK.bytes(96));
local award = MOCK.bytes(28);
MOCK.put(award, 4, 4, MOCK.player.server_id);
MOCK.put(award, 8, 4, MOCK.player.server_id);
MOCK.put(award, 16, 4, 100);
MOCK.put(award, 24, 2, 8);
packet(0x02D, award);
equal(app.tracker().session_exp, 100, 'A reward during client searches is counted once');
timer(600);
local deadline = app.events.core.current.ends_at;
view = app.view(MOCK.now);
equal(view.events.remaining, 600, 'A newer native timer replaces the buffered timer during startup');
equal(view.gil.gained, 200, 'Gil gained while loading is counted from the starting baseline');
equal(view.gil.spent, 100, 'Gil spent while loading is counted from the latest packet');
equal(view.gil.net, 100, 'Gil packets retain their order while loading');
equal(view.gil.current, 1100, 'Current gil follows the newest packet while loading');
local sounds, sound = 0, require('core.sound');
sound.use = function() return true; end;
sound.play = function() sounds = sounds + 1; return true; end;
local ended = MOCK.bytes(28);
MOCK.put(ended, 4, 4, MOCK.player.server_id);
MOCK.put(ended, 8, 4, MOCK.player.server_id);
MOCK.put(ended, 12, 4, 249);
MOCK.put(ended, 24, 2, 206);
MOCK.player.buffs = {};
packet(0x029, ended);
equal(sounds, 0, 'A Dedication loss queues playback for the normal render callback');
local ui_calls = #MOCK.imgui_calls;
MOCK.fire('d3d_present');
check(not app.state.hidden and not app.state.resources_ready, 'Rendering does not flush commands or finish client searches');
equal(#MOCK.imgui_calls, ui_calls, 'No HUD or settings drawing runs before resources are ready');
equal(sounds, 1, 'Dedication sounds still play while client searches are pending');
equal(app.view(MOCK.now).notice.id, 'dedication_end', 'The Dedication notice is retained while startup finishes');

local frames = 0;
while not app.state.resources_ready and frames < 20 do
    scene();
    frames = frames + 1;
end
check(app.state.resources_ready and not app.state.startup_failed, 'Startup finishes across normal frames');
equal(#scans, 8, 'All four player and four chat searches still run');
equal(scans[1], 'player:' .. clock_pattern, 'The current server clock is available before the session baseline');
equal(app.events.core.current.ends_at, deadline, 'Finishing startup does not replay the older event timer');
view = app.view(MOCK.now);
check(view.events.remaining < 600 and view.events.remaining > 599, 'The native countdown keeps running during client searches');
equal(app.tracker().session_exp, 100, 'The final sample does not double count the reward');
equal(view.gil.gained, 200, 'The final sample does not double count gil income');
equal(view.gil.spent, 100, 'The final sample does not double count spending');
equal(view.gil.current, 1100, 'Stale inventory memory cannot replace the newest gil packet');
MOCK.fire('d3d_present');
check(app.state.hidden and not app.state.broken, 'The queued command runs when resources are ready');
equal(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands, 0, 'Queued commands drain once');
local complete_scans = #scans;
for _ = 1, 120 do scene(); MOCK.fire('d3d_present'); end
equal(#scans, complete_scans, 'Steady frames never repeat client searches');
equal(app.events.core.current.ends_at, deadline, 'Steady frames retain the same event deadline');
equal(sounds, 1, 'Finishing startup does not replay the Dedication alert');
equal(#MOCK.commands, 0, 'Startup observation sends no gameplay commands');
MOCK.fire('unload');
for _ = 1, 12 do scene(); end
equal(#scans, complete_scans, 'Unloaded callbacks never restart client searches');
return { count = count };
