local defaults = require('ui.defaults');
local modes = require('ui.modes');
local tracker_module = require('core.tracker');
local count = 0;
local function eq(actual, expected, label)
    count = count + 1;
    assert(actual == expected, label .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local function near(actual, expected, label)
    count = count + 1;
    assert(type(actual) == 'number' and math.abs(actual - expected) < 0.001, label);
end

local utc, finish = 1800000000, 1800;
local memory = AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager = function() return memory; end;
local stats = memory:GetPlayer();
stats.GetStatusIcons = function() return { [0] = 251, [1] = 249 }; end;
stats.GetStatusTimers = function()
    local value = ((utc + finish - 1009810800) * 60) % 4294967296;
    return { [0] = value, [1] = value };
end;
local used, balance, updates = 70, 1000, 1;
local extra = MOCK.bytes(24);
MOCK.put(extra, 0, 1, 1); MOCK.put(extra, 1, 1, 6); MOCK.put(extra, 3, 1, 0x90);
MOCK.put(extra, 4, 4, utc + finish - 1009810800);
local ring = { Id = 15762, Count = 1, Flags = 0, Extra = MOCK.packet(0, extra).data };
memory.GetInventory = function()
    return {
        GetContainerCount = function(_, bag) assert(bag == 0 or bag == 5); return bag == 0 and used or 10; end,
        GetContainerCountMax = function(_, bag) return bag == 0 and 80 or bag == 5 and 1 or 0; end,
        GetContainerUpdateFlags = function() return 33; end,
        GetContainerUpdateCounter = function() return updates; end,
        GetContainerItem = function(_, bag, slot)
            if bag == 0 and slot == 0 then return { Id = 65535, Count = balance }; end;
            if bag == 0 and slot == 1 then return ring; end;
        end,
        GetTreasurePoolItem = function() return { ItemId = 0, Count = 0 }; end,
    };
end;
local player = require('core.player');
player.utc = function() return utc + MOCK.now; end;
local resources = {};
resources.GetItemById = function(_, id) return { Name = { id == 4 and 'Shell' or 'Test item' }, StackSize = id == 4 and 12 or 1 }; end;
AshitaCore.GetResourceManager = function() return resources; end;
local settings = defaults.make();
settings.appearance_version, settings.style.palette_version = 2, 1;
modes.select(settings, 'farming');
settings.farming.selected_item, settings.farming.goal, settings.farming.goal_unit = 4, 1, 'stacks';
settings.farming.wanted['4'], settings.farming.prices['4'] = true, 50;
settings.display.enabled.ring = true;
for _, id in ipairs({ 'farm_item', 'farm_goal', 'farm_space' }) do
    local alert = settings.alerts.events[id];
    alert.visual, alert.sound, alert.file, alert.cooldown = true, true, 'FF VII Save.mp3', 0;
end
settings.alerts.events.farm_space.visual, settings.alerts.events.farm_space.sound = false, false;
settings.events.auto_layout, settings.dynamis.auto_layout = false, false;
MOCK.settings_file, MOCK.player.zone = settings, 144;
local sound, played = require('core.sound'), 0;
sound.use = function() return true; end;
sound.play = function() played = played + 1; return true; end;
MOCK.load_addon();
local app = MOMENTUM_TEST;
local function packet(id, bytes)
    local fields = MOCK.packet(id, bytes);
    local native = newproxy(true);
    getmetatable(native).__index = function(_, name)
        if fields[name] ~= nil then return fields[name]; end
        error('Unknown native packet member: ' .. tostring(name));
    end;
    MOCK.fire('packet_in', native);
end;
local function frame(seconds)
    MOCK.frame(seconds or 0.25);
    eq(app.state.broken, false, 'The full Farming render stays healthy');
end
local generation = 1;
local function drop(slot, quantity, old)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, quantity); MOCK.put(bytes, 8, 4, 0x1000123);
    MOCK.put(bytes, 16, 2, 4); MOCK.put(bytes, 20, 1, slot);
    MOCK.put(bytes, 21, 1, old and 1 or 0); MOCK.put(bytes, 24, 4, generation);
    generation = generation + 1;
    packet(0x0D2, bytes);
end
local function award(slot, winner, result)
    local bytes = MOCK.bytes(24);
    MOCK.put(bytes, 4, 4, winner or MOCK.player.server_id);
    MOCK.put(bytes, 20, 1, slot); MOCK.put(bytes, 21, 1, result or 1);
    packet(0x0D3, bytes);
end
local function mob_gil(amount)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, MOCK.player.server_id); MOCK.put(bytes, 8, 4, MOCK.player.server_id);
    MOCK.put(bytes, 12, 4, amount); MOCK.put(bytes, 24, 2, 565); packet(0x029, bytes);
end
local function bag(amount)
    used, updates = amount, updates + 1;
    local bytes = MOCK.bytes(16); MOCK.put(bytes, 14, 1, 0); packet(0x020, bytes);
end
local function wallet(amount)
    balance = amount;
    local bytes = MOCK.bytes(20); MOCK.put(bytes, 4, 4, amount); packet(0x01E, bytes);
end
frame();
eq(app.settings().farming.stack_size, 12, 'Stack goals use the client item stack size');
eq(app.view(MOCK.now).farming.selected.goal, 12, 'The stack goal is converted to individual items');
drop(0, 5); award(0); frame(1.1);
eq(app.view(MOCK.now).farming.total, 5, 'Confirmed personal treasure reaches the session');
eq(app.view(MOCK.now).farming.pool_found, 5, 'Pool appearances remain separately counted');
eq(app.view(MOCK.now).farming.rate, nil, 'Farming rate waits for one minute');
eq(app.farming_notifications:view(MOCK.now).id, 'farm_item', 'Wanted receipt reaches the notice dispatcher');
eq(played, 1, 'Wanted receipt uses the normal sound path');
for _ = 1, 31 do MOCK.frame(1); end
local function saved_farm()
    local data = assert(require('core.file_store').read(MOCK_INSTALL_PATH .. '/config/addons/momentum/sessions-1001.json'));
    local current = app.services.session_current().id:match(':(%d+)$');
    for _, row in ipairs(data.entries) do if row.id == current then return row.payload.farming; end end
    error('The current session was not written');
end
eq(app.tracker().started, nil, 'Items alone do not pretend EXP was earned');
eq(app.tracker().gil.started, false, 'Items alone do not pretend wallet gil changed');
eq(saved_farm().total, 5, 'An item-only session checkpoints normally without unload or forced save');
award(0); drop(1, 2); award(1, 2002); drop(2, 3); award(2, nil, 2);
eq(app.view(MOCK.now).farming.total, 5, 'Duplicates, other winners, and failed awards do not count');
drop(3, 7, true); award(3); frame(1.1);
eq(app.view(MOCK.now).farming.total, 12, 'An old pool item counts when actually awarded');
eq(app.view(MOCK.now).farming.pool_found, 10, 'An old pool refresh is not a new pool drop');
eq(app.farming_notifications.last.farm_goal ~= nil, true, 'The newly received stack goal reaches the alert pipeline');
eq(app.view(MOCK.now).farming.selected.goal_complete, true, 'The stack goal is complete');
eq(played, 2, 'The next receipt can play the selected sound');
mob_gil(120); wallet(1400);
eq(app.view(MOCK.now).farming.mob_gil, 120, 'Monster gil has its own confirmed total');
eq(app.view(MOCK.now).gil.net, 400, 'Actual wallet change remains separate');

local space = app.settings().alerts.events.farm_space;
space.visual, space.sound = true, true;
frame(1.1);
eq(app.farming_notifications.last.farm_space, nil, 'Enabling a bag warning does not emit a catch-up alert');
bag(76); frame(1.1);
eq(app.farming_notifications:view(MOCK.now).id, 'farm_space', 'Crossing the free-slot threshold emits a warning');
local before_sound = played;
bag(77); frame(1.1);
eq(played, before_sound, 'Remaining below the threshold does not spam sounds');

local area, battle = require('data.event_rules').areas[144];
for _, fight in pairs(area.battles) do if fight.kind == 'bcnm' then battle = fight; break; end end
local entry = MOCK.bytes(28);
MOCK.put(entry, 4, 4, MOCK.player.server_id); MOCK.put(entry, 12, 4, battle.index);
MOCK.put(entry, 26, 2, area.messages.ENTERING_THE_BATTLEFIELD_FOR); packet(0x02A, entry);
local timer = MOCK.bytes(40);
MOCK.put(timer, 4, 4, 1); MOCK.put(timer, 8, 4, utc - 1009810800);
MOCK.put(timer, 12, 4, 1200); MOCK.put(timer, 36, 1, 1); packet(0x075, timer);
local exp = MOCK.bytes(28);
MOCK.put(exp, 4, 4, MOCK.player.server_id); MOCK.put(exp, 8, 4, MOCK.player.server_id);
MOCK.put(exp, 16, 4, 100); MOCK.put(exp, 20, 4, 2); MOCK.put(exp, 24, 2, 8);
MOCK.player.exp = MOCK.player.exp + 100; packet(0x02D, exp); frame();
local baseline = app.view(MOCK.now);
local event_deadline = app.events.core.current.ends_at;
local chain_deadline = baseline.chain_started + baseline.chain_window;
eq(baseline.food, true, 'The live food effect is known');
eq(baseline.dedication, true, 'The live Dedication effect is known');
eq(baseline.rings.entries[1] ~= nil, true, 'The owned EXP ring remains visible');
app.services.session_pause(true);
local paused = app.view(MOCK.now).farming;
drop(4, 3); award(4); mob_gil(80); wallet(1600); bag(75); frame(2);
eq(app.view(MOCK.now).farming.total, 12, 'Pause excludes newly received treasure');
eq(app.view(MOCK.now).farming.mob_gil, 120, 'Pause excludes monster gil');
eq(app.view(MOCK.now).gil.current, 1600, 'Pause keeps current gil live');
eq(app.view(MOCK.now).gil.net, 400, 'Pause excludes wallet session changes');
eq(app.view(MOCK.now).storage.inventory.free, 5, 'Pause keeps Inventory slots live');
near(app.view(MOCK.now).farming.elapsed, paused.elapsed, 'Pause freezes farming elapsed time');
eq(app.events.core.current.loot[4].received, 3, 'Event-run loot keeps counting while Farming is paused');
eq(app.events.core.current.ends_at, event_deadline, 'Pause leaves the native event deadline unchanged');
near(app.view(MOCK.now).chain_left, chain_deadline - MOCK.now, 'Pause leaves the EXP chain deadline unchanged');
near(app.view(MOCK.now).food_seconds, finish - MOCK.now, 'Pause leaves the food deadline unchanged');
near(app.view(MOCK.now).dedication_seconds, finish - MOCK.now, 'Pause leaves the Dedication deadline unchanged');
near(app.view(MOCK.now).rings.entries[1].recast + app.state.rings_at, finish, 'Pause leaves the ring recast deadline unchanged');
app.services.session_pause(false); frame();
eq(app.view(MOCK.now).farming.total, 12, 'Resume does not add missed paused receipts');
drop(5, 2);
eq(app.services.session_reset(), true, 'Reset starts a fresh Farming session');
eq(app.view(MOCK.now).farming.total, 0, 'Reset clears Farming item totals');
eq(app.view(MOCK.now).farming.rate, nil, 'Reset clears Items/HR');
eq(app.view(MOCK.now).farming.mob_gil, 0, 'Reset clears monster gil');
eq(app.view(MOCK.now).gil.net, 0, 'Reset clears wallet session changes');
award(5); frame();
eq(app.view(MOCK.now).farming.total, 2, 'A pending pool award survives Reset session and counts once');
eq(app.view(MOCK.now).farming.pool_found, 0, 'The pre-reset pool appearance is not counted again');
eq(app.events.core.current.ends_at, event_deadline, 'Reset leaves the event deadline unchanged');
eq(app.events.core.current.loot[4].received, 5, 'Reset leaves event-specific loot intact');
near(app.view(MOCK.now).chain_left, chain_deadline - MOCK.now, 'Reset preserves the chain countdown');
near(app.view(MOCK.now).food_seconds, finish - MOCK.now, 'Reset preserves food countdown');
near(app.view(MOCK.now).dedication_seconds, finish - MOCK.now, 'Reset preserves Dedication countdown');
near(app.view(MOCK.now).rings.entries[1].recast + app.state.rings_at, finish, 'Reset preserves ring recast');
local summary = app.services.farming_summary();
eq(summary:find('Shell', 1, true) ~= nil, true, 'The copied summary contains actual item names');
eq(summary:find('Estimated loot value: ~100', 1, true) ~= nil, true, 'The summary keeps manual gross value separate');
eq(summary:find('Net gil: 0', 1, true) ~= nil, true, 'Estimated value is not added to net gil');
for _ = 1, 61 do MOCK.frame(1); end
eq(app.view(MOCK.now).farming.rate ~= nil, true, 'Items/HR becomes available without another EXP award');
local payload = app.tracker():export(MOCK.now);
local old = require('ui.history').copy(payload); old.farming = nil;
local legacy = tracker_module.new();
eq(legacy:restore(old, MOCK.now + 500), true, 'Old sessions without Farming remain valid');
eq(legacy.farming:view(MOCK.now + 500, settings.farming).total, 0, 'Old sessions receive empty Farming totals');
local restored = tracker_module.new();
eq(restored:restore(payload, MOCK.now + 500), true, 'Farming session payload restores');
near(restored.farming:view(MOCK.now + 500, settings.farming).elapsed, payload.farming.elapsed, 'Offline time is not added on restore');
payload.farming.total = -1;
eq(tracker_module.new():restore(payload, MOCK.now), false, 'Malformed Farming payload is rejected');
eq(app.services.session_reset(), true, 'Start an empty session for pool-only and mob-gil-only checkpoints');
drop(6, 1); mob_gil(33);
for _ = 1, 31 do MOCK.frame(1); end
eq(app.view(MOCK.now).farming.total, 0, 'Unawarded pool items are not received items');
eq(saved_farm().pool_found, 1, 'Pool-only activity checkpoints normally');
eq(saved_farm().mob_gil, 33, 'Confirmed monster gil checkpoints without wallet deltas or EXP');
eq(#MOCK.commands, 0, 'Farming sends no gameplay commands');
MOCK.fire('unload');
return { count = count };
