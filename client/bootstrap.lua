-- WHIP satellite init (client) + shared namespace + small helpers.
Cine = {}
Cine.Resource = GetCurrentResourceName()
Cine.Ready = false

-- Runs once whip_core is ready, and again after every whip_core restart.
Whip.register(function()
    Cine.Ready = true
end)

--- Blocks until whip_core is usable. Returns false if it never arrives.
function Cine.WaitReady(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 30000)
    while not (Cine.Ready and Whip.isReady()) do
        if GetGameTimer() > deadline then return false end
        Wait(50)
    end
    return true
end

function Cine.Notify(message, kind)
    Whip.core:Notify(message, kind or 'info')
end

function Cine.Debug(...)
    if Config.Debug then print(('[%s]'):format(Cine.Resource), ...) end
end

--- Print where the developer sees it (F8).
function Cine.Err(fmt, ...)
    print(('^1[%s] ' .. fmt .. '^7'):format(Cine.Resource, ...))
end

--- Real-time clock in seconds (see Config.Timeline.ClockSource and spec risk R3).
function Cine.Clock()
    if Config.Timeline.ClockSource == 'network' then
        return GetNetworkTimeAccurate() / 1000.0
    end
    return GetGameTimer() / 1000.0
end

local lists = {}
--- Load lists/<name>.json once (array of strings or of tables).
function Cine.List(name)
    if lists[name] then return lists[name] end
    local raw = LoadResourceFile(Cine.Resource, 'lists/' .. name .. '.json')
    local ok, decoded = false, nil
    if raw and raw ~= '' then ok, decoded = pcall(json.decode, raw) end
    lists[name] = (ok and type(decoded) == 'table') and decoded or {}
    return lists[name]
end

function Cine.Ground(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + 0.0, false)
    if ok then return gz end
    return nil
end

--- Entity coordinates as a plain 3-array.
function Cine.EntityPos(e)
    local c = GetEntityCoords(e)
    return { c.x, c.y, c.z }
end
