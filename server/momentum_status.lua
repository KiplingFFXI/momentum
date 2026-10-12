-----------------------------------
-- Momentum status companion
-- Read-only gameplay snapshots for players who opt in.
-- Source profile: Phoenix 071c401048bdb97bcbe12ad93651574fcf867407
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('momentum_status')
local heartbeat

local function publishChain(player, ending, sequence, now)
    local known, count, serverNow, deadline = 0, 0, 0, 0
    if not ending and type(GetMomentumChain) == 'function' then
        local ok, native = pcall(GetMomentumChain, player)
        if ok and type(native) == 'table' and native.known == true then
            local valid = true
            for _, key in ipairs({ 'count', 'server_now_ms', 'deadline_ms' }) do
                local value = native[key]
                if type(value) ~= 'number' or value < 0 or value > 9007199254740991 or value ~= math.floor(value) then
                    valid = false
                end
            end

            if valid and native.count <= 65534 then
                local inactive = native.deadline_ms == 0 and native.count == 0
                local remaining = native.deadline_ms - native.server_now_ms
                if inactive or (remaining > 0 and remaining <= 300000) then
                    known, count, serverNow, deadline = 1, native.count, native.server_now_ms, native.deadline_ms
                end
            end
        end
    end

    local values =
    {
        'MOMC1', player:getID(), player:getZoneID(), player:getMainJob(),
        player:getJobLevel(player:getMainJob()), player:getMainLvl(), sequence, now,
        ending and 0 or 1, known, count, serverNow, deadline,
    }

    for i, value in ipairs(values) do
        values[i] = type(value) == 'number' and string.format('%.0f', value) or value
    end

    player:printToPlayer(table.concat(values, '|'), xi.msg.channel.SYSTEM_3, 'Momentum')
end

local function publish(player, ending)
    if player:getObjType() ~= xi.objType.PC or (player:getCharVar('[Momentum]Status') ~= 1 and not ending) then
        return
    end

    if player:getMainJob() == xi.job.MON then
        return
    end

    local now        = GetSystemTime()
    local serial     = player:getLocalVar('[Momentum]Stamp') == now and player:getLocalVar('[Momentum]Serial') + 1 or 0
    local sequence   = now * 1000 + serial
    local syncActive = player:hasStatusEffect(xi.effect.LEVEL_SYNC)
    local dedication = player:getStatusEffect(xi.effect.DEDICATION)
    local pool       = 0
    local bonus      = 0
    local seconds    = 0

    if dedication then
        pool    = dedication:getSubPower()
        bonus   = dedication:getPower()
        seconds = math.ceil(dedication:getTimeRemaining() / 1000)
    end

    player:setLocalVar('[Momentum]Stamp', now)
    player:setLocalVar('[Momentum]Serial', serial)
    local values =
    {
        'MOM1', player:getID(), player:getZoneID(), player:getMainJob(),
        player:getJobLevel(player:getMainJob()), player:getMainLvl(), sequence, now,
        syncActive and 1 or 0, syncActive and player:getLocalVar('[SyncPenalty]Amount') or 0,
        GetServerVariable('[SyncPenalty]RatePerLevel'), dedication and 1 or 0, pool, bonus, seconds, ending and 0 or 1,
    }

    for i, value in ipairs(values) do
        values[i] = type(value) == 'number' and string.format('%.0f', value) or value
    end

    player:printToPlayer(table.concat(values, '|'), xi.msg.channel.SYSTEM_3, 'Momentum')
    publishChain(player, ending, sequence, now)
end

local function schedule(player)
    local now = GetSystemTime()
    if player:getCharVar('[Momentum]Status') ~= 1 or player:getLocalVar('[Momentum]Next') > now then
        return
    end

    player:setLocalVar('[Momentum]Next', now + 5)
    player:timer(5000, heartbeat)
end

heartbeat = function(player)
    local due = player:getLocalVar('[Momentum]Next')
    if due == 0 or due > GetSystemTime() or player:getCharVar('[Momentum]Status') ~= 1 then
        return
    end

    player:setLocalVar('[Momentum]Next', 0)
    publish(player)
    schedule(player)
end

local function publishAfterEffect(player)
    if player:getObjType() == xi.objType.PC and player:getCharVar('[Momentum]Status') == 1 then
        -- Effect loss callbacks run before the container removes the old effect.
        player:timer(100, publish)
    end
end

m:addOverride('xi.player.onGameIn', function(player, firstLogin, zoning)
    super(player, firstLogin, zoning)
    publishAfterEffect(player)
    schedule(player)
end)

m:addOverride('xi.player.onPlayerLevelUp', function(player)
    super(player)
    publishAfterEffect(player)
end)

m:addOverride('xi.player.onPlayerLevelDown', function(player)
    super(player)
    publishAfterEffect(player)
end)

m:addOverride('xi.effects.level_sync.onEffectGain', function(player, effect)
    super(player, effect)
    publishAfterEffect(player)
end)

m:addOverride('xi.effects.level_sync.onEffectLose', function(player, effect)
    super(player, effect)
    publishAfterEffect(player)
end)

m:addOverride('xi.effects.dedication.onEffectGain', function(player, effect)
    super(player, effect)
    publishAfterEffect(player)
end)

m:addOverride('xi.effects.dedication.onEffectLose', function(player, effect)
    super(player, effect)
    publishAfterEffect(player)
end)

m:addOverride('xi.experiencePoints.calculate', function(player, mob, data)
    local result = super(player, mob, data)
    publishAfterEffect(player)
    return result
end)

---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 0,
    parameters = 's',
}

commandObj.onTrigger = function(player, option)
    if option == 'on' then
        player:setCharVar('[Momentum]Status', 1)
        publish(player)
        schedule(player)
        player:printToPlayer('Momentum status sharing is on.', xi.msg.channel.SYSTEM_3)
        return
    end

    if option == 'off' then
        player:setCharVar('[Momentum]Status', 0)
        player:setLocalVar('[Momentum]Next', 0)
        publish(player, true)
        player:printToPlayer('Momentum status sharing is off.', xi.msg.channel.SYSTEM_3)
        return
    end

    player:printToPlayer('Use !momentumstatus on or !momentumstatus off.', xi.msg.channel.SYSTEM_3)
end

xi.module.registerCommand('momentumstatus', commandObj)
