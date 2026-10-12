local player = {};
local memory = AshitaCore:GetMemoryManager();
local stats, party = memory:GetPlayer(), memory:GetParty();
local bit = require('bit');
local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG',
    'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };
local event_flag, interface, focus_slot, time_struct = 0, 0, 0, 0;
local waiting, expected_id = false, nil;

local function truth(value) return value == true or value == 1; end

local function pointer(pattern, offset, extra)
    local match = ashita.memory.find('FFXiMain.dll', 0, pattern, offset or 0, 0);
    if (not match or match == 0) then return 0; end
    return ashita.memory.read_uint32(match + (extra or 0)) or 0;
end

function player.load()
    event_flag = pointer('A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3', 0, 1);
    interface = pointer('8B4424046A016A0050B9????????E8????????F6D81BC040C3', 0, 10);
    focus_slot = pointer('8B480C85C974??8B510885D274??3B05', 16, 0);
    if (focus_slot ~= 0 and focus_slot ~= interface + 0x54) then interface, focus_slot = 0, 0; end
    local slot = pointer('8B0D????????8B410C8B49108D04808D04808D04808D04C1C3', 2, 0);
    time_struct = slot ~= 0 and ashita.memory.read_uint32(slot) or 0;
end

function player.on_zone(id)
    waiting, expected_id = true, id;
end

function player.on_status()
    waiting = false;
end

function player.id() return expected_id or party:GetMemberServerId(0); end

function player.typing()
    return bit.band(AshitaCore:GetChatManager():IsInputOpen(), 1) ~= 0;
end

function player.hidden(visibility)
    local entity = GetPlayerEntity();
    if (visibility.event and ((event_flag ~= 0 and ashita.memory.read_uint8(event_flag) == 1)
        or (event_flag == 0 and entity ~= nil and entity.StatusServer == 4))) then return true; end
    if (visibility.game_ui and interface ~= 0 and ashita.memory.read_uint8(interface + 0xB4) == 1) then return true; end
    if (visibility.map and focus_slot ~= 0) then
        local menu = ashita.memory.read_uint32(focus_slot);
        if (menu ~= 0) then
            local header = ashita.memory.read_uint32(menu + 4);
            if (header ~= 0 and bit.band(ashita.memory.read_uint32(header + 0x4E), 0xFFFFFF) == 0x70616D) then return true; end
        end
    end
    return false;
end

function player.capabilities()
    return { map = focus_slot ~= 0, game_ui = interface ~= 0, status_time = time_struct ~= 0 };
end

function player.utc()
    if (time_struct == 0) then return nil; end
    local value = ashita.memory.read_uint32(time_struct + 0x0C);
    if (type(value) == 'number' and value > 1009810800) then return value; end
end

local function effect_seconds(raw, utc)
    if (type(raw) ~= 'number' or raw == 0 or raw == 0x7FFFFFFF or not utc) then return nil; end
    local ticks = raw - ((utc - 0x3C307D70) * 60);
    while (ticks < -2147483648) do ticks = ticks + 4294967296; end
    if (ticks >= 0 and ticks <= 604800 * 60) then return ticks / 60; end
end

function player.read()
    local entity = GetPlayerEntity();
    local id, job = party:GetMemberServerId(0), stats:GetMainJob();
    if (type(job) == 'number' and job > #jobs) then return { valid = false, unsupported_job = true }; end
    local needed, level = stats:GetExpNeeded(), stats:GetJobLevel(job);
    if (entity == nil or waiting or truth(stats:GetIsZoning()) or id == 0 or job == 0 or needed == 0
        or not level or level == 0 or (expected_id ~= nil and id ~= expected_id)) then return { valid = false }; end
    expected_id = nil;
    local status = entity.StatusServer;
    local merit_cap = stats:GetMeritPointsMax();
    if type(merit_cap) ~= 'number' or merit_cap ~= merit_cap or merit_cap <= 0 or merit_cap >= math.huge
        or merit_cap ~= math.floor(merit_cap) then merit_cap = nil; end
    -- LP, stored merits and capacity arrive together in the client's merit packet.
    local snapshot = { valid = true, id = id, job = job, job_name = jobs[job] or tostring(job),
        level = level, effective_level = stats:GetMainJobLevel(), zone = party:GetMemberZone(0),
        exp = stats:GetExpCurrent(), exp_needed = needed, lp = merit_cap and stats:GetLimitPoints() or nil,
        merits = merit_cap and stats:GetMeritPoints() or nil, merit_cap = merit_cap,
        limit_mode = truth(stats:GetIsLimitModeEnabled()), limit_breaker = truth(stats:GetIsLimitBreaker()),
        exp_locked = truth(stats:GetIsExperiencePointsLocked()), dead = status == 2 or status == 3, dedication = false,
        food = false, food_known = false, sync_active = nil, utc = player.utc() };
    local icons, timers = stats:GetStatusIcons(), stats:GetStatusTimers();
    if (icons ~= nil) then
        snapshot.food_known = true;
        snapshot.sync_active = false;
        for i = 0, 31 do
            if (icons[i] == 269) then snapshot.sync_active = true; end
            if (icons[i] == 251) then
                snapshot.food = true;
                snapshot.food_seconds = effect_seconds(timers and timers[i], snapshot.utc);
            end
            if (icons[i] == 249) then
                snapshot.dedication = true;
                snapshot.dedication_seconds = effect_seconds(timers and timers[i], snapshot.utc);
            end
        end
    else
        local buffs = stats:GetBuffs();
        snapshot.food_known = buffs ~= nil;
        if (buffs ~= nil) then snapshot.sync_active = false; end
        for i = 0, 31 do
            if (buffs ~= nil and buffs[i] == 269) then snapshot.sync_active = true; end
            if (buffs ~= nil and buffs[i] == 249) then snapshot.dedication = true; end
            if (buffs ~= nil and buffs[i] == 251) then snapshot.food = true; end
        end
    end
    return snapshot;
end

return player;
