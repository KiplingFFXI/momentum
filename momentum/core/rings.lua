local rings = {}
local rules = require('data.phoenix_rules')
local EPOCH = 1009810800

local function uint(data, offset)
    local a, b, c, d = data:byte(offset, offset + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

function rings.decode(item, container, slot, utc)
    local rule = item and rules.rings and rules.rings[item.Id]
    if not rule or not item.Count or item.Count < 1 then return nil end
    local entry = { id = item.Id, container = container, slot = slot, key = container .. ':' .. slot .. ':' .. item.Id }
    for key, value in pairs(rule) do entry[key] = value end
    local extra = item.Extra
    if type(extra) ~= 'string' or #extra < 12 or extra:byte(1) ~= 1 then return entry end
    local charges = extra:byte(2)
    if charges > rule.max_charges then return entry end
    entry.charges = charges
    if charges == 0 then entry.ready, entry.recast = false, 0; return entry end
    local flag = extra:byte(4)
    if math.floor(flag / 64) % 2 == 1 then
        entry.recast, entry.ready = 0, true
    elseif type(utc) == 'number' and utc == utc and utc > EPOCH and utc < 4294967296 then
        local target = uint(extra, 5)
        if target > 0 then
            entry.recast = math.max(0, target + EPOCH - utc)
            entry.ready = entry.recast == 0
        end
    end
    if item.Flags == 5 and type(utc) == 'number' and utc > EPOCH and utc < 4294967296 then
        local target = uint(extra, 9)
        if target > 0 then entry.equip_delay = math.max(0, target + EPOCH - utc) end
    end
    return entry
end

function rings.read(utc, inventory)
    if not inventory then
        local ok, value = pcall(function() return AshitaCore:GetMemoryManager():GetInventory() end)
        if not ok then return { available = false, entries = {} } end
        inventory = value
    end
    if not inventory then return { available = false, entries = {} } end
    local result = { available = false, entries = {} }
    -- Include loaded storage so a spare ring remains visible without opening a bag.
    for container = 0, 16 do
        local ok, maximum = pcall(function() return inventory:GetContainerCountMax(container) end)
        if ok and type(maximum) == 'number' and maximum >= 0 and maximum <= 80 and maximum == math.floor(maximum) then
            result.available = true
            for slot = 1, maximum do
                local found, item = pcall(function() return inventory:GetContainerItem(container, slot) end)
                if found then
                    local entry = rings.decode(item, container, slot, utc)
                    if entry then result.entries[#result.entries + 1] = entry end
                else
                    result.incomplete = true
                end
            end
        end
    end
    if result.incomplete and #result.entries == 0 then result.available = false end
    return result
end

return rings
