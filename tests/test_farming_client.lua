local Client = require('core.farming_client')
local Farming = require('core.farming')
local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function length(values)
    local count = 0; for _ in pairs(values) do count = count + 1 end; return count
end
local function drop(id, slot, quantity, started, old, sequence)
    local bytes = MOCK.bytes(28)
    MOCK.put(bytes, 2, 2, sequence or 1)
    MOCK.put(bytes, 4, 4, quantity or 1)
    MOCK.put(bytes, 8, 4, 12345)
    MOCK.put(bytes, 16, 2, id)
    MOCK.put(bytes, 20, 1, slot or 0)
    MOCK.put(bytes, 21, 1, old and 1 or 0)
    MOCK.put(bytes, 24, 4, started or 10)
    return MOCK.packet(0x0D2, bytes)
end
local function result(slot, winner, kind, sequence)
    local bytes = MOCK.bytes(24)
    MOCK.put(bytes, 2, 2, sequence or 2)
    MOCK.put(bytes, 4, 4, winner or 1001)
    MOCK.put(bytes, 20, 1, slot or 0)
    MOCK.put(bytes, 21, 1, kind == nil and 1 or kind)
    return MOCK.packet(0x0D3, bytes)
end
local function gil(amount, actor, target, message)
    local bytes = MOCK.bytes(28)
    MOCK.put(bytes, 4, 4, actor or 1001)
    MOCK.put(bytes, 8, 4, target or 1001)
    MOCK.put(bytes, 12, 4, amount)
    MOCK.put(bytes, 24, 2, message or 565)
    return MOCK.packet(0x029, bytes)
end
local old_memory, old_resources = AshitaCore.GetMemoryManager, AshitaCore.GetResourceManager
local pool, seed_reads, resource_reads = {}, 0, 0
local metadata = { [100] = { Name = { 'Silk Thread' }, StackSize = 12 },
    [101] = { Name = { 'Beastmen\'s Seal' }, StackSize = 99 },
    [102] = { Name = { '.' }, StackSize = 1 } }
AshitaCore.GetMemoryManager = function()
    return { GetInventory = function()
        return { GetTreasurePoolItem = function(_, slot) seed_reads = seed_reads + 1; return pool[slot] end }
    end }
end
AshitaCore.GetResourceManager = function()
    return { GetItemById = function(_, id) resource_reads = resource_reads + 1; return metadata[id] end }
end
local snapshot = { valid = true, id = 1001, zone = 102 }
local client, model = Client.new(), Farming.new()
model:observe(true, 0)
client:observe(snapshot)
equal(seed_reads, 10, 'Startup seeds only ten native treasure slots')
for _ = 1, 100 do client:observe(snapshot) end
equal(seed_reads, 10, 'Steady samples never rescan the treasure pool')
equal(resource_reads, 0, 'Startup never scans item resources')
local first = drop(100, 0, 12)
client:packet(first, 1, model)
client:packet(first, 1, model)
client:packet(drop(100, 0, 12, 10, true), 2, model)
equal(model:view(2).pool_found, 12, 'New pool quantity counts once and old resends only hydrate')
local won = result(0)
client:packet(won, 3, model)
client:packet(won, 3, model)
equal(model:view(3).total, 12, 'Only the confirmed personal award counts')
equal(model:view(3).partial, false, 'An ordinary duplicate terminal packet is harmless')
client:packet(drop(100, 0, 12, 10, true), 4, model)
client:packet(result(0), 4, model)
equal(model:view(4).total, 12, 'A stale old pool resend cannot reopen an already received generation')
client:packet(drop(100, 0, 12, 10, false), 5, model)
client:packet(won, 5, model)
equal(client.pool[0].id, 100, 'An old terminal packet cannot consume a new pending item')
client:packet(result(0), 5, model)
equal(model:view(5).total, 24, 'Identical successive solo drops in the same millisecond remain separate')
equal(model:view(5).pool_found, 24, 'Identical successive pool additions remain separate after terminal results')
client:packet(drop(101, 1), 6, model)
client:packet(result(1, 9999), 6, model)
equal(model:view(6).total, 24, 'Another player winning is not personal loot')
equal(client.pool[1], nil, 'Another player winning still consumes the pending slot')
client:packet(drop(101, 1), 7, model)
client:packet(result(1, 1001, 0), 7, model)
equal(client.pool[1].id, 101, 'Lot and pass updates do not consume the pending slot')
client:packet(result(1, 1001, 2), 7, model)
equal(client.pool[1], nil, 'Failed awards consume the pending item')
equal(model:view(7).total, 24, 'Inventory failure does not become personal loot')
client:packet(drop(101, 1), 8, model)
client:packet(result(1, 1001, 3), 8, model)
equal(model:view(8).total, 24, 'A lost item is not received')
client:packet(drop(101, 1), 9, model)
model:set_paused(true, 9)
local paused_win = result(1)
client:packet(paused_win, 10, model)
equal(client.pool[1], nil, 'Paused terminal results still consume their metadata')
model:set_paused(false, 11)
client:packet(paused_win, 11, model)
equal(model:view(11).total, 24, 'Resume cannot catch up an ignored paused award')
client:packet(drop(101, 1), 12, model)
model:reset(12)
client:packet(result(1), 12, model)
equal(model:view(12).total, 1, 'Session reset preserves pending metadata for a future genuine receipt')
equal(model:view(12).pool_found, 0, 'Session reset does not invent a new pool appearance')
client:packet(drop(100, 0, 1, 12), 13, model)
client:packet(drop(101, 0, 1, 13, true), 14, model)
equal(client.pool[0].id, 101, 'Authoritative old pool refresh can replace a missing generation')
client:packet(result(0), 14, model)
equal(model:view(14).total, 2, 'A refreshed current generation can subsequently be received')
client:packet(drop(100, 0), 15, model)
client:packet(drop(0, 0), 15, model)
equal(client.pool[0], nil, 'Empty pool updates clear metadata')
client:packet(result(0, 1001, 1, 99), 16, model)
equal(model:view(16).partial, true, 'An unknown personal award is disclosed rather than guessed')
equal(model:view(16).total, 2, 'Unknown awards never infer items from inventory')
local no_raw, no_raw_model = Client.new(), Farming.new()
no_raw:observe(snapshot); no_raw_model:observe(true, 0)
local rawless_drop = drop(100, 0, 1, 9, false, 1); rawless_drop.data_raw = nil
local rawless_win = result(0); rawless_win.data_raw = nil
no_raw:packet(rawless_drop, 0, no_raw_model); no_raw:packet(rawless_win, 0, no_raw_model)
no_raw:packet(rawless_drop, 0, no_raw_model); no_raw:packet(rawless_win, 0, no_raw_model)
equal(no_raw_model:view(0).total, 1, 'Missing receive pointers still deduplicate an identical drop replay')
rawless_drop = drop(100, 0, 1, 9, false, 3); rawless_drop.data_raw = nil
no_raw:packet(rawless_drop, 1, no_raw_model); no_raw:packet(rawless_win, 1, no_raw_model)
equal(no_raw_model:view(1).total, 2, 'New packet sequences distinguish raw-pointer-free identical generations')
local paused_client, paused_model = Client.new(), Farming.new()
paused_client:observe(snapshot); paused_model:observe(true, 0); paused_model:set_paused(true, 0)
paused_client:packet(result(0), 1, paused_model)
equal(paused_model:view(1).partial, false, 'An intentionally ignored unknown paused award does not mark the session partial')
equal(paused_model:view(1).total, 0, 'Unknown paused awards do not change counts')
paused_model:set_paused(false, 2); paused_model:discontinuity(2)
paused_client:packet(result(1), 3, paused_model)
equal(paused_model:view(3).partial, false, 'Unavailable tracking cannot create a partial receipt warning')
paused_model:observe(true, 4); paused_model:mark_partial(); paused_model:set_paused(true, 4)
paused_client:packet(result(2), 5, paused_model)
equal(paused_model:view(5).partial, true, 'Ignoring paused awards preserves an earlier real partial-history flag')

local fresh = Client.new()
local seeded = Farming.new(); seeded:observe(true, 0)
pool[2] = { ItemId = 100, Count = 12 }
pool[3] = { ItemId = 65535, Count = 12 }
pool[4] = { ItemId = 101, Count = 0 }
fresh:observe(snapshot)
equal(length(fresh.pool), 1, 'Only valid occupied native pool entries seed metadata')
equal(seeded:view(0).pool_found, 0, 'Seeded old items do not become newly found treasure')
fresh:packet(result(2), 1, seeded)
equal(seeded:view(1).total, 12, 'An item already present at load counts when subsequently received')
fresh:packet(drop(100, 2, 12, 10, true), 2, seeded)
fresh:packet(result(2), 2, seeded)
equal(seeded:view(2).total, 12, 'Seeded receipt cannot be replayed through an old refresh')
pool = {}
fresh:observe({ valid = true, id = 1002, zone = 102 })
equal(length(fresh.pool), 0, 'Character change clears the previous treasure pool')
fresh:packet(drop(100, 0), 3, seeded)
fresh:packet(result(0, 1001), 3, seeded)
equal(seeded:view(3).total, 12, 'Previous character cannot receive on the new character identity')
fresh:observe({ valid = true, id = 1002, zone = 103 })
equal(length(fresh.done), 0, 'Zone change clears packet deduplication history')
fresh:observe({ valid = false })
equal(fresh.id, nil, 'Invalid samples clear the active owner')
fresh:packet(drop(100, 0), 4, seeded)
equal(length(fresh.pool), 0, 'Packets while no character is active are ignored')
for _, value in ipairs({ { valid = true, id = 0, zone = 102 }, { valid = true, id = '1', zone = 102 },
    { valid = true, id = 1001, zone = 0 }, { valid = 1, id = 1001, zone = 102 },
    { valid = true, id = 1001, zone = math.huge } }) do
    fresh:observe(value); equal(fresh.id, nil, 'Malformed identity cannot seed a pool')
end
fresh:observe(snapshot)
for _, flag in ipairs({ 'blocked', 'blocked_original', 'injected', 'is_injected' }) do
    local event = drop(100, 0); event[flag] = true
    fresh:packet(event, 5, seeded)
    equal(length(fresh.pool), 0, 'Blocked and injected drops cannot change metadata')
end
for _, size in ipairs({ 27, 28.5, 513, math.huge, 0 / 0, '28' }) do
    local event = drop(100, 0); event.size = size
    fresh:packet(event, 5, seeded)
    equal(length(fresh.pool), 0, 'Invalid packet size cannot change metadata')
end
local truncated = drop(100, 0); truncated.data = truncated.data:sub(1, 27)
fresh:packet(truncated, 5, seeded)
fresh:packet(nil, 5, seeded)
equal(length(fresh.pool), 0, 'Truncated or absent events are harmless')
for _, event in ipairs({ drop(100, 10), drop(100, 0, 1000), drop(65535, 0), result(10), result(0, 1001, 4) }) do
    fresh:packet(event, 5, seeded)
    equal(length(fresh.pool), 0, 'Invalid treasure fields cannot alter the pool')
end
fresh:packet(drop(100, 0), 6, seeded)
fresh:packet(result(0), 607, seeded)
equal(seeded:view(607).total, 12, 'Expired metadata cannot invent a delayed receipt')
equal(seeded:view(607).partial, true, 'Expired metadata is disclosed')
local money = Farming.new(); money:observe(true, 0)
local paid = gil(123)
fresh:packet(paid, 608, money)
fresh:packet(paid, 608, money)
equal(money:view(608).mob_gil, 123, 'A committed personal mob-gil award counts once')
fresh:packet(gil(123), 608, money)
equal(money:view(608).mob_gil, 246, 'Separate identical mob-gil awards remain separate')
for _, event in ipairs({ gil(1, 9999), gil(1, 1001, 9999), gil(1, 1001, 1001, 8), gil(0), gil(1000000000) }) do
    fresh:packet(event, 609, money)
end
equal(money:view(609).mob_gil, 246, 'Other messages and invalid gil cannot become mob gil')
money:set_paused(true, 609)
local ignored = gil(50); fresh:packet(ignored, 610, money)
money:set_paused(false, 611); fresh:packet(ignored, 611, money)
equal(money:view(611).mob_gil, 246, 'Paused mob-gil tokens cannot replay on resume')
equal(money:view(611).total, 0, 'Gil messages never become item receipts')
local burst, burst_model, held_packets = Client.new(), Farming.new(), {}
burst:observe(snapshot); burst_model:observe(true, 0)
for index = 1, 300 do
    held_packets[index] = gil(1)
    burst:packet(held_packets[index], index, burst_model)
end
equal(burst_model:view(300).mob_gil, 300, 'A large legitimate award burst retains every received quantity')
equal(length(burst.done), 256, 'Receive-token memory remains bounded')
equal(#burst.done_order, 256, 'Receive-token eviction order remains bounded')
local before_metadata = resource_reads
local info = client:item(100)
equal(info.name, 'Silk Thread', 'Metadata uses local item resources')
equal(info.stack_size, 12, 'Metadata reads the actual stack size')
equal(client:item(100), info, 'Repeated metadata returns its cached row')
equal(resource_reads, before_metadata + 1, 'Repeated names do not hit native resources again')
equal(client:item(102), nil, 'Placeholder resource names are not items')
before_metadata = resource_reads
equal(client:item(102), nil, 'Missing metadata is cached too')
equal(resource_reads, before_metadata, 'Missing metadata does not repeatedly read resources')
for id = 1000, 2024 do
    metadata[id] = { Name = { 'Loot ' .. id }, StackSize = 1 }
    client:item(id)
end
equal(length(client.metadata), 1024, 'Metadata cache remains bounded')
equal(#client.metadata_order, 1024, 'Metadata eviction order remains bounded')
local names = Client.new()
before_metadata = resource_reads
local rows, pending = names:search('lo')
equal(resource_reads - before_metadata, 64, 'Search reads at most sixty-four item resources per call')
equal(#rows, 0, 'Nonmatching resources are not shown')
equal(pending, true, 'Incomplete search remains explicitly pending')
before_metadata = resource_reads
rows, pending = names:search('100')
equal(#rows, 1, 'Numeric item search is immediate')
equal(rows[1].id, 100, 'Numeric search returns its requested item')
equal(pending, false, 'Numeric lookup does not begin a full catalog scan')
equal(resource_reads - before_metadata, 1, 'Numeric lookup reads one resource')
before_metadata = resource_reads
names:search('x'); names:search(string.rep('x', 81)); names:search('')
equal(resource_reads, before_metadata, 'Short or overlong queries do no resource work')
for id = 1, 80 do metadata[id] = { Name = { 'Match ' .. id }, StackSize = 1 } end
before_metadata = resource_reads
rows, pending = names:search('match')
equal(#rows, 50, 'A broad query stops after fifty matches')
equal(pending, false, 'A full search result stops catalog work')
equal(resource_reads - before_metadata, 50, 'Matched resources are not reread to build metadata')
before_metadata = resource_reads
names:search('match')
equal(resource_reads, before_metadata, 'Completed searches do no repeated resource work')
local old_tick, ticking = ashita.time.get_tick64, 0
ashita.time.get_tick64 = function() ticking = ticking + 1; return ticking end
before_metadata = resource_reads
names:search('never matches')
equal(resource_reads - before_metadata, 2, 'Search honors its two-millisecond cooperative budget')
ashita.time.get_tick64 = nil
before_metadata = resource_reads
names:search('clock unavailable')
equal(resource_reads - before_metadata, 64, 'Missing clocks retain the strict operation-count bound')
ashita.time.get_tick64 = old_tick
AshitaCore.GetMemoryManager = function() return {} end
local incomplete = Client.new()
incomplete:observe(snapshot)
equal(incomplete.id, 1001, 'Missing optional treasure capability does not stop normal startup')
AshitaCore.GetResourceManager = nil
equal(incomplete:item(100), nil, 'Missing optional item resources use an unknown name')
AshitaCore.GetMemoryManager, AshitaCore.GetResourceManager = old_memory, old_resources
return { count = checks }
