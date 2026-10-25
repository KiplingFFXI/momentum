local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local memory = AshitaCore:GetMemoryManager();
local calls = { used = 0, capacity = 0, flags = 0, counter = 0, items = 0, gil = 0 };
local bags = { [0] = { used = 56, capacity = 80 }, [5] = { used = 34, capacity = 80 } };
local flags, counter = 33, 10;
local inventory = {
    GetContainerCount = function(_, id)
        assert(id == 0 or id == 5, 'Only Inventory and Mog Satchel can be read');
        calls.used = calls.used + 1; return bags[id].used;
    end,
    GetContainerCountMax = function(_, id)
        assert(id == 0 or id == 5, 'Only Inventory and Mog Satchel capacity can be read');
        calls.capacity = calls.capacity + 1; return bags[id].capacity;
    end,
    GetContainerUpdateFlags = function() calls.flags = calls.flags + 1; return flags; end,
    GetContainerUpdateCounter = function() calls.counter = calls.counter + 1; return counter; end,
    GetContainerItem = function(_, bag, slot)
        calls.items = calls.items + 1;
        if bag == 0 and slot == 0 then calls.gil = calls.gil + 1; return { Id = 65535, Count = 1000 }; end
        return { Id = 0, Count = 0 };
    end,
};
memory.GetInventory = function() return inventory; end;
AshitaCore.GetMemoryManager = function() return memory; end;
MOCK.load_addon(); MOCK.frame(0.25);
local app = MOMENTUM_TEST;
eq(calls.used, 0, 'Default layout reads no occupied slot counts');
eq(calls.capacity, 0, 'Default layout reads no bag capacities');
eq(calls.flags, 0, 'Default layout does not poll inventory readiness');
eq(calls.counter, 0, 'Default layout does not poll inventory counters');
local items = calls.items;
local function select_bags()
    local enabled = app.settings().display.enabled;
    enabled.inventory_slots, enabled.inventory_free = true, true;
    enabled.satchel_slots, enabled.satchel_free = true, true;
end
local function view() return app.view(MOCK.now).storage; end
local function sync(mask, state)
    local bytes = MOCK.bytes(12);
    MOCK.put(bytes, 4, 1, state or 0); MOCK.put(bytes, 8, 4, mask);
    MOCK.fire('packet_in', MOCK.packet(0x01D, bytes));
end
local function changed(bag)
    local bytes = MOCK.bytes(16); MOCK.put(bytes, 14, 1, bag);
    MOCK.fire('packet_in', MOCK.packet(0x020, bytes));
end
select_bags(); MOCK.frame(0.25);
eq(view().inventory.used, 56, 'Inventory shows occupied slots');
eq(view().inventory.capacity, 80, 'Inventory shows actual capacity');
eq(view().inventory.free, 24, 'Inventory shows free slots');
eq(view().satchel.used, 34, 'Mog Satchel shows occupied slots');
eq(view().satchel.free, 46, 'Mog Satchel shows free slots');
eq(calls.used, 2, 'Two readouts for one bag share the same native count');
eq(calls.items, items, 'Slot tracking never scans items');
local before = calls.used;
for _ = 1, 30 do MOCK.frame(1 / 120); end
eq(calls.used, before, 'Idle frames reuse counts');

MOCK.fire('command', { command = '/momentum pause' });
bags[0].used, bags[5].used = 57, 33; counter = counter + 1;
changed(0); changed(5); MOCK.frame(0.25);
eq(view().inventory.used, 57, 'Pause leaves Inventory live');
eq(view().satchel.free, 47, 'Pause leaves Mog Satchel live');
MOCK.fire('command', { command = '/momentum reset' });
bags[0].used, bags[5].used = 80, 0; counter = counter + 1;
changed(0); changed(5); MOCK.frame(0.25);
eq(view().inventory.free, 0, 'Reset keeps a full Inventory count');
eq(view().satchel.used, 0, 'A loaded empty Mog Satchel is known zero');
eq(view().satchel.free, 80, 'A loaded empty Mog Satchel has all slots free');

local saved = require('ui.history').copy(app.settings());
MOCK.settings.switch_character(saved);
eq(view().inventory, nil, 'Settings callbacks clear the displayed previous counts');
MOCK.frame(0.25);
eq(view().inventory.used, 80, 'A same-character settings reload recovers without another inventory sync');
local logout = MOCK.bytes(8); MOCK.put(logout, 4, 1, 1);
MOCK.fire('packet_in', MOCK.packet(0x00B, logout));
eq(view().inventory, nil, 'Logout clears the old Inventory immediately');
eq(view().satchel, nil, 'Logout clears the old Mog Satchel immediately');
MOCK.player.server_id = 2002;
MOCK.settings.switch_character(require('ui.defaults').make());
select_bags();
local zone = MOCK.bytes(0xA0);
MOCK.put(zone, 4, 4, 2002); MOCK.put(zone, 48, 2, MOCK.player.zone);
MOCK.fire('packet_in', MOCK.packet(0x00A, zone));
MOCK.fire('packet_in', MOCK.packet(0x061, MOCK.bytes(96)));
MOCK.frame(0.25);
eq(view().inventory, nil, 'An alt cannot inherit the old Inventory while loading');
eq(view().satchel, nil, 'An alt cannot inherit the old Mog Satchel while loading');
bags[0].used, bags[0].capacity = 12, 40;
bags[5].used, bags[5].capacity = 5, 40;
sync(1); MOCK.frame(0.25);
eq(view().inventory.used, 12, 'The new character uses its own Inventory');
eq(view().inventory.capacity, 40, 'The new character uses its own unlocked capacity');
eq(view().satchel, nil, 'Mog Satchel waits for its own container data');
sync(33, 1); MOCK.frame(0.25);
eq(view().satchel.used, 5, 'Mog Satchel appears after its data loads');
eq(view().satchel.capacity, 40, 'Mog Satchel follows the current character capacity');

MOCK.player.server_id = 1001;
MOCK.settings.switch_character(saved);
MOCK.put(zone, 4, 4, 1001);
MOCK.fire('packet_in', MOCK.packet(0x00A, zone));
MOCK.fire('packet_in', MOCK.packet(0x061, MOCK.bytes(96)));
MOCK.frame(0.25);
eq(view().inventory, nil, 'Returning main waits for its own current bag data');
bags[0].used, bags[0].capacity = 56, 80;
bags[5].used, bags[5].capacity = 34, 80;
sync(33, 1); MOCK.frame(0.25);
eq(view().inventory.used, 56, 'Main Inventory returns without the alt capacity');
eq(view().satchel.used, 34, 'Main Mog Satchel returns without alt values');
for _, id in ipairs({ 'inventory_slots', 'inventory_free', 'satchel_slots', 'satchel_free' }) do
    app.settings().display.enabled[id] = false;
end
MOCK.frame(0.25);
before = calls.used;
local old_flags, old_counter = calls.flags, calls.counter;
for _ = 1, 120 do MOCK.frame(1 / 60); end
eq(calls.used, before, 'Disabled storage does not read counts');
eq(calls.flags, old_flags, 'Disabled storage does not poll flags');
eq(calls.counter, old_counter, 'Disabled storage does not poll counters');
eq(view().inventory, nil, 'Disabled bag values are discarded');
eq(view().satchel, nil, 'Disabled satchel values are discarded');
eq(calls.items, calls.gil, 'Only existing gil baselines read items through character changes');
eq(app.state.broken, false, 'Entry tracking remains healthy');
return { count = count };
