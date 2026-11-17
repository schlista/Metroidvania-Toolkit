-- Pure projection of a validated inspection result into shared-list rows.
-- The caller owns reading/validation and supplies the retirement predicate.
local M = {}

local function keys(value)
    local out = {}
    if type(value) == "table" then for key in pairs(value) do out[#out + 1] = key end end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

local function add(rows, id, label)
    rows[#rows + 1] = {id = id, label = label, selectable = false}
end

local function flatten(rows, path, value)
    if type(value) ~= "table" then
        add(rows, path, path .. " = " .. tostring(value))
        return
    end
    local sorted = keys(value)
    if #sorted == 0 then add(rows, path, path .. " = {}") end
    for _, key in ipairs(sorted) do flatten(rows, path .. "." .. tostring(key), value[key]) end
end

local function payload(data, id, mirror)
    local entry = (data.modules or {})[id]
    if type(entry) == "table" and entry.data ~= nil then return entry.data end
    return mirror and data[mirror] or nil
end

-- data/source come straight from Checkpoint.inspect_slot, without migration.
-- A reason always hides payload details, including any accidentally supplied data.
function M.rows(data, reason, source, opts)
    opts = opts or {}
    local rows = {}
    if reason or not data then
        add(rows, "reason", reason or "missing")
        return rows
    end
    local meta = data.meta or {}
    add(rows, "version", "Version: " .. tostring(meta.version or 1))
    add(rows, "game_id", "Game ID: " .. tostring(meta.game_id or "absent (legacy)"))
    -- inspect_slot has already validated both stable and legacy checksums.
    add(rows, "checksum", "Checksum: " .. (meta.checksum and "valid" or "absent (legacy)"))
    add(rows, "source", "Source: " .. tostring(source or "unknown"))
    add(rows, "blocked", "Blocked reason: none")
    add(rows, "providers", "Providers (keys count immediate payload entries)")
    local ids = {}
    for id in pairs(data.modules or {}) do ids[id] = true end
    for id in pairs(meta.providers or {}) do ids[id] = true end
    for _, id in ipairs(keys(ids)) do
        local entry = (data.modules or {})[id] or (meta.providers or {})[id]
        local retired = opts.is_retired_provider and opts.is_retired_provider(id)
        add(rows, "provider:" .. tostring(id), tostring(id) .. (retired and " [retired]" or "")
            .. " | version " .. tostring(entry.version or 1) .. " | keys " .. #keys(entry.data))
    end
    if next(ids) == nil then add(rows, "providers:none", "Providers: none") end
    local prefix = opts.prefix or ""
    add(rows, "flags", "Flags (prefix: " .. prefix .. ")")
    local flags, count = payload(data, "flags", "flags"), 0
    for _, key in ipairs(keys(flags)) do
        if tostring(key):sub(1, #prefix) == prefix then
            flatten(rows, "Flag " .. tostring(key), flags[key]); count = count + 1
        end
    end
    if count == 0 then add(rows, "flags:none", "Flags: none matching") end
    for _, family in ipairs({
        {"Abilities", "abilities", "abilities"}, {"Inventory", "inventory", "inventory"},
        {"Death drop", "death_drop"}, {"Completion", "game_completion"},
    }) do
        local value = payload(data, family[2], family[3])
        if value == nil then add(rows, family[1], family[1] .. ": none")
        else flatten(rows, family[1], value) end
    end
    return rows
end

return M
