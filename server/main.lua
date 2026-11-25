-- whip_cine server: WHIP permissions, project callbacks, chunked save / load transport.
-- Every client request is a WHIP SecureCallback: WHIP checks the permission, rate limit and
-- parameter types before a handler runs, and logs refusals in /whip -> System -> Monitor.
local RES = GetCurrentResourceName()
local CB = RES .. ':'
local S = CineSchema

local uploads = {}     -- [source] = { id, count, parts = {}, bytes, started }
local downloads = {}   -- [source] = { id, parts = {}, at }

local function log(fmt, ...)
    print(('^3[%s] ' .. fmt .. '^7'):format(RES, ...))
end

--- Who is asking, and may they see every character's projects?
local function viewerOf(source, player)
    local charId = player and player.charId
    if not charId then return nil end
    local all = Config.Access.ManagePermission
        and exports.whip_core:HasPermission(source, Config.Access.ManagePermission) or false
    return { charId = charId, all = all == true }
end

--- Reasons are short codes the UI already understands; WHIP shows `false, why` as a toast,
--- so refusals that need no toast return a table instead.
local function fail(reason) return { ok = false, reason = reason } end

local function split(raw)
    local size, parts = Config.Storage.ChunkBytes, {}
    for i = 1, #raw, size do parts[#parts + 1] = raw:sub(i, i + size - 1) end
    if #parts == 0 then parts[1] = '' end
    return parts
end

local function schema(extra)
    local s = { rateLimit = 250, burst = 4 }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

local function register(name, extra, handler)
    local ok, why = Whip.core:SecureCallback(CB .. name, schema(extra), function(source, player, ...)
        -- the permission is read live, so revoking it in /whip takes effect on the next call
        if Config.Access.Permission and not exports.whip_core:HasPermission(source, Config.Access.Permission) then
            return fail('denied')
        end
        local viewer = viewerOf(source, player)
        if not viewer then return fail('no_character') end
        return handler(source, viewer, ...)
    end)
    if not ok then log('could not register %s: %s', name, tostring(why)) end
end

Whip.register(function()
    Whip.core:EnsureTable(Storage.TABLE, Storage.CREATE)

    if Config.Access.Permission then
        Whip.core:RegisterPermission(Config.Access.Permission, {
            label = 'Use the cinematic director',
            description = 'Open /' .. Config.Access.Command .. ' and keep their own projects.',
        })
    end
    if Config.Access.ManagePermission then
        Whip.core:RegisterPermission(Config.Access.ManagePermission, {
            label = 'Manage every cinematic project',
            description = "See, open, change and delete every character's director projects.",
            implies = Config.Access.Permission and { Config.Access.Permission } or nil,
        })
    end

    local ID = { 'id', 'key', 40 }
    local NAME = { 'name', 'string', 64 }

    register('open', nil, function(_, viewer)
        return { ok = true, projects = Storage.List(viewer), manage = viewer.all, theme = (exports.whip_core:GetActiveTheme()) }
    end)

    register('list', nil, function(_, viewer)
        return { ok = true, projects = Storage.List(viewer) }
    end)

    register('create', { params = { NAME } }, function(_, viewer, name)
        local id, doc = Storage.Create(viewer, name)
        if not id then return fail(doc) end
        return { ok = true, id = id, project = doc, projects = Storage.List(viewer) }
    end)

    register('delete', { params = { ID } }, function(_, viewer, id)
        local ok, why = Storage.Delete(viewer, id)
        return { ok = ok, reason = why, projects = Storage.List(viewer) }
    end)

    register('rename', { params = { ID, NAME } }, function(_, viewer, id, name)
        local ok, why = Storage.Rename(viewer, id, name)
        return { ok = ok, reason = why, projects = Storage.List(viewer) }
    end)

    register('duplicate', { params = { ID, { 'newName', 'string', 64, '' } } }, function(_, viewer, id, newName)
        local newId, why = Storage.Duplicate(viewer, id, newName ~= '' and newName or nil)
        if not newId then return fail(why) end
        return { ok = true, id = newId, projects = Storage.List(viewer) }
    end)

    -- Load: the first call reads the project and answers with how many pieces it has and the
    -- first piece; the client asks for the rest one by one.
    register('load', { params = { ID } }, function(source, viewer, id)
        local raw, why = Storage.Read(viewer, id)
        if not raw then return fail(why) end
        local parts = split(raw)
        downloads[source] = { id = id, parts = parts, at = os.time() }
        return { ok = true, id = id, count = #parts, data = parts[1] }
    end)

    register('loadPart', { rateLimit = 20, burst = 80, params = { ID, { 'index', 'id', 1, 4096 } } }, function(source, _, id, index)
        local d = downloads[source]
        if not d or d.id ~= id or not d.parts[index] then return fail('no_download') end
        local data = d.parts[index]
        if index == #d.parts then downloads[source] = nil end
        return { ok = true, data = data }
    end)

    -- Save: pieces arrive in order; the last one writes the project.
    register('savePart', {
        rateLimit = 20, burst = 80,
        params = { ID, { 'index', 'id', 1, 4096 }, { 'count', 'id', 1, 4096 }, { 'data', 'any' } },
    }, function(source, viewer, id, index, count, data)
        if type(data) ~= 'string' or #data > Config.Storage.ChunkBytes then return fail('bad_payload') end
        local maxParts = math.ceil(Config.Storage.MaxProjectBytes / Config.Storage.ChunkBytes)
        if count > maxParts then return fail('too_large') end

        local u = uploads[source]
        if index == 1 then
            u = { id = id, count = count, parts = {}, bytes = 0, started = os.time() }
            uploads[source] = u
        end
        if not u or u.id ~= id or u.count ~= count or #u.parts ~= index - 1 then
            uploads[source] = nil
            return fail('out_of_order')
        end
        u.parts[index] = data
        u.bytes = u.bytes + #data
        if u.bytes > Config.Storage.MaxProjectBytes then
            uploads[source] = nil
            return fail('too_large')
        end
        if index < count then return { ok = true, more = true } end

        uploads[source] = nil
        local ok, reason, bytes, savedAt = Storage.Save(viewer, id, table.concat(u.parts))
        return { ok = ok, reason = reason, bytes = bytes, savedAt = savedAt }
    end)
end)

AddEventHandler('playerDropped', function()
    uploads[source] = nil
    downloads[source] = nil
end)

-- Half-finished transfers (a player who closed the game mid-save) are dropped after 2 minutes.
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for src, u in pairs(uploads) do if now - u.started > 120 then uploads[src] = nil end end
        for src, d in pairs(downloads) do if now - d.at > 120 then downloads[src] = nil end end
    end
end)
