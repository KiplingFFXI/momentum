local events = require('core.events');
local client = require('core.events_client');
local rules = require('data.event_rules');
local count = 0;
local function eq(a, b, name) count = count + 1; assert(a == b, name .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); end
local function packet(id, size, fields)
    local data = MOCK.bytes(size);
    for _, row in ipairs(fields or {}) do MOCK.put(data, row[1], row[2], row[3]); end
    return MOCK.packet(id, data);
end
local function menu(zone, target, event, values)
    local fields = { { 4, 4, target }, { 42, 2, zone }, { 44, 2, event } };
    for i, value in ipairs(values or {}) do fields[#fields + 1] = { 4 + i * 4, 4, value }; end
    return packet(0x034, 52, fields);
end
local utc, settings, owned, reads, key_reads = 1800000000, { events = { enabled = true } }, {}, 0, 0;
local inventory = {
    GetContainerCountMax = function() return 80; end,
    GetContainerItem = function() reads = reads + 1; return nil; end,
    GetTreasurePoolItem = function() return nil; end,
};
local player = { HasKeyItem = function(_, id) key_reads = key_reads + 1; return owned[id] == true; end,
    GetStatusIcons = function() return { [0] = 254 }; end };
local memory = { GetInventory = function() return inventory; end, GetPlayer = function() return player; end };
local core = events.new();
local observer = client.new(core, { memory = memory, clock = function() return utc; end });
local zone, index;
for z, area in pairs(rules.areas) do for i, row in pairs(area.battles or {}) do if row.kind == 'bcnm' then zone, index = z, i; break; end end if zone then break; end end
observer:sample({ valid = true, id = 1001, zone = zone }, 0, settings);
local initial, key_initial = reads, key_reads;
for i = 1, 600 do observer:sample({ valid = true, id = 1001, zone = zone }, i / 60, settings); end
eq(reads, initial, 'Stable frames do not scan inventory');
eq(key_reads, key_initial, 'Stable frames do not rescan key items');
eq(core:view(0, utc, settings).active, false, 'Arena alone does not invent an entered fight');
observer:packet(menu(zone, 123, 32000), 10, settings);
observer:packet(packet(0x075, 40, { { 4, 4, 1 }, { 12, 4, 1234 }, { 36, 1, 1 } }), 10, settings);
eq(core:view(10, utc, settings).active, false, 'Timer waits for battlefield identity');
observer:packet(packet(0x05C, 36, { { 4, 4, 2 }, { 8, 4, index }, { 16, 4, 90 } }), 10, settings);
eq(core:view(10, utc, settings).active, true, 'Successful native entry identifies fight');
eq(core:view(10, utc, settings).remaining, 1234, 'Native remaining duration retained');
eq(core:view(10, utc, settings).record, 90, 'Entry record retained');
observer:packet(menu(zone, 1001, 32001, { 1, 90, 3, 70, zone, index, 0 }), 20, settings);
eq(core:view(20, utc, settings).status, 'Won', 'Normal result confirms victory');
eq(core:view(20, utc, settings).elapsed, 70, 'Reported elapsed used');
local sagheera = rules.npcs.sagheera;
observer:sample({ valid = true, id = 1001, zone = sagheera.zone }, 30, settings);
observer:packet(menu(sagheera.zone, sagheera.id, sagheera.event, { 0, 0, 0, 0, utc + 500 - 1009882800, 1, 0, 123 }), 30, settings);
local view = core:view(30, utc, settings);
eq(view.currencies.ancient_beastcoins.value, 123, 'Sagheera stored coins');
local limbus;
for _, row in ipairs(view.cooldowns) do if row.key == 'limbus' then limbus = row; end end
eq(limbus.remaining, 500, 'Sagheera unusual timestamp conversion');
observer:packet(menu(sagheera.zone, sagheera.id + 1, sagheera.event, { 0, 0, 0, 0, 2147483649, 1, 0, 0 }), 31, settings);
eq(core.cooldowns.limbus.ready_at, utc + 500, 'Other NPC cannot change cooldown');
local npc_zone, npc_id, npc_info;
for z, npcs in pairs(rules.enm_npcs) do for id, info in pairs(npcs) do npc_zone, npc_id, npc_info = z, id, info; break; end if npc_zone then break; end end
local npc_event; for event in pairs(npc_info.events) do npc_event = event; break; end
observer:sample({ valid = true, id = 1001, zone = npc_zone }, 40, settings);
observer:packet(menu(npc_zone, npc_id, npc_event), 40, settings);
observer:outgoing(packet(0x05B, 20, { { 4, 4, npc_id }, { 8, 4, 8 }, { 14, 2, 1 }, { 18, 2, npc_event } }), 40);
observer:packet(packet(0x05C, 36, { { 4, 4, 0 }, { 8, 4, utc + 800 - 1009810800 } }), 40, settings);
eq(core.cooldowns['enm:8'].ready_at, utc + 800, 'Normal ENM dialogue supplies selected group ready time');
eq(core.cooldowns['enm:8'].estimated, false, 'NPC deadline confirmed');
owned[rules.enm_groups[8].key_items[1]] = true;
observer:packet(packet(0x055, 8), 41, settings);
observer:sample({ valid = true, id = 1001, zone = npc_zone }, 41, settings);
eq(core.cooldowns['enm:8'].ready_at, utc + rules.enm_groups[8].duration, 'Observed acquisition starts ENM cooldown');
owned[rules.enm_groups[8].key_items[1]] = false;
observer:packet(packet(0x055, 8), 42, settings);
observer:sample({ valid = true, id = 1001, zone = npc_zone }, 42, settings);
eq(core.cooldowns['enm:8'].ready_at, utc + rules.enm_groups[8].duration, 'Consumption does not restart ENM cooldown');
local currency = packet(0x113, 192, { { 16, 2, 20 }, { 18, 2, 30 }, { 26, 2, 40 }, { 128, 4, 50 }, { 190, 1, 2 } });
observer:packet(currency, 43, settings);
eq(core.currencies.beastmen_seals.value, 20, 'Beastmen seals standard packet');
eq(core.currencies.kindred_seals.value, 30, 'Kindred seals standard packet');
eq(core.currencies.assault_tags.value, 2, 'Stored tags standard packet');
eq(core.currencies.assault_leujaoam.value, 50, 'Assault points standard packet');
for _, id in ipairs({ 0x075, 0x034, 0x05C, 0x113, 0x00A, 0x0D2, 0x0D3, 0x02A }) do
    eq(client.parse(packet(id, 4)), nil, 'Truncated packet rejected');
end
local injected = packet(0x075, 40, { { 4, 4, 1 }, { 12, 4, 100 }, { 36, 1, 1 } });
injected.injected = true;
eq(client.parse(injected), nil, 'Injected event ignored');
local delayed_core = events.new();
local delayed = client.new(delayed_core, { memory = memory, clock = function() return utc; end });
delayed:sample({ valid = true, id = 1001, zone = zone }, 0, settings);
delayed:packet(menu(zone, 123, 32000), 3, settings);
local timer = packet(0x075, 40, { { 4, 4, 1 }, { 12, 4, 900 }, { 36, 1, 1 } });
timer.received_at = 0;
delayed:packet(timer, 3, settings);
local update = packet(0x05C, 36, { { 4, 4, 2 }, { 8, 4, index } });
update.received_at = 0;
delayed:packet(update, 3, settings);
eq(delayed_core:view(3, utc, settings).remaining, 897, 'Startup replay subtracts queue delay once');
local limbus_zone, limbus_index;
for z, area in pairs(rules.areas) do for i, row in pairs(area.battles or {}) do if row.kind == 'limbus' then limbus_zone, limbus_index = z, i; break; end end if limbus_zone then break; end end
local area = rules.areas[limbus_zone];
delayed:packet(packet(0x00A, 60, { { 4, 4, 1001 }, { 48, 2, limbus_zone }, { 56, 4, utc } }), 4, settings);
delayed:packet(menu(limbus_zone, 123, 32000), 4, settings);
delayed:packet(packet(0x05C, 36, { { 4, 4, 2 }, { 8, 4, limbus_index } }), 4, settings);
eq(delayed_core.cooldowns.limbus, nil, 'Registration alone cannot start entry cooldown');
delayed:packet(packet(0x02A, 28, { { 4, 4, 1001 }, { 12, 4, limbus_index }, { 26, 2, area.messages.ENTERING_THE_BATTLEFIELD_FOR } }), 4, settings);
eq(delayed_core.cooldowns.limbus.ready_at, utc + rules.cooldowns.limbus.duration, 'Witnessed Limbus entry starts cooldown');
delayed:packet(packet(0x02A, 28, { { 4, 4, 1001 }, { 20, 4, 30 }, { 26, 2, area.messages.TIME_LIMIT_FOR_THIS_BATTLE_IS } }), 4, settings);
eq(delayed_core:view(4, utc, settings).remaining, nil, 'Advertised limit does not restart a late-join countdown');
delayed:packet(packet(0x02A, 28, { { 4, 4, 1001 }, { 8, 4, 17 }, { 26, 2, area.messages.TIME_LEFT } }), 4, settings);
eq(delayed_core:view(4, utc, settings).remaining, 1020, 'Normal remaining message confirms actual time');
eq(delayed_core:view(4, utc, settings).time_estimated, true, 'Whole-minute entry timer is an estimate');
local current = packet(0x056, 40, { { 20, 4, 21 }, { 36, 2, 0x00C0 } });
delayed:packet(current, 5, settings);
eq(delayed_core:view(5, utc + 1, settings).assault_current, 21, 'Current mission normal quest log');
delayed:packet(packet(0x056, 40, { { 20, 4, 2 ^ 21 }, { 36, 2, 0x0080 } }), 5, settings);
eq(delayed_core:view(5, utc + 1, settings).assault_completed[21], true, 'Assault completion normal quest log');
delayed:packet(packet(0x056, 40, { { 20, 4, 0 }, { 36, 2, 0x00C0 } }), 6, settings);
eq(delayed_core.assault_report, nil, 'Normal report clears reminder');
owned[rules.enm_groups[8].key_items[1]] = true;
observer:sample({ valid = true, id = 2002, zone = npc_zone }, 44, settings);
eq(core.cooldowns['enm:8'], nil, 'Other character starts a fresh key-item baseline');
local single_zone, single_index, single_info, boss;
for z, candidate in pairs(rules.areas) do
    for i, row in pairs(candidate.battles or {}) do
        if row.kind == 'limbus' and row.floor_count == 1 and row.objective.type == 'kills'
            and row.objective.mobs and row.mob_floors and next(row.mob_floors) == nil then
            for mob, name in pairs(candidate.mobs) do
                if row.objective.mob_ids and row.objective.mob_ids[mob] or not row.objective.mob_ids and row.objective.mobs[name] then boss = mob; break; end
            end
            if boss then single_zone, single_index, single_info = z, i, row; break; end
        end
    end
    if single_zone then break; end
end
assert(single_info, 'Single-floor objective fixture');
core:context(2002, single_zone, 45, utc, true);
core:begin(single_zone, single_index, 45, utc, false);
assert(boss, 'Catalog boss ID');
eq(core:death(boss, 45, utc), true, 'Empty floor map does not reject a required boss');
eq(core:view(45, utc, settings).kills, 1, 'Single-floor boss counted');
delayed:packet(menu(limbus_zone, 1001, 32001, { 0, 0, 0, 0, limbus_zone, limbus_index }), 7, settings);
eq(delayed_core:view(7, utc + 3, settings).status, 'Won', 'Limbus normal result confirms clear');
eq(delayed_core:view(7, utc + 3, settings).elapsed, 3, 'Limbus result uses observed time, not a missing zero parameter');
delayed_core:finish(8, utc + 4);
delayed_core:begin(limbus_zone, limbus_index, 8, utc + 4, true);
eq(delayed_core:view(8, utc + 4, settings).personal_best, nil, 'Observed Limbus time cannot become a confirmed personal best');
delayed:sample({ valid = true, id = 1001, zone = limbus_zone }, 8, settings);
settings.events.enabled = false;
delayed:sample({ valid = true, id = 1001, zone = limbus_zone }, 9, settings);
settings.events.enabled = true;
delayed:sample({ valid = true, id = 1001, zone = limbus_zone }, 10, settings);
eq(delayed_core:view(10, utc + 6, settings).partial, true, 'Disabled observations make resumed run partial');
return { count = count };
