local count = 0;
local function check(value, label) count = count + 1; assert(value, label); end
MOCK.login_status = 0;
dofile(ADDON_DIR .. '/momentum.lua');
MOCK.fire('load');
local function packet(id, bytes) MOCK.fire('packet_in', MOCK.packet(id, bytes)); end
local utc, zone = os.time(), MOCK.bytes(60);
MOCK.put(zone, 4, 4, 1001); MOCK.put(zone, 48, 2, 144); MOCK.put(zone, 56, 4, utc);
packet(0x00A, zone);
local rules = require('data.event_rules');
local area, fight = rules.areas[144];
for _, value in pairs(area.battles) do if value.kind == 'bcnm' then fight = value; break; end end
local entry = MOCK.bytes(28);
MOCK.put(entry, 4, 4, 1001); MOCK.put(entry, 12, 4, fight.index);
MOCK.put(entry, 26, 2, area.messages.ENTERING_THE_BATTLEFIELD_FOR);
packet(0x02A, entry);
local timer = MOCK.bytes(40);
MOCK.put(timer, 4, 4, 1); MOCK.put(timer, 8, 4, utc - 1009810800);
MOCK.put(timer, 12, 4, 900); MOCK.put(timer, 36, 1, 1);
packet(0x075, timer);
check(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_events == 2, 'Relevant normal packets wait for runtime readiness');
check(not MOMENTUM_TEST, 'Capturing an entry does not start the runtime early');
local injected = MOCK.packet(0x075, timer);
injected.injected = true;
MOCK.fire('packet_in', injected);
check(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_events == 2, 'Injected packets cannot enter the startup queue');
for _ = 1, 63 do packet(0x075, timer); end
check(MOMENTUM_BOOTSTRAP_TEST.inspect().event_overflow, 'The startup queue is bounded');
check(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_events == 0, 'Overflow discards the incomplete sequence');
packet(0x00A, zone);
check(not MOMENTUM_BOOTSTRAP_TEST.inspect().event_overflow, 'A new zone starts a fresh sequence');
packet(0x02A, entry);
packet(0x075, timer);
MOCK.player.zone, MOCK.login_status = 144, 2;
MOCK.fire('d3d_beginscene', true);
MOCK.now = MOCK.now + 3;
MOCK.fire('d3d_beginscene', true);
local view = MOMENTUM_TEST.view(MOCK.now).events;
check(view.active and view.kind == 'bcnm', 'Entry identity survives the startup handoff');
check(view.remaining == 897, 'Native countdown accounts for time spent waiting to start');
check(view.time_estimated == false, 'Buffered native time keeps its known status');
check(#MOCK.commands == 0, 'Startup observation sends no gameplay commands');
MOCK.fire('unload');
return { count = count };
