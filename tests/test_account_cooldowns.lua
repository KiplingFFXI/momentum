local cooldowns = require('core.cooldowns');
local copy = require('ui.history').copy;
local count, reads, writes, disk = 0, 0, 0, {};
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local function new()
    return cooldowns.new('test/', {
        read = function() reads = reads + 1; return copy(disk); end,
        write = function(_, value) writes = writes + 1; disk = copy(value); return true; end,
    });
end
local now, utc = 100, 1800000000;
local tracker = new();
tracker:select(1001, { group = '' }, now);
eq(reads, 0, 'Unlinked characters do not read an account file');
eq(tracker:view(now, utc).dynamis, nil, 'Unknown account cooldown stays unknown');
tracker:observe('dynamis', utc + 1000, utc, now);
eq(writes, 0, 'Unlinked characters do not write an account file');
eq(tracker:view(now + 1, utc + 1).dynamis.remaining, 999, 'Own observed cooldown keeps running');
tracker:select(1001, { group = ' Main ', share_dynamis = true, share_limbus = true }, now + 1);
tracker:observe('dynamis', utc + 1000, utc, now + 1);
tracker:observe('limbus', utc + 300, utc, now + 1);
eq(disk.groups.main.dynamis.character_id, 1001, 'Recorded cooldown belongs to its observed character');
eq(disk.groups.main.limbus.ready_at, utc + 300, 'Limbus reminder persists independently');
local saved_reads, saved_writes = reads, writes;
for i = 1, 100 do
    tracker:select(1001, { group = 'Main' }, now + 1 + i / 100);
    tracker:observe('dynamis', utc + 1000, utc, now + 1 + i / 100);
    tracker:view(now + 1 + i / 100, utc);
end
eq(reads, saved_reads, 'Unchanged repeated frames do not reread the account file');
eq(writes, saved_writes, 'Unchanged observations do not rewrite timers');
disk.groups.main.dynamis = nil;
tracker:select(1001, { group = 'Main' }, now + 7);
tracker:observe('dynamis', utc + 1000, utc, now + 7);
eq(disk.groups.main.dynamis.ready_at, utc + 1000, 'A later refresh repairs an observation lost to a concurrent writer');
local alt = new();
alt:select(1002, { group = 'MAIN' }, now + 2);
eq(alt:view(now + 2, utc).dynamis.shared, true, 'Linked alt sees the other character\'s recorded cooldown');
eq(alt:view(now + 2, utc).limbus.reminder, true, 'Limbus sharing is labeled a reminder');
alt:observe('dynamis', utc + 100, utc, now + 2);
eq(alt:view(now + 2, utc).dynamis.ready_at, utc + 1000, 'Shorter alt observation cannot erase a later account deadline');
alt:select(1002, { group = 'MAIN', share_limbus = false }, now + 3);
eq(alt:view(now + 3, utc).limbus, nil, 'Limbus reminder can be disabled separately');
alt:select(1002, { group = 'Other' }, now + 3);
eq(alt:view(now + 3, utc).dynamis, nil, 'Account groups do not leak timers');
alt:select(1002, { group = 'Main' }, now + 4);
eq(alt:view(now + 4, utc + 2000).dynamis.remaining, 0, 'A known expired countdown reaches zero');
alt:detach();
eq(alt:view(now + 4, utc).dynamis, nil, 'Detaching clears the previous character view');
disk = { version = 9, groups = {} };
local broken = new();
broken:select(1003, { group = 'Main' }, now);
saved_writes = writes;
broken:observe('dynamis', utc + 10, utc, now);
eq(writes, saved_writes, 'Invalid saved data is not overwritten');
eq(disk.version, 9, 'The original invalid file is kept');
eq(type(broken:view(now, utc).error), 'string', 'A file problem is available to settings');
local failed_reads, failed_writes = 0, 0;
local unavailable = cooldowns.new('test/', {
    read = function() failed_reads = failed_reads + 1; return nil, 'Unavailable'; end,
    write = function() failed_writes = failed_writes + 1; return false, 'Unavailable'; end,
});
unavailable:select(1001, { group = 'Main' }, now);
for index = 1, 100 do
    unavailable:observe('dynamis', utc + 1000, utc, now + index / 100);
    unavailable:view(now + index / 100, utc);
end
eq(failed_reads, 1, 'An unreadable account file does not retry every sample');
eq(failed_writes, 0, 'An unreadable account file never gets overwritten');
unavailable:observe('dynamis', utc + 1000, utc, now + 6);
eq(failed_reads, 2, 'Unreadable account files retry after the normal interval');
failed_reads, failed_writes = 0, 0;
local readonly = cooldowns.new('test/', {
    read = function() failed_reads = failed_reads + 1; return {}; end,
    write = function() failed_writes = failed_writes + 1; return false, 'Read only'; end,
});
readonly:select(1001, { group = 'Main' }, now);
readonly:observe('limbus', utc + 300, utc, now);
for index = 1, 100 do readonly:observe('limbus', utc + 300, utc, now + index / 100); end
eq(failed_writes, 1, 'A read-only account file does not rewrite every sample');
readonly:observe('limbus', utc + 300, utc, now + 6);
eq(failed_writes, 2, 'Read-only account files retry after the normal interval');
local full = { version = 1, groups = {} };
for index = 1, 128 do full.groups[tostring(index)] = {}; end
local full_reads = 0;
local limited = cooldowns.new('test/', {
    read = function() full_reads = full_reads + 1; return copy(full); end,
    write = function() error('A full account file must stay unchanged'); end,
});
limited:select(1001, { group = 'New' }, now);
limited:observe('dynamis', utc + 1000, utc, now);
for index = 1, 100 do limited:observe('dynamis', utc + 1000, utc, now + index / 100); end
eq(full_reads, 2, 'The account group limit does not reread the full file every sample');
eq(limited:view(now + 1, utc).dynamis.remaining, 1000, 'A full account file keeps the own observed timer available');
return { count = count };
