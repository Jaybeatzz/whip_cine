-- Save / load bridge to the server. Every call is a WHIP Callback (checked server-side as a
-- SecureCallback). The project document (up to Config.Storage.MaxProjectBytes) travels in pieces of
-- Config.Storage.ChunkBytes, one callback each, so no single network message gets large.
Cine.Persist = { saving = false, lastSaveAt = 0 }
local P = Cine.Persist

local reqCounter = 0
local pendingSave = nil     -- { reqId, deadline }
local pendingLoad = nil     -- { reqId, id }

local function nextReq()
    reqCounter = reqCounter + 1
    return reqCounter
end

local function reasonText(r)
    return tostring(r or 'unknown')
end

local CB = Cine.Resource .. ':'

--- Callback wrapper: every server call goes through WHIP, never throws into the NUI.
local function call(name, ...)
    local res, why = Whip.core:Callback(CB .. name, ...)
    if type(res) ~= 'table' then return { ok = false, reason = why or 'no_answer' } end
    return res
end

local function chunks(raw)
    local size, parts = Config.Storage.ChunkBytes, {}
    for i = 1, #raw, size do parts[#parts + 1] = raw:sub(i, i + size - 1) end
    return parts
end

function P.Open()
    return call('open')
end

function P.List()
    return call('list')
end

function P.Create(name)
    local res = call('create', name)
    if res.ok and res.project then
        local doc = CineSchema.Project(res.project)
        if doc then Cine.Store.Load(doc) else res = { ok = false, reason = 'bad_schema' } end
    end
    return res
end

function P.Rename(id, name)
    return call('rename', id, name)
end

function P.Duplicate(id, newName)
    return call('duplicate', id, newName or '')
end

function P.Delete(id)
    local res = call('delete', id)
    local proj = Cine.Store.project
    if res.ok and proj and proj.id == id then Cine.Store.Unload() end
    return res
end

--- Fetch a project from the server piece by piece, then load it. Runs in its own thread.
local function receive(id, reqId)
    local res = call('load', id)
    if not res.ok then return res end
    local parts, count = { res.data or '' }, math.floor(tonumber(res.count) or 1)
    for i = 2, count do
        if not pendingLoad or pendingLoad.reqId ~= reqId then return { ok = false, reason = 'cancelled' } end
        local part = call('loadPart', id, i)
        if not part.ok or type(part.data) ~= 'string' then return { ok = false, reason = part.reason or 'bad_payload' } end
        parts[i] = part.data
    end
    return { ok = true, json = table.concat(parts) }
end

local function applyLoaded(raw)
    if type(raw) ~= 'string' or #raw > Config.Storage.MaxProjectBytes then
        Cine.Notify(_L('load_failed', 'bad_payload'), 'error')
        return
    end
    local ok, decoded = pcall(json.decode, raw)
    local doc = ok and type(decoded) == 'table' and CineSchema.Project(decoded) or nil
    if not doc then
        Cine.Notify(_L('load_failed', 'bad_schema'), 'error')
        return
    end
    if not Cine.Session.active then return end
    Cine.Store.Load(doc)
end

--- Request a project from the server; it is applied when every piece has arrived.
function P.Load(id)
    local reqId = nextReq()
    pendingLoad = { reqId = reqId, id = id }
    CreateThread(function()
        local res = receive(id, reqId)
        if not pendingLoad or pendingLoad.reqId ~= reqId then return end
        pendingLoad = nil
        if not res.ok then
            if res.reason ~= 'cancelled' then Cine.Notify(_L('load_failed', reasonText(res.reason)), 'error') end
            return
        end
        applyLoaded(res.json)
    end)
    return { ok = true }
end

--- Send the open project to the server (non-blocking). The result goes to the NUI as 'saveResult'.
function P.Save(silent)
    local proj = Cine.Store.project
    if not proj then Cine.Notify(_L('no_project'), 'error'); return false end
    if pendingSave then return false end
    local doc = CineSchema.Project(proj)
    if not doc then
        Cine.Nui.Send('saveResult', { ok = false, reason = 'bad_schema' })
        return false
    end
    local enc = json.encode(doc)
    if #enc > Config.Storage.MaxProjectBytes then
        Cine.Nui.Send('saveResult', { ok = false, reason = 'too_large' })
        Cine.Notify(_L('save_failed', 'too_large'), 'error')
        return false
    end
    local reqId = nextReq()
    pendingSave = { reqId = reqId, silent = silent == true, deadline = GetGameTimer() + Config.Storage.SaveTimeoutMs, revAtSend = Cine.Store.rev }
    P.saving = true
    Cine.Nui.Send('state', Cine.Session.StatePayload())
    local id = doc.id
    CreateThread(function()
        local parts = chunks(enc)
        local res = { ok = false, reason = 'no_answer' }
        for i = 1, #parts do
            if not pendingSave or pendingSave.reqId ~= reqId then return end -- timed out meanwhile
            res = call('savePart', id, i, #parts, parts[i])
            if not res.ok then break end
        end
        P.OnSaved({ reqId = reqId, ok = res.ok == true, reason = res.reason, bytes = res.bytes, savedAt = res.savedAt })
    end)
    return true
end

--- Per-frame housekeeping: save timeout + autosave. Cheap.
function P.Tick()
    if pendingSave and GetGameTimer() > pendingSave.deadline then
        pendingSave = nil
        P.saving = false
        Cine.Nui.Send('saveResult', { ok = false, reason = 'timeout' })
        Cine.Nui.Send('state', Cine.Session.StatePayload())
    end
    local every = Config.Storage.AutosaveSec
    if every > 0 and not pendingSave and Cine.Store.project and Cine.Store.dirty
        and GetGameTimer() - P.lastSaveAt > every * 1000 then
        P.lastSaveAt = GetGameTimer()
        P.Save(true)
    end
end

function P.Reset()
    pendingSave, pendingLoad, P.saving = nil, nil, false
    P.lastSaveAt = GetGameTimer()
end

function P.OnSaved(payload)
    if type(payload) ~= 'table' or not pendingSave or payload.reqId ~= pendingSave.reqId then return end
    local silent = pendingSave.silent
    local sentRev = pendingSave.revAtSend
    pendingSave = nil
    P.saving = false
    P.lastSaveAt = GetGameTimer()
    if payload.ok == true then
        -- edits made while the save was in flight keep the project dirty
        if Cine.Store.rev == sentRev then Cine.Store.dirty = false end
        Cine.Nui.Send('saveResult', { ok = true, savedAt = payload.savedAt, silent = silent })
        if not silent then Cine.Notify(_L('saved'), 'success') end
    else
        Cine.Nui.Send('saveResult', { ok = false, reason = reasonText(payload.reason) })
        Cine.Notify(_L('save_failed', reasonText(payload.reason)), 'error')
    end
    Cine.Nui.Send('state', Cine.Session.StatePayload())
end
