local rules = require('data.event_rules');
local packets = require('core.packets');
local dyna_client = require('core.dynamis_client');
local bit = require('bit');
local client = {};
local methods = {};
methods.__index = methods;
local EPOCH = 1009810800;
local relevant_packets = { [0x00A] = true, [0x00B] = true, [0x00E] = true, [0x01D] = true, [0x01E] = true, [0x01F] = true,
    [0x020] = true, [0x029] = true, [0x02A] = true, [0x032] = true, [0x034] = true, [0x055] = true, [0x056] = true,
    [0x05C] = true, [0x075] = true, [0x0D2] = true, [0x0D3] = true, [0x113] = true };
local run_packets = { [0x00E] = true, [0x029] = true, [0x0D2] = true, [0x0D3] = true };
local seal_fields = { beastmen = 'beastmen_seals', kindred = 'kindred_seals' };
local shami_orbs = {};
for item, orb in pairs(rules.orbs or {}) do
    shami_orbs[orb.option] = { item = item, field = seal_fields[orb.seal], count = 1, cost = orb.cost };
end

local function uint(data, offset, size)
    if type(data) ~= 'string' or #data < offset + size then return nil; end
    local result = 0;
    for i = size - 1, 0, -1 do result = result * 256 + data:byte(offset + i + 1); end
    return result;
end

local function call(object, name, ...)
    if not object or type(object[name]) ~= 'function' then return nil; end
    local ok, result = pcall(object[name], object, ...);
    if ok then return result; end
end

function client.parse(event)
    if not packets.valid(event, 4) then return nil; end
    local id, data = event.id, event.data;
    if id == 0x075 and packets.valid(event, 40) then
        local duration, mode = uint(data, 12, 4), uint(data, 4, 4);
        if bit.band(uint(data, 36, 1), 1) ~= 0 and duration <= 86400 and mode == 1 then
            return 'timer', { seconds = duration };
        end
    elseif id == 0x032 and packets.valid(event, 20) then
        return 'menu', { target = uint(data, 4, 4), zone = uint(data, 10, 2), event = uint(data, 12, 2), values = {} };
    elseif id == 0x034 and packets.valid(event, 48) then
        local result = { target = uint(data, 4, 4), zone = uint(data, 42, 2), event = uint(data, 44, 2), values = {} };
        for i = 1, 8 do result.values[i] = uint(data, 4 + i * 4, 4); end
        return 'menu', result;
    elseif id == 0x05C and packets.valid(event, 36) then
        local result = { values = {} };
        for i = 1, 8 do result.values[i] = uint(data, i * 4, 4); end
        return 'update', result;
    elseif id == 0x113 and packets.valid(event, 192) then
        return 'currency', { beastmen_seals = uint(data, 16, 2), kindred_seals = uint(data, 18, 2),
            ancient_beastcoins = uint(data, 26, 2), assault_leujaoam = uint(data, 128, 4),
            assault_mamool = uint(data, 132, 4), assault_lebros = uint(data, 136, 4),
            assault_periqia = uint(data, 140, 4), assault_ilrusi = uint(data, 144, 4),
            assault_tags = uint(data, 190, 1) };
    elseif id == 0x056 and packets.valid(event, 40) then
        local port = uint(data, 36, 2);
        if port == 0x00C0 then return 'assault_current', { mission = uint(data, 20, 4) };
        elseif port == 0x0080 then
            local completed = {};
            for mission in pairs(rules.assault_missions or {}) do
                completed[mission] = bit.band(uint(data, 20 + math.floor(mission / 32) * 4, 4), bit.lshift(1, mission % 32)) ~= 0;
            end
            return 'assault_completed', completed;
        end
    elseif id == 0x02A and packets.valid(event, 28) then
        return 'message', { actor = uint(data, 4, 4), message = bit.band(uint(data, 26, 2), 0x7FFF),
            first = uint(data, 8, 4), second = uint(data, 12, 4), third = uint(data, 16, 4), fourth = uint(data, 20, 4) };
    elseif id == 0x029 and packets.valid(event, 28)
        and bit.band(uint(data, 24, 2), 0x7FFF) == ((rules.basic_messages or {}).TIME_LEFT or 202) then
        return 'remaining_basic', { actor = uint(data, 4, 4), target = uint(data, 8, 4), seconds = uint(data, 12, 4) };
    elseif id == 0x055 then return 'key_items', {};
    elseif id == 0x01D or id == 0x01E or id == 0x01F or id == 0x020 then return 'inventory', {}; end
    return dyna_client.parse(event);
end

function client.new(core, options)
    options = options or {};
    return setmetatable({ core = core, memory = options.memory or AshitaCore:GetMemoryManager(),
        server_clock = options.utc, local_clock = options.clock or os.time, resource = options.resource,
        inventory_dirty = true, ki_dirty = true, seen = {}, seen_order = {}, options = options }, methods);
end

function methods:utc(now)
    local current = self.server_clock and self.server_clock();
    if type(current) == 'number' and current > EPOCH then return current; end
    if self.server_utc and now >= self.server_at then return self.server_utc + now - self.server_at; end
    return self.local_clock();
end

function methods:context(id, zone, now, settings, observed)
    if type(id) ~= 'number' or id <= 0 or type(zone) ~= 'number' or zone <= 0 then return; end
    if self.id ~= id or self.zone ~= zone then
        local changed_character = self.id ~= id;
        self.id, self.zone, self.menu, self.pending_timer = id, zone, nil, nil;
        self.shami_pending = nil;
        self.inventory_dirty, self.ki_dirty, self.pool_seeded = true, true, false;
        self.ki_state, self.seen, self.seen_order = changed_character and {} or self.ki_state or {}, {}, {};
    end
    local enabled = not settings.events or settings.events.enabled ~= false;
    if self.enabled ~= nil and self.enabled ~= enabled and self.core.current then
        self.core.current.partial = true;
        self.core.pool = {};
        self.pool_seeded = false;
        self.core:change();
    end
    self.enabled = enabled;
    self.core:context(id, zone, now, self:utc(now), observed);
end

function methods:begin(index, now, partial, entered, delay)
    local area, utc = rules.areas[self.zone], self:utc(now) - (delay or 0);
    local info = area and area.battles and area.battles[index];
    if not self.enabled or not info then return false; end
    if not self.core:begin(self.zone, index, now, utc, partial) then return false; end
    if info.kind == 'limbus' and entered and not partial and not self.core.current.entry_witnessed then
        self.core:cooldown('limbus', 'Limbus entry', utc + rules.cooldowns.limbus.duration, utc, 'Observed Limbus entry', false);
        self.core.current.entry_witnessed = true;
    end
    if self.pending_timer and now - self.pending_timer.at <= 5 then
        self.core:timer(self.pending_timer.seconds - math.max(0, now - self.pending_timer.at), now, self:utc(now), false);
        self.pending_timer = nil;
    end
    return true;
end

function methods:inventory(now)
    if not self.inventory_dirty or self.inventory_at and now - self.inventory_at < 0.5 then return; end
    self.inventory_at = now;
    local inventory = call(self.memory, 'GetInventory');
    if not inventory then return; end
    local count = call(inventory, 'GetContainerCountMax', 0);
    if type(count) ~= 'number' or count <= 0 then return; end
    local values = {};
    for slot = 1, math.min(80, count) do
        local item = call(inventory, 'GetContainerItem', 0, slot);
        if item and type(item.Id) == 'number' and type(item.Count) == 'number' and item.Count > 0
            and (rules.items[item.Id] or rules.orbs[item.Id] or item.Id == 1126 or item.Id == 1127) then
            values[item.Id] = (values[item.Id] or 0) + item.Count;
        end
    end
    self.inventory_dirty = false;
    self.core.inventory_available = true;
    self.core:items(self.core.entry_items, values);
end

function methods:key_items(now)
    if not self.ki_dirty or self.ki_at and now - self.ki_at < 0.25 then return; end
    self.ki_at = now;
    local player = call(self.memory, 'GetPlayer');
    if not player or type(player.HasKeyItem) ~= 'function' then return; end
    local entries, utc = {}, self:utc(now);
    for name, id in pairs(rules.key_items or {}) do
        local owned = call(player, 'HasKeyItem', id);
        if type(owned) == 'boolean' then
            entries[#entries + 1] = { id = id, name = (rules.key_item_names or {})[id]
                or name:gsub('_', ' '):lower():gsub('^%l', string.upper), owned = owned, kind = 'key_item' };
            if owned and self.ki_state[id] == false then
                for group, info in pairs(rules.enm_groups or {}) do
                    for _, required in ipairs(info.key_items or {}) do
                        if required == id then
                            self.core:cooldown('enm:' .. group, info.name, utc + info.duration, utc, 'Observed key item obtained', true);
                        end
                    end
                end
            end
            self.ki_state[id] = owned;
        end
    end
    table.sort(entries, function(a, b) return a.id < b.id; end);
    self.ki_dirty = false;
    self.core:items(entries, self.core.inventory);
end

function methods:seed_pool(now)
    if self.pool_seeded or not self.core.current then return; end
    local inventory = call(self.memory, 'GetInventory');
    if not inventory then return; end
    self.pool_seeded = true;
    for slot = 0, 9 do
        local item = call(inventory, 'GetTreasurePoolItem', slot);
        if item and type(item.Id) == 'number' and item.Id > 0 and type(item.Count) == 'number' and item.Count > 0 then
            self.core:drop({ slot = slot, item_id = item.Id, count = item.Count, old = true }, now, self:utc(now));
        end
    end
end

function methods:sample(snapshot, now, settings)
    if not snapshot or not snapshot.valid then return; end
    self:context(snapshot.id, snapshot.zone, now, settings, false);
    if self.shami_pending and (now < self.shami_pending.at or now - self.shami_pending.at > 10) then self.shami_pending = nil; end
    if type(snapshot.zone_name) == 'string' then self.core.zone_name = snapshot.zone_name; end
    if not self.enabled then return; end
    local enabled = settings.display and settings.display.enabled or {};
    local inventory_wanted = self.core.current ~= nil or settings.window and settings.window.open and settings.window.tab == 'Events'
        or enabled.beastcoins_carried or enabled.beastmen_carried or enabled.kindred_carried;
    if inventory_wanted then self:inventory(now); end
    self:key_items(now);
    local area = rules.areas[self.zone];
    if self.core.resume then
        local player = call(self.memory, 'GetPlayer');
        local effects = call(player, 'GetStatusIcons') or call(player, 'GetBuffs');
        local confirmed = area and area.kind == 'assault';
        if effects then
            for slot = 0, 31 do if effects[slot] == 254 then confirmed = true; end end
        end
        self.core:resume_run(self.zone, now, self:utc(now), confirmed);
    end
    if self.core.current then
        self:seed_pool(now);
        self.core:position(snapshot.x, snapshot.y, snapshot.z);
        if self.core.current.kind ~= 'assault' and (not self.effect_at or now - self.effect_at >= 0.25) then
            self.effect_at = now;
            local player = call(self.memory, 'GetPlayer');
            local effects = call(player, 'GetStatusIcons') or call(player, 'GetBuffs');
            if effects then
                local present = false;
                for slot = 0, 31 do if effects[slot] == 254 then present = true; break; end end
                if present then self.core.current.native_seen = true;
                elseif self.core.current.native_seen then
                    self.core:finish(now, self:utc(now));
                    self.pool_seeded = false;
                end
            end
        end
    end
end

function methods:menu_values(menu, values, now)
    local utc, npcs = self:utc(now), rules.npcs or {};
    local shami = npcs.shami;
    if shami and menu.zone == shami.zone and menu.target == shami.id then
        local balances = {};
        if menu.event == shami.event and values[1] then
            balances.beastmen_seals, balances.kindred_seals = values[1] % 65536, math.floor(values[1] / 65536);
            menu.seals = balances;
        elseif menu.event == shami.deposit_event then
            for index, key in ipairs({ 'beastmen_seals', 'kindred_seals' }) do
                local total = values[index] and math.floor(values[index] / 65536) or 0;
                if total > 0 then balances[key] = total; end
            end
        elseif menu.event == shami.empty_event then balances.beastmen_seals, balances.kindred_seals = 0, 0; end
        if next(balances) then self.core:currency(balances, utc); end
    end
    local sagheera = npcs.sagheera;
    if sagheera and menu.zone == sagheera.zone and menu.target == sagheera.id and menu.event == sagheera.event then
        local stamp = values[5];
        if type(stamp) == 'number' then
            local ready = stamp >= 2147483648 and utc or stamp + 1009882800;
            self.core:cooldown('limbus', 'Limbus entry', ready, utc, 'Sagheera', false);
        end
        self.core:currency({ ancient_beastcoins = values[8] }, utc);
    end
    local rytaal = npcs.rytaal;
    if rytaal and menu.zone == rytaal.zone and menu.target == rytaal.id and menu.event == rytaal.event then
        self.core:currency({ assault_tags = values[2] }, utc);
        if values[5] and values[5] > 0 then
            self.core:cooldown('assault_tag', 'Next Assault tag', values[5] + EPOCH + 86400, utc, 'Rytaal', false);
        end
    end
end

function methods:outgoing(event, now)
    if not self.enabled or event.id ~= 0x05B or not packets.valid(event, 20) or not self.menu then return; end
    local menu, data = self.menu, event.data;
    if now < menu.at or now - menu.at > 300 or uint(data, 4, 4) ~= menu.target or uint(data, 18, 2) ~= menu.event then return; end
    local shami = (rules.npcs or {}).shami;
    if shami and menu.target == shami.id and menu.zone == shami.zone and self.zone == shami.zone
        and menu.event == shami.event and uint(data, 14, 2) == 0 and uint(data, 16, 2) == shami.zone then
        local option = uint(data, 8, 4);
        local chosen = shami_orbs[option];
        if not chosen and option >= 508 and option ~= 4294967295 then
            for family, offset in pairs(rules.seal_retrieval or {}) do
                if (option + offset) % 256 == 0 then
                    local quantity = (option + offset) / 256 - 1;
                    if quantity > 0 then chosen = { item = rules.seal_items[family], field = seal_fields[family], count = quantity, cost = quantity }; end
                    break;
                end
            end
        end
        local balance = chosen and menu.seals and menu.seals[chosen.field];
        if balance and balance >= chosen.cost then
            self.shami_pending = { item = chosen.item, field = chosen.field, count = chosen.count,
                before = balance, balance = balance - chosen.cost, id = self.id, at = event.received_at or now };
        end
    end
    local npc = (rules.enm_npcs[self.zone] or {})[menu.target];
    if npc and npc.events[menu.event] then
        local option = uint(data, 8, 4);
        self.enm_option = npc.options[option];
    end
    if uint(data, 14, 2) == 0 then self.menu = nil; end
end

function methods:shami_receipt(value, now)
    local pending, shami = self.shami_pending, (rules.npcs or {}).shami;
    if not pending or not shami then return false; end
    if self.id ~= pending.id or self.zone ~= shami.zone or now < pending.at or now - pending.at > 10 then
        self.shami_pending = nil; return false;
    end
    if value.actor ~= self.id or value.first ~= pending.item then return false; end
    if value.message == shami.inventory_full or value.message == shami.inventory_full + 1 then
        self.shami_pending = nil; return true;
    end
    local count = value.message == shami.item_obtained and 1
        or value.message == shami.item_obtained_count and value.second or nil;
    if count ~= pending.count then return false; end
    self.shami_pending = nil;
    self.core:currency({ [pending.field] = pending.balance }, self:utc(now));
    return true;
end

function methods:message(value, now, token, delay)
    local area, utc = rules.areas[self.zone], self:utc(now) - (delay or 0);
    if not area then return; end
    local text = area.messages or {};
    if value.actor ~= self.id and value.actor ~= 0 then return; end
    if value.message == text.ENTERING_THE_BATTLEFIELD_FOR then
        self:begin(value.second, now, false, true, delay);
        return;
    end
    if not self.core.current and area.kind == 'assault' then
        for index, info in pairs(area.battles) do
            if info.kind == 'assault' then self:begin(index, now, not self.core.zone_observed, false, delay); break; end
        end
    end
    local run = self.core.current;
    if not run then return; end
    if value.message == text.TIME_TO_COMPLETE or value.message == text.TIME_LIMIT_FOR_THIS_BATTLE_IS then
        -- The advertised limit can be repeated for a late join. It is not time remaining.
        return;
    elseif value.message == text.TIME_REMAINING_MINUTES or value.message == text.TIME_LEFT then
        self.core:timer(value.first * 60, now, utc, true);
    elseif value.message == text.TIME_REMAINING_SECONDS then
        self.core:timer(value.first, now, utc, true);
    elseif value.message == text.TIME_EXTENDED then
        self.core:extension(value.first, now, utc, token);
    elseif value.message == text.RUNE_UNLOCKED or value.message == text.RUNE_UNLOCKED_POS then
        self.core:objective('Rune of Release ready', true, now, utc, 'rune');
    elseif value.message == text.ASSAULT_POINTS_OBTAINED then
        self.core:points(value.first, now, utc, token);
        self.core:outcome(true, now, utc);
    elseif value.message == text.MISSION_FAILED or value.message == text.TIME_IN_THE_BATTLEFIELD_IS_UP then
        self.core:outcome(false, now, utc);
    elseif value.message == text.VORTEX_MATERIALIZES then
        self.core:objective('Vortex opened', false, now, utc, 'vortex:' .. tostring(run.floor or run.objective_count));
    elseif value.message == text.GATE_OPEN or value.message == text.GATE_OPENED then
        self.core:objective('Gate opened', false, now, utc, 'gate:' .. tostring(run.floor or run.objective_count));
    end
end

function methods:packet(event, now, settings)
    if not relevant_packets[event.id] or not self.core.current and run_packets[event.id] then return; end
    if event.id == 0x00B and packets.valid(event, 4) then self.shami_pending, self.menu = nil, nil; return; end
    if event.id ~= 0x00A and event.id ~= 0x055 and event.id ~= 0x056 and event.id ~= 0x113
        and event.id ~= 0x01D and event.id ~= 0x01E and event.id ~= 0x01F and event.id ~= 0x020
        and event.id ~= 0x032 and event.id ~= 0x034 and event.id ~= 0x05C
        and not (event.id == 0x02A and self.shami_pending) and not self.core.current and not rules.areas[self.zone] then return; end
    local kind, value = client.parse(event);
    if not kind then return; end
    local delay = type(event.received_at) == 'number' and now - event.received_at or 0;
    if delay < 0 or delay > 30 then return; end
    if kind == 'zone' then
        if value.utc > EPOCH then self.server_utc, self.server_at = value.utc, now - delay; end
        self:context(value.id, value.zone, now, settings, true);
        return;
    end
    if not self.enabled then return; end
    if kind == 'inventory' then self.inventory_dirty = true; return; end
    if kind == 'key_items' then self.ki_dirty = true; return; end
    local utc = self:utc(now);
    if kind == 'currency' then
        local pending = self.shami_pending;
        if pending and value[pending.field] ~= pending.before then self.shami_pending = nil; end
        self.core:currency(value, utc); return;
    end
    if kind == 'assault_current' then
        self.core.assault_current = value.mission;
        if value.mission == 0 then self.core.assault_report = nil; end
        self.core:change(); return;
    end
    if kind == 'assault_completed' then self.core.assault_completed = value; self.core:change(); return; end
    local token = tostring(event.id) .. ':' .. event.data:sub(1, math.min(#event.data, event.size));
    if self.seen[token] then return; end
    if #self.seen_order >= 256 then self.seen[table.remove(self.seen_order, 1)] = nil; end
    self.seen[token], self.seen_order[#self.seen_order + 1] = true, token;
    if kind == 'timer' then
        local seconds = math.max(0, value.seconds - delay);
        if self.core.current then self.core:timer(seconds, now, utc, false);
        else self.pending_timer = { seconds = seconds, at = now }; end
    elseif kind == 'remaining_basic' and value.actor == self.id and value.target == self.id then
        self.core:timer(math.max(0, value.seconds - delay), now, utc, true);
    elseif kind == 'menu' then
        if value.zone ~= self.zone then return; end
        self.shami_pending = nil;
        value.at, self.enm_option = now - delay, nil;
        self.menu = value;
        self:menu_values(value, value.values, now);
        if value.event == 32001 and self.core.current then
            local info = (rules.areas[self.zone].battles or {})[value.values[6]];
            if self.core.current.kind == 'limbus' or info and info.index == self.core.current.index then
                self.core:outcome(true, now, utc, self.core.current.kind ~= 'limbus' and value.values[4] or nil, value.values[2]);
            end
        elseif value.event == 32002 then self.core:outcome(false, now, utc); end
    elseif kind == 'update' and self.menu and now - self.menu.at <= 300 then
        local menu = self.menu;
        if menu.event == 32000 and value.values[1] == 2 then
            if self:begin(value.values[2], now, false, false, delay) and self.core.current then
                local record = value.values[4];
                if record and record > 0 and record <= 86400 then self.core.current.record = record; self.core:change(); end
            end
        end
        if self.enm_option and (rules.enm_npcs[self.zone] or {})[menu.target] then
            local info = rules.enm_groups[self.enm_option];
            local ready = value.values[2] and value.values[2] > 0 and value.values[2] + EPOCH or utc;
            if info and value.values[1] == 0 then self.core:cooldown('enm:' .. info.id, info.name, ready, utc, 'ENM timer NPC', false); end
        end
    elseif kind == 'message' then
        if not self:shami_receipt(value, now) then self:message(value, now, token, delay); end
    elseif kind == 'drop' or kind == 'lot' then self.core[kind](self.core, value, now, utc, token);
    elseif kind == 'death' then self.core:death(value.id, now, utc);
    elseif kind == 'spawn' then self.core:spawn(value.id, now); end
end

return client;
