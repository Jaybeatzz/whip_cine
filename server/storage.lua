-- Server-side project storage in the database (one row per project, owned by a character).
-- The table is created by WHIP's EnsureTable in server/main.lua.
Storage = {}
local RES = GetCurrentResourceName()
local S = CineSchema
local TABLE = 'whip_cine_projects'

Storage.TABLE = TABLE
Storage.CREATE = ([[
CREATE TABLE IF NOT EXISTS `%s` (
  `id` VARCHAR(40) NOT NULL,
  `charId` INT NOT NULL,
  `name` VARCHAR(64) NOT NULL,
  `created` INT UNSIGNED NOT NULL,
  `updated` INT UNSIGNED NOT NULL,
  `bytes` INT UNSIGNED NOT NULL DEFAULT 0,
  `shots` INT UNSIGNED NOT NULL DEFAULT 0,
  `doc` MEDIUMTEXT NOT NULL,
  `backup` MEDIUMTEXT NULL,
  PRIMARY KEY (`id`),
  KEY `charId` (`charId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(TABLE)

local counter = 0

local function log(fmt, ...)
    print(('^3[%s] ' .. fmt .. '^7'):format(RES, ...))
end

--- Row meta (no document) for one project, or nil.
local function meta(id)
    return MySQL.single.await(('SELECT `id`, `charId`, `name`, `created`, `updated`, `bytes`, `shots` FROM `%s` WHERE `id` = ?'):format(TABLE), { id })
end

--- May this viewer touch this project? viewer = { charId, all }
local function mayUse(row, viewer)
    return row ~= nil and (viewer.all or row.charId == viewer.charId)
end

local function countFor(charId)
    return MySQL.scalar.await(('SELECT COUNT(*) FROM `%s` WHERE `charId` = ?'):format(TABLE), { charId }) or 0
end

function Storage.NewId()
    local id
    repeat
        counter = counter + 1
        id = ('p_%d_%d_%d'):format(os.time(), math.random(1000, 9999), counter)
    until not meta(id)
    return id
end

--- Projects the viewer can see, newest first. Staff (viewer.all) also get the owner's name.
function Storage.List(viewer)
    local rows
    if viewer.all then
        rows = MySQL.query.await(('SELECT `id`, `charId`, `name`, `updated`, `shots`, `bytes` FROM `%s` ORDER BY `updated` DESC LIMIT 500'):format(TABLE), {})
    else
        rows = MySQL.query.await(('SELECT `id`, `charId`, `name`, `updated`, `shots`, `bytes` FROM `%s` WHERE `charId` = ? ORDER BY `updated` DESC'):format(TABLE), { viewer.charId })
    end
    rows = rows or {}
    local names = {}
    if viewer.all and #rows > 0 then
        local ids, seen = {}, {}
        for _, r in ipairs(rows) do
            if not seen[r.charId] then seen[r.charId] = true; ids[#ids + 1] = r.charId end
        end
        names = exports.whip_core:GetCharacterNames(ids) or {}
    end
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = r.id, name = r.name, updated = r.updated, shots = r.shots, bytes = r.bytes,
            mine = r.charId == viewer.charId,
            owner = viewer.all and r.charId ~= viewer.charId and (names[r.charId] or ('#' .. r.charId)) or nil,
        }
    end
    return out
end

--- Create an empty project owned by viewer.charId. Returns id, doc or nil, reason.
function Storage.Create(viewer, name)
    if not viewer.all and countFor(viewer.charId) >= Config.Storage.MaxProjects then return nil, 'max_projects' end
    local id = Storage.NewId()
    local now = os.time()
    local doc = S.NewProject(id, name, now)
    local enc = json.encode(doc)
    local ok = MySQL.insert.await(('INSERT INTO `%s` (`id`, `charId`, `name`, `created`, `updated`, `bytes`, `shots`, `doc`) VALUES (?, ?, ?, ?, ?, ?, 0, ?)'):format(TABLE),
        { id, viewer.charId, doc.name, now, now, #enc, enc })
    if ok == nil then return nil, 'write_failed' end
    return id, doc
end

--- Raw JSON of a project the viewer may open, or nil, reason.
function Storage.Read(viewer, id)
    if not S.Id(id) then return nil, 'bad_id' end
    local row = MySQL.single.await(('SELECT `charId`, `doc` FROM `%s` WHERE `id` = ?'):format(TABLE), { id })
    if not row then return nil, 'not_found' end
    if not mayUse(row, viewer) then return nil, 'not_yours' end
    if not row.doc or row.doc == '' then return nil, 'not_found' end
    return row.doc
end

--- Validate + write a sanitized project. Returns ok, reason, bytes, savedAt.
function Storage.Save(viewer, id, rawJson)
    if not S.Id(id) then return false, 'bad_id' end
    local row = meta(id)
    if not row then return false, 'unknown_project' end
    if not mayUse(row, viewer) then return false, 'not_yours' end
    if type(rawJson) ~= 'string' or #rawJson == 0 then return false, 'bad_payload' end
    if #rawJson > Config.Storage.MaxProjectBytes then return false, 'too_large' end
    local ok, decoded = pcall(json.decode, rawJson)
    if not ok or type(decoded) ~= 'table' then return false, 'bad_json' end
    local doc, why = S.Project(decoded)
    if not doc then return false, why or 'bad_schema' end
    if doc.id ~= id then return false, 'id_mismatch' end

    local now = os.time()
    doc.created = row.created
    doc.updated = now
    local enc = json.encode(doc)
    if #enc > Config.Storage.MaxProjectBytes then return false, 'too_large' end

    local sql
    if Config.Storage.Backup then
        sql = ('UPDATE `%s` SET `backup` = `doc`, `doc` = ?, `name` = ?, `updated` = ?, `bytes` = ?, `shots` = ? WHERE `id` = ?'):format(TABLE)
    else
        sql = ('UPDATE `%s` SET `doc` = ?, `name` = ?, `updated` = ?, `bytes` = ?, `shots` = ? WHERE `id` = ?'):format(TABLE)
    end
    local changed = MySQL.update.await(sql, { enc, doc.name, now, #enc, #doc.shots, id })
    if not changed or changed < 1 then return false, 'write_failed' end
    return true, nil, #enc, now
end

function Storage.Rename(viewer, id, name)
    local row = meta(id)
    if not mayUse(row, viewer) then return false, row and 'not_yours' or 'unknown_project' end
    local nm = S.Name(name, nil)
    if not nm then return false, 'bad_name' end
    local raw = Storage.Read(viewer, id)
    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            decoded.name = nm
            local doc = S.Project(decoded)
            if doc then
                local enc = json.encode(doc)
                MySQL.update.await(('UPDATE `%s` SET `doc` = ?, `bytes` = ? WHERE `id` = ?'):format(TABLE), { enc, #enc, id })
            end
        end
    end
    MySQL.update.await(('UPDATE `%s` SET `name` = ? WHERE `id` = ?'):format(TABLE), { nm, id })
    return true
end

--- The copy belongs to the viewer (staff copying someone's project get their own copy).
function Storage.Duplicate(viewer, id, newName)
    local row = meta(id)
    if not mayUse(row, viewer) then return nil, row and 'not_yours' or 'unknown_project' end
    if not viewer.all and countFor(viewer.charId) >= Config.Storage.MaxProjects then return nil, 'max_projects' end
    local raw = Storage.Read(viewer, id)
    if not raw then return nil, 'missing_doc' end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return nil, 'bad_json' end
    local newId = Storage.NewId()
    decoded.id = newId
    decoded.name = S.Name(newName, nil) or (row.name .. ' copy')
    local doc = S.Project(decoded)
    if not doc then return nil, 'bad_schema' end
    local now = os.time()
    doc.created, doc.updated = now, now
    local enc = json.encode(doc)
    local ins = MySQL.insert.await(('INSERT INTO `%s` (`id`, `charId`, `name`, `created`, `updated`, `bytes`, `shots`, `doc`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'):format(TABLE),
        { newId, viewer.charId, doc.name, now, now, #enc, #doc.shots, enc })
    if ins == nil then return nil, 'write_failed' end
    return newId
end

function Storage.Delete(viewer, id)
    local row = meta(id)
    if not mayUse(row, viewer) then return false, row and 'not_yours' or 'unknown_project' end
    MySQL.query.await(('DELETE FROM `%s` WHERE `id` = ?'):format(TABLE), { id })
    log('project %s deleted by character %s', id, tostring(viewer.charId))
    return true
end
