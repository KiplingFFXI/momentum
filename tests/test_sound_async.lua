local worker = require('core.sound_worker');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local function new()
    return worker.new('C:\\Momentum\\bin\\momentum-sound.exe');
end

local source, traces = new(), {};
source:set_trace(function(event, fields) traces[#traces + 1] = { event = event, fields = fields }; end);
MOCK.sound_launch_pending = true;
eq(source:start('C:\\first.mp3', 500), true, 'Pending launch is accepted without waiting');
eq(source:owned(), true, 'A pending launch remains owned');
eq(MOCK.sound_workers, nil, 'A slow process launch does not need to finish before Play returns');
source:update(0);
local polls = MOCK.sound_launch_polls;
for index = 1, 20 do source:update(index / 100); end
eq(MOCK.sound_launch_polls, polls, 'Pending launch checks stay below four times a second');
source:start('C:\\second.wav', 300);
source:start('C:\\latest.wav', 200);
eq(#MOCK.sound_requests, 1, 'Repeated Play keeps one pending native launch');
eq(source.pending.path, 'C:\\latest.wav', 'Only the latest replacement is kept');
eq(MOCK.sound_waits, nil, 'No game-thread wait is used');
source:update(0.3);
eq(MOCK.sound_workers, nil, 'Cancellation waits through polling rather than blocking the game');
MOCK.sound_launch_pending = nil;
source:update(0.6);
eq(#MOCK.sound_workers, 1, 'Only the replacement launches after cancellation completes');
eq(MOCK.sound_workers[1].path, 'C:\\latest.wav', 'Cancelled launch never plays');
eq(MOCK.sound_requests[1].released, true, 'Cancelled request is released');
source:update(0.9);
eq(source.request, nil, 'Ready process handles transfer once');
eq(MOCK.sound_workers[1].thread.closed, true, 'Transferred thread handle closes');
local timing;
for _, row in ipairs(traces) do
    if row.event == 'worker.launch.completed' and row.fields.ok then timing = row.fields.duration_ms; end
end
eq(timing, 6, 'Native launch timing reaches diagnostics separately from submission');
eq(source:stop(), true, 'Transferred process can be cancelled');

MOCK.sound_launch_pending = true;
source:start('C:\\cancelled.mp3', 500);
eq(source:stop(), false, 'Close can defer cleanup of a running native launch');
eq(source.pending, nil, 'Close removes pending replacement playback');
MOCK.sound_launch_pending = nil;
source:update(1.3);
eq(source:owned(), false, 'Deferred close releases the cancelled request');
eq(#MOCK.sound_workers, 1, 'Closed request cannot play later');

MOCK.sound_launch_pending = true;
source:start('C:\\unloaded.mp3', 500);
local request = source.request;
eq(source:shutdown(), true, 'Unload releases a pending launch without waiting');
eq(request.released, true, 'Unload cancels native request ownership');
eq(source:owned(), false, 'Unload leaves no Lua-owned request');
MOCK.sound_launch_pending = nil;
source:update(2);
eq(#MOCK.sound_workers, 1, 'Unloaded playback cannot restart');

local failed = new();
MOCK.sound_create_error = true;
eq(failed:start('C:\\bad.mp3', 500), true, 'Process creation errors arrive asynchronously');
local result = failed:update(0);
eq(result.launched, false, 'Failed creation is reported on completion');
eq(type(result.problem), 'string', 'Failed creation has a useful sound error');
eq(failed:owned(), false, 'Failed creation releases its request');
MOCK.sound_create_error = nil;
MOCK.sound_submit_error = true;
eq(failed:start('C:\\bad.mp3', 500), false, 'Submission failure is contained');
eq(failed:owned(), false, 'Failed submission owns no request');
MOCK.sound_submit_error = nil;

local completed = new();
completed:start('C:\\ready.mp3', 500);
local child = MOCK.sound_workers[2];
MOCK.sound_terminate_error = true;
eq(completed:stop(), false, 'Cancel after completion retains a process that cannot be terminated');
eq(completed.request, nil, 'Completed native request transfers even after cancellation');
eq(completed.process, child.process, 'Lua retains ownership for a cleanup retry');
eq(child.process.closed, nil, 'A running child handle is not discarded');
MOCK.sound_terminate_error = nil;
completed:update(3);
eq(completed:owned(), false, 'A later cleanup retry succeeds');
eq(child.process.closed, true, 'Recovered cancellation closes the child handle');
eq(MOCK.sound_waits, nil, 'All launch and cancellation paths remain nonblocking');
return { count = count };
