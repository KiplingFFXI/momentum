local events = require('core.events');
local client = require('core.events_client');
local runtime = require('core.events_runtime');
local rules = require('data.event_rules');
local count, sequence = 0, 0;
local function eq(actual, expected, name)
    count = count + 1;
    assert(actual == expected, name .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected));
end
local shami = assert(rules.npcs.shami, 'Shami source contract');
eq(shami.zone, 246, 'Shami is in Port Jeuno');
eq(shami.id, 17784905, 'Source Shami identity');
eq(shami.event, 322, 'Balance and orb menu');
eq(shami.deposit_event, 321, 'Accepted deposit dialogue');
eq(shami.empty_event, 23, 'Empty stored balance dialogue');
eq(shami.item_obtained, 6395, 'Single item receipt');
eq(shami.item_obtained_count, 6404, 'Multiple item receipt');
eq(shami.inventory_full, 6387, 'Inventory full message');

local function packet(id, size, fields)
    local data = MOCK.bytes(size);
    sequence = (sequence + 1) % 65536;
    MOCK.put(data, 2, 2, sequence);
    for _, row in ipairs(fields or {}) do MOCK.put(data, row[1], row[2], row[3]); end
    return MOCK.packet(id, data);
end
local function menu(event, bs, ks, target, zone)
    return packet(0x034, 52, { { 4, 4, target or shami.id }, { 8, 4, (ks or 0) * 65536 + (bs or 0) },
        { 42, 2, zone or shami.zone }, { 44, 2, event or shami.event } });
end
local function final(option, overrides)
    overrides = overrides or {};
    return packet(0x05B, overrides.size or 20, { { 4, 4, overrides.target or shami.id }, { 8, 4, option },
        { 14, 2, overrides.mode or 0 }, { 16, 2, overrides.zone or shami.zone }, { 18, 2, overrides.event or shami.event } });
end
local function receipt(item, quantity, actor, message)
    return packet(0x02A, 28, { { 4, 4, actor or 1001 }, { 8, 4, item }, { 12, 4, quantity or 0 },
        { 26, 2, message or (quantity and quantity > 1 and shami.item_obtained_count or shami.item_obtained) } });
end
local settings = { events = { enabled = true } };
local memory = { GetPlayer = function() return { HasKeyItem = function() return false; end }; end };
local function fixture()
    local core = events.new();
    local observer = client.new(core, { memory = memory, clock = function() return 1800000000; end });
    observer:context(1001, shami.zone, 0, settings, false);
    return core, observer;
end
local function balance(core, key)
    return core.currencies[key] and core.currencies[key].value;
end
local function seed(observer, bs, ks, now)
    observer:packet(menu(shami.event, bs or 120, ks or 90), now or 0, settings);
end
local function currency(observer, bs, ks, now)
    observer:packet(packet(0x113, 192, { { 16, 2, bs }, { 18, 2, ks } }), now, settings);
end

local core, observer = fixture();
seed(observer, 1234, 5678);
eq(balance(core, 'beastmen_seals'), 1234, 'Talking to Shami reads stored BS');
eq(balance(core, 'kindred_seals'), 5678, 'Talking to Shami reads stored KS');
observer:packet(menu(shami.event, 0, 0), 1, settings);
eq(balance(core, 'beastmen_seals'), 0, 'Packed menu includes a known zero BS balance');
eq(balance(core, 'kindred_seals'), 0, 'Packed menu includes a known zero KS balance');
seed(observer, 25, 35, 2);
observer:packet(menu(shami.event, 999, 999, shami.id + 1), 3, settings);
eq(balance(core, 'beastmen_seals'), 25, 'Other NPC cannot supply a seal balance');
observer:packet(menu(shami.event, 999, 999, nil, shami.zone + 1), 4, settings);
eq(balance(core, 'kindred_seals'), 35, 'Wrong zone cannot supply a seal balance');
local invalid = menu(shami.event, 999, 999);
invalid.injected = true;
observer:packet(invalid, 5, settings);
eq(balance(core, 'beastmen_seals'), 25, 'Injected balance ignored');
invalid = menu(shami.event, 999, 999);
invalid.blocked = true;
observer:packet(invalid, 6, settings);
eq(balance(core, 'kindred_seals'), 35, 'Blocked balance ignored');

observer:packet(packet(0x034, 52, { { 4, 4, shami.id }, { 8, 4, 30 * 65536 },
    { 42, 2, shami.zone }, { 44, 2, shami.deposit_event } }), 7, settings);
eq(balance(core, 'beastmen_seals'), 30, 'Deposit dialogue supplies the new BS total');
eq(balance(core, 'kindred_seals'), 35, 'Untouched KS deposit field is not a zero balance');
observer:packet(packet(0x034, 52, { { 4, 4, shami.id }, { 12, 4, 40 * 65536 },
    { 42, 2, shami.zone }, { 44, 2, shami.deposit_event } }), 8, settings);
eq(balance(core, 'beastmen_seals'), 30, 'Untouched BS deposit field is not a zero balance');
eq(balance(core, 'kindred_seals'), 40, 'Deposit dialogue supplies the new KS total');
observer:packet(packet(0x034, 52, { { 4, 4, shami.id }, { 8, 4, 41 * 65536 }, { 12, 4, 51 * 65536 },
    { 42, 2, shami.zone }, { 44, 2, shami.deposit_event } }), 9, settings);
eq(balance(core, 'beastmen_seals'), 41, 'Mixed seal deposit updates BS');
eq(balance(core, 'kindred_seals'), 51, 'Mixed seal deposit updates KS');
local empty = packet(0x032, 20, { { 4, 4, shami.id }, { 10, 2, shami.zone }, { 12, 2, shami.empty_event } });
local kind, parsed = client.parse(empty);
eq(kind, 'menu', 'Parameterless event uses the normal menu path');
eq(parsed.zone, shami.zone, 'Parameterless event zone offset');
eq(parsed.event, shami.empty_event, 'Parameterless event ID offset');
eq(type(parsed.values), 'table', 'Parameterless event has an empty parameter table');
observer:packet(empty, 10, settings);
eq(balance(core, 'beastmen_seals'), 0, 'Empty Shami dialogue confirms zero BS');
eq(balance(core, 'kindred_seals'), 0, 'Empty Shami dialogue confirms zero KS');
core, observer = fixture();
observer:packet(packet(0x034, 52, { { 4, 4, shami.id }, { 8, 4, 12 * 65536 },
    { 42, 2, shami.zone }, { 44, 2, shami.deposit_event } }), 0, settings);
eq(balance(core, 'beastmen_seals'), 12, 'A deposit works without a previously recorded balance');
eq(balance(core, 'kindred_seals'), nil, 'A deposit does not invent the other stored balance');
observer:packet(packet(0x032, 20, { { 4, 4, shami.id + 1 }, { 10, 2, shami.zone }, { 12, 2, shami.empty_event } }), 1, settings);
eq(balance(core, 'beastmen_seals'), 12, 'Another NPC empty dialogue cannot zero seals');
eq(client.parse(packet(0x032, 16)), nil, 'Truncated parameterless event rejected');

for item, orb in pairs(rules.orbs) do
    core, observer = fixture();
    seed(observer, 120, 150);
    observer:outgoing(final(orb.option), 1);
    eq(balance(core, orb.seal == 'beastmen' and 'beastmen_seals' or 'kindred_seals'),
        orb.seal == 'beastmen' and 120 or 150, orb.name .. ' choice does not spend seals before confirmation');
    local success = receipt(item);
    observer:packet(success, 2, settings);
    local key = orb.seal == 'beastmen' and 'beastmen_seals' or 'kindred_seals';
    eq(balance(core, key), (orb.seal == 'beastmen' and 120 or 150) - orb.cost, orb.name .. ' confirmed receipt spends its source seal cost');
    observer:packet(success, 2, settings);
    observer:packet(receipt(item), 3, settings);
    eq(balance(core, key), (orb.seal == 'beastmen' and 120 or 150) - orb.cost, orb.name .. ' receipt cannot spend twice');
    eq(balance(core, orb.seal == 'beastmen' and 'kindred_seals' or 'beastmen_seals'),
        orb.seal == 'beastmen' and 150 or 120, orb.name .. ' leaves the other seal type alone');
end

local orb = rules.orbs[1131];
assert(orb and orb.seal == 'beastmen', 'Star Orb source fixture');
local function no_purchase(name, prepare, confirm_at)
    local current, source = fixture();
    seed(source);
    prepare(source, current);
    source:packet(receipt(1131), confirm_at or 3, settings);
    eq(balance(current, 'beastmen_seals'), 120, name);
end
no_purchase('Cancelled menu does not spend seals', function(source) source:outgoing(final(4294967295), 1); end);
no_purchase('Never mind does not spend seals', function(source) source:outgoing(final(0), 1); end);
no_purchase('A menu update is not an orb purchase', function(source) source:outgoing(final(orb.option, { mode = 1 }), 1); end);
no_purchase('Wrong NPC choice does not spend seals', function(source) source:outgoing(final(orb.option, { target = shami.id + 1 }), 1); end);
no_purchase('Wrong zone choice does not spend seals', function(source) source:outgoing(final(orb.option, { zone = shami.zone + 1 }), 1); end);
no_purchase('Wrong event choice does not spend seals', function(source) source:outgoing(final(orb.option, { event = shami.event + 1 }), 1); end);
no_purchase('Injected choice does not spend seals', function(source)
    local outgoing = final(orb.option); outgoing.injected = true; source:outgoing(outgoing, 1);
end);
no_purchase('Blocked choice does not spend seals', function(source)
    local outgoing = final(orb.option); outgoing.blocked = true; source:outgoing(outgoing, 1);
end);
no_purchase('Truncated choice does not spend seals', function(source)
    local outgoing = final(orb.option); outgoing.size = 18; outgoing.data = outgoing.data:sub(1, 18); source:outgoing(outgoing, 1);
end);
no_purchase('Old dialogue cannot authorize a purchase', function(source) source:outgoing(final(orb.option), 301); end, 302);
no_purchase('Receipt after the confirmation window does not spend seals', function(source) source:outgoing(final(orb.option), 1); end, 11.1);
no_purchase('New menu clears the pending purchase', function(source)
    source:outgoing(final(orb.option), 1); seed(source, 120, 90, 2);
end);
no_purchase('Another NPC menu clears the pending purchase', function(source)
    source:outgoing(final(orb.option), 1); source:packet(menu(shami.event, 120, 90, shami.id + 1), 2, settings);
end);
no_purchase('Inventory full clears the pending purchase', function(source)
    source:outgoing(final(orb.option), 1); source:packet(receipt(1131, 0, nil, shami.inventory_full), 2, settings);
end);

core, observer = fixture();
seed(observer);
observer:outgoing(final(orb.option), 1);
observer:packet(receipt(1131, 0, 9999), 2, settings);
eq(balance(core, 'beastmen_seals'), 120, 'Another player obtaining an orb is not our purchase');
observer:packet(receipt(1130), 2.1, settings);
eq(balance(core, 'beastmen_seals'), 120, 'Another item cannot confirm the selected orb');
invalid = receipt(1131); invalid.injected = true;
observer:packet(invalid, 2.2, settings);
eq(balance(core, 'beastmen_seals'), 120, 'Injected item receipt ignored');
invalid = receipt(1131); invalid.blocked_original = true;
observer:packet(invalid, 2.3, settings);
eq(balance(core, 'beastmen_seals'), 120, 'Blocked original receipt ignored');
invalid = receipt(1131); invalid.size = 26; invalid.data = invalid.data:sub(1, 26);
observer:packet(invalid, 2.4, settings);
eq(balance(core, 'beastmen_seals'), 120, 'Truncated item receipt ignored');
observer:packet(receipt(1131), 3, settings);
eq(balance(core, 'beastmen_seals'), 120 - orb.cost, 'Matching ordinary receipt still confirms the purchase');
currency(observer, 120 - orb.cost, 90, 4);
eq(balance(core, 'beastmen_seals'), 120 - orb.cost, 'Later currency snapshot is absolute');

core, observer = fixture();
seed(observer);
observer:outgoing(final(orb.option), 1);
currency(observer, 120 - orb.cost, 90, 2);
observer:packet(receipt(1131), 3, settings);
eq(balance(core, 'beastmen_seals'), 120 - orb.cost, 'Currency snapshot before the receipt cannot debit twice');
core, observer = fixture();
seed(observer);
observer:outgoing(final(orb.option), 1);
currency(observer, 120, 90, 2);
eq(balance(core, 'beastmen_seals'), 120, 'A delayed pre-purchase currency response is still the old balance');
observer:packet(receipt(1131), 3, settings);
eq(balance(core, 'beastmen_seals'), 120 - orb.cost, 'Confirmed purchase updates after a delayed pre-purchase currency response');
core, observer = fixture();
seed(observer);
observer:outgoing(final(orb.option), 1);
currency(observer, 99, 90, 2);
observer:packet(receipt(1131), 3, settings);
eq(balance(core, 'beastmen_seals'), 99, 'An unexpected newer balance stays authoritative over the menu calculation');
core, observer = fixture();
seed(observer);
observer:outgoing(final(orb.option), 1);
observer:context(1001, shami.zone + 1, 2, settings, true);
observer:context(1001, shami.zone, 3, settings, true);
observer:packet(receipt(1131), 4, settings);
eq(balance(core, 'beastmen_seals'), 120, 'Zone change clears a pending purchase');
core, observer = fixture();
seed(observer);
observer:outgoing(final(orb.option), 1);
observer:context(2002, shami.zone, 2, settings, false);
observer:packet(receipt(1131, 0, 2002), 3, settings);
eq(balance(core, 'beastmen_seals'), nil, 'Character change cannot inherit a pending purchase');
core, observer = fixture();
seed(observer);
observer:outgoing(final(orb.option), 1);
observer:packet(packet(0x00B, 4), 2, settings);
observer:packet(receipt(1131), 3, settings);
eq(balance(core, 'beastmen_seals'), 120, 'Normal logout packet clears a pending purchase');
observer:outgoing(final(orb.option), 4);
observer:packet(receipt(1131), 5, settings);
eq(balance(core, 'beastmen_seals'), 120, 'Logout also clears the menu that authorized purchases');
core, observer = fixture();
seed(observer);
observer:outgoing(final(orb.option), 1);
local logout = packet(0x00B, 4); logout.injected = true;
observer:packet(logout, 2, settings);
observer:packet(receipt(1131), 3, settings);
eq(balance(core, 'beastmen_seals'), 120 - orb.cost, 'Injected logout cannot interrupt normal confirmation');

for _, row in ipairs({ { item = 1126, key = 'beastmen_seals', offset = 2, quantity = 3, initial = 120 },
    { item = 1127, key = 'kindred_seals', offset = 1, quantity = 1, initial = 90 } }) do
    core, observer = fixture();
    seed(observer);
    observer:outgoing(final((row.quantity + 1) * 256 - row.offset), 1);
    eq(balance(core, row.key), row.initial, 'Withdrawal choice alone does not remove stored seals');
    observer:packet(receipt(row.item, row.quantity + 1), 1.5, settings);
    eq(balance(core, row.key), row.initial, 'A different withdrawal quantity cannot confirm the transaction');
    observer:packet(receipt(row.item, row.quantity), 2, settings);
    eq(balance(core, row.key), row.initial - row.quantity, 'Confirmed withdrawal moves seals out of storage');
    observer:packet(receipt(row.item, row.quantity), 3, settings);
    eq(balance(core, row.key), row.initial - row.quantity, 'Withdrawal receipt cannot spend twice');
end

local service = runtime.new(MOCK_INSTALL_PATH .. '/config/addons/momentum/', { memory = memory, clock = function() return 1800000000; end });
service:sample({ valid = true, id = 1001, zone = shami.zone }, 0, settings);
seed(service.observer);
service:outgoing(final(orb.option), 1, settings);
service:detach(2);
service:sample({ valid = true, id = 1001, zone = shami.zone }, 3, settings);
service:packet(receipt(1131), 4, settings);
eq(service.core.currencies.beastmen_seals.value, 120, 'Logging out and reloading cannot replay a pending purchase');
eq(#MOCK.commands, 0, 'Seal tracking sends no gameplay or currency requests');
return { count = count };
