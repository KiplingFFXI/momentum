local count = 0;
local function check(value, message)
    count = count + 1;
    assert(value, message);
end
MOCK.login_status = 0;
local imports, reads, writes = 0, 0, 0;
local original_require, original_open = require, io.open;
require = function(name) imports = imports + 1; error('Unexpected early import: ' .. name); end;
io.open = function() writes = writes + 1; error('Unexpected early file access'); end;
local stats = AshitaCore:GetMemoryManager():GetPlayer();
local get_job = stats.GetMainJob;
stats.GetMainJob = function() reads = reads + 1; error('Character memory is not ready'); end;
dofile(ADDON_DIR .. '/momentum.lua');
MOCK.fire('load');
for _ = 1, 120 do
    MOCK.now = MOCK.now + 0.25;
    MOCK.fire('d3d_beginscene', true);
    MOCK.fire('d3d_present');
end
check(MOMENTUM_TEST == nil, 'The main addon has not loaded at the title screen');
check(imports == 0, 'Waiting imports no addon or shared Lua libraries');
check(reads == 0, 'Waiting does not read job memory');
check(writes == 0, 'Waiting never opens settings, logs or other files');
check(#(MOCK.mci or {}) == 0, 'Waiting never opens audio');
local other = { command = '/something_else', blocked = false };
MOCK.fire('command', other);
check(not other.blocked, 'Other addon commands are left alone');
local own = { command = '/momentum hide', blocked = false };
MOCK.fire('command', own);
check(own.blocked, 'A queued Momentum command is consumed');
check(imports == 0 and writes == 0, 'Queuing a command does not load the addon');
MOCK.fire('unload');
MOCK.login_status = 2;
stats.GetMainJob = get_job;
for _ = 1, 20 do
    MOCK.now = MOCK.now + 0.25;
    MOCK.fire('d3d_beginscene', true);
end
check(MOMENTUM_TEST == nil, 'Unloading cancels the pending start');
check(imports == 0 and writes == 0, 'A cancelled start remains inactive');
require, io.open = original_require, original_open;
return { count = count };
