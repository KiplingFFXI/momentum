local count = 0;
local function check(value, message)
    count = count + 1;
    assert(value, message);
end
local function scene(seconds, backbuffer)
    MOCK.now = MOCK.now + (seconds or 0.25);
    MOCK.fire('d3d_beginscene', backbuffer ~= false);
end
MOCK.login_status = 0;
dofile(ADDON_DIR .. '/momentum.lua');
MOCK.fire('load');
check(MOMENTUM_TEST == nil, 'Launcher preload waits for the character');
MOCK.fire('command', { command = '/momentum hide' });
MOCK.fire('command', { command = '/momentum free' });
MOCK.fire('command', { command = '/momentum' });
MOCK.login_status = 2;
MOCK.zoning = true;
scene(5);
check(MOMENTUM_TEST == nil, 'Time at the title screen or while zoning does not satisfy the delay');
MOCK.zoning = false;
scene(0.25, false);
check(MOMENTUM_TEST == nil, 'Off-screen scenes cannot start the addon');
scene(0.25);
scene(2.75);
check(MOMENTUM_TEST == nil, 'The full three-second in-game delay is required');
MOCK.zoning = true;
scene(0.25);
MOCK.zoning = false;
scene(0.25);
scene(2.75);
check(MOMENTUM_TEST == nil, 'Zoning restarts the settling period');
scene(0.25);
local app = MOMENTUM_TEST;
check(app ~= nil and app.state.resources_ready, 'The addon starts after three stable in-game seconds');
check(app.tracker():view(MOCK.now, app.settings()).valid, 'Player values are seeded after startup');
check(MOMENTUM_BOOTSTRAP_TEST.inspect().queued_commands == 3, 'Queued commands wait for the UI frame');
MOCK.fire('d3d_present');
check(app.state.hidden, 'Queued hide command is applied');
check(not app.settings().bar.docked and not app.settings().bar.locked, 'Queued free placement keeps its normal behavior');
check(app.settings().window.open, 'Queued settings command opens the menu');
local settings = app.settings();
for _ = 1, 20 do scene(); end
MOCK.fire('load');
check(MOMENTUM_TEST == app and app.settings() == settings, 'Repeated events do not reload the runtime or settings');
local bytes = MOCK.bytes(28);
MOCK.put(bytes, 4, 4, MOCK.player.server_id);
MOCK.put(bytes, 8, 4, MOCK.player.server_id);
MOCK.put(bytes, 16, 4, 123);
MOCK.put(bytes, 24, 2, 8);
MOCK.fire('packet_in', MOCK.packet(0x02D, bytes));
check(app.tracker().session_exp == 123, 'The first EXP award after startup is counted once');
MOCK.fire('d3d_present');
check(not app.state.broken, 'Rendering works after the delayed handoff');
MOCK.fire('unload');
return { count = count };
