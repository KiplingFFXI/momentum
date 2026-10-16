local packets = {};
local reward_messages = { [8] = 'exp', [253] = 'exp', [371] = 'lp', [372] = 'lp' };
local inventory_lengths = { [0x01E] = 10, [0x01F] = 12, [0x020] = 16 };

local function uint(data, offset, count)
    local result = 0;
    for i = count - 1, 0, -1 do result = result * 256 + data:byte(offset + i + 1); end
    return result;
end

local function bits(data, offset, count)
    if (offset + count > #data * 8) then return nil; end
    local result, weight = 0, 1;
    for i = 0, count - 1 do
        local at = offset + i;
        local value = math.floor(data:byte(math.floor(at / 8) + 1) / 2 ^ (at % 8)) % 2;
        result, weight = result + value * weight, weight * 2;
    end
    return result;
end

function packets.valid(event, minimum)
    return (type(event) == 'table' or type(event) == 'userdata') and type(event.data) == 'string'
        and type(event.size) == 'number' and event.size == event.size and event.size >= minimum
        and #event.data >= minimum and not event.blocked and not event.blocked_original
        and not event.injected and not event.is_injected;
end

function packets.zone_id(event)
    if (event.id == 0x00A and packets.valid(event, 8)) then return uint(event.data, 4, 4); end
end

function packets.inventory(event)
    local id = event.id;
    if id == 0x01D and packets.valid(event, 12) then
        local state, flags = uint(event.data, 4, 1), uint(event.data, 8, 4);
        if state > 1 then return nil; end
        return { ready = state == 1 or flags % 2 == 1 };
    end
    local minimum = inventory_lengths[id];
    if not minimum or not packets.valid(event, minimum) then return nil; end
    local bag, slot;
    if id == 0x01E then
        bag, slot = uint(event.data, 8, 1), uint(event.data, 9, 1);
    elseif id == 0x01F then
        if uint(event.data, 8, 2) ~= 65535 then return nil; end
        bag, slot = uint(event.data, 10, 1), uint(event.data, 11, 1);
    else
        if uint(event.data, 12, 2) ~= 65535 then return nil; end
        bag, slot = uint(event.data, 14, 1), uint(event.data, 15, 1);
    end
    if bag ~= 0 or slot ~= 0 then return nil; end
    local balance = uint(event.data, 4, 4);
    if balance > 999999999 then return nil; end
    return { balance = balance, baseline = id == 0x020 };
end

function packets.reward_candidate(event, player_id)
    if (not player_id or player_id == 0) then return false; end
    if (event.id == 0x02D and packets.valid(event, 28)) then
        local amount = uint(event.data, 16, 4);
        return uint(event.data, 4, 4) == player_id and uint(event.data, 8, 4) == player_id
            and reward_messages[uint(event.data, 24, 2)] ~= nil and amount > 0 and amount <= 2147483647;
    end
    -- Only this player's completed item actions can carry EXP or an observed item use.
    return event.id == 0x028 and packets.valid(event, 24)
        and uint(event.data, 5, 4) == player_id and bits(event.data, 82, 4) == 5;
end

-- The receive-buffer address distinguishes identical rewards in the same packet batch.
local function identity(event, suffix)
    if (event.data_raw == nil) then return nil; end
    return tostring(event.data_raw) .. ':' .. event.data:sub(1, 4) .. ':' .. tostring(suffix or 0);
end

function packets.food_end(event, player_id)
    if (not player_id or player_id == 0 or event.id ~= 0x029 or not packets.valid(event, 28)) then return nil; end
    local actor, target = uint(event.data, 4, 4), uint(event.data, 8, 4);
    local effect, message = uint(event.data, 12, 4), uint(event.data, 24, 2);
    if (actor ~= player_id or target ~= player_id or effect ~= 251 or message ~= 206) then return nil; end
    return { actor_id = actor, target_id = target, effect = effect, message = message, token = identity(event) };
end

function packets.dedication_end(event, player_id)
    if (not player_id or player_id == 0 or event.id ~= 0x029 or not packets.valid(event, 28)) then return nil; end
    local actor, target = uint(event.data, 4, 4), uint(event.data, 8, 4);
    local effect, message = uint(event.data, 12, 4), uint(event.data, 24, 2);
    if (actor ~= player_id or target ~= player_id or effect ~= 249 or message ~= 206) then return nil; end
    return { actor_id = actor, target_id = target, effect = effect, message = message, token = identity(event) };
end

function packets.no_exp(event, player_id)
    if (not player_id or player_id == 0 or event.id ~= 0x029 or not packets.valid(event, 28)) then return nil; end
    if (uint(event.data, 4, 4) ~= player_id or uint(event.data, 8, 4) ~= player_id) then return nil; end
    local message = uint(event.data, 24, 2);
    local reason = ({ [37] = 'distance', [545] = 'sync_target' })[message];
    if (reason) then return { reason = reason, actor_id = player_id, target_id = player_id, token = identity(event) }; end
end

function packets.item_use(event, player_id)
    if (not player_id or player_id == 0 or event.id ~= 0x028 or not packets.valid(event, 35)) then return nil; end
    local data = event.data:sub(1, math.min(#event.data, event.size));
    if (bits(data, 40, 32) ~= player_id or bits(data, 82, 4) ~= 5 or bits(data, 72, 6) ~= 1
        or bits(data, 150, 32) ~= player_id or bits(data, 182, 4) ~= 1) then return nil; end
    local item_id = bits(data, 86, 32);
    local message = bits(data, 230, 10);
    if (not item_id or item_id < 1 or item_id > 65535 or (message ~= 0 and message ~= 28)
        or bits(data, 186, 3) ~= 0
        or bits(data, 271, 1) ~= 0 or bits(data, 272, 1) ~= 0) then return nil; end
    return { id = player_id, item_id = item_id, token = identity(event) };
end

function packets.awards(event, player_id)
    if (not player_id or player_id == 0) then return {}; end
    if (event.id == 0x02D and packets.valid(event, 28)) then
        if (uint(event.data, 4, 4) ~= player_id or uint(event.data, 8, 4) ~= player_id) then return {}; end
        local message = uint(event.data, 24, 2);
        local kind = reward_messages[message];
        if (kind == nil) then return {}; end
        local amount = uint(event.data, 16, 4);
        if (amount == 0 or amount > 2147483647) then return {}; end
        return { { kind = kind, amount = amount, chain = uint(event.data, 20, 4), source = 'battle',
            token = identity(event), message = message } };
    end
    if (event.id ~= 0x028 or not packets.valid(event, 24)) then return {}; end
    local data = event.data:sub(1, math.min(#event.data, event.size));
    if (bits(data, 40, 32) ~= player_id or bits(data, 82, 4) ~= 5) then return {}; end
    local targets = bits(data, 72, 6);
    if (targets == nil or targets > 16) then return {}; end
    local result, offset = {}, 150;
    for _ = 1, targets do
        local target, count = bits(data, offset, 32), bits(data, offset + 32, 4);
        if (target == nil or count == nil or count > 8) then return {}; end
        offset = offset + 36;
        for _ = 1, count do
            local message, amount = bits(data, offset + 44, 10), bits(data, offset + 27, 17);
            if (message == nil or amount == nil or bits(data, offset + 85, 1) == nil) then return {}; end
            if (target == player_id and message == 105 and amount > 0) then
                result[#result + 1] = { kind = 'exp', amount = amount, source = 'item', token = identity(event, offset) };
            end
            local extra = bits(data, offset + 85, 1);
            offset = offset + 86 + (extra == 1 and 37 or 0);
            local reaction = bits(data, offset, 1);
            if (reaction == nil) then return {}; end
            offset = offset + 1 + (reaction == 1 and 34 or 0);
            if (offset > #data * 8) then return {}; end
        end
    end
    return result;
end

return packets;
