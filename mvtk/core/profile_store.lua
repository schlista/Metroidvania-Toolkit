-- Per-game player data shared by save slots, never a checkpoint provider.
local SavePaths = require "mvtk.core.save_paths"
local M = {}

-- Minimum wall-time seconds between successful ordinary flushes. Milestones
-- and shutdown pass force=true; deferred or failed writes remain dirty.
M.FLUSH_INTERVAL = 10

local ALLOCATED = { achievements = true, records = true, unlocks = true }
local loaded, dirty = false, false
local sections, previous_good = {}, nil
local blocked, last_flush = nil, nil

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[key] = copy(item, seen) end
    return result
end

local function nonempty(value)
    return type(value) == "string" and value ~= ""
end

local function other_game(data)
    local current = SavePaths.game_id()
    return type(data) == "table" and nonempty(data.game_id)
        and nonempty(current) and data.game_id ~= current
end

local function valid(data)
    if type(data) ~= "table" or data.version ~= 1 or type(data.sections) ~= "table" then
        return false
    end
    for name, value in pairs(data.sections) do
        if not ALLOCATED[name] or type(value) ~= "table" then return false end
    end
    return true
end

local function read(file)
    -- SavePaths.path calls sys.get_save_file, which raises if unavailable.
    local ok, path = pcall(SavePaths.path, file)
    if not ok then return nil end
    local read_ok, data = pcall(sys.load, path)
    if read_ok then return data end
end

-- Idempotent, also called lazily by get/put/flush.
function M.load()
    if loaded then return not blocked, blocked end
    loaded = true
    local candidate
    for _, file in ipairs({ "mvtk_profile", "mvtk_profile_backup" }) do
        local data = read(file)
        -- Check both owners before selecting a payload, even when the main
        -- file is valid: its next flush must not overwrite a foreign backup.
        if other_game(data) then
            blocked = "different_game"
            print("[PROFILE] Ignoring another game's profile; disk writes disabled.")
            return false, blocked
        end
        if not candidate and valid(data) then candidate = data end
    end
    if candidate then
        sections = copy(candidate.sections)
        previous_good = copy(candidate)
    end
    return true
end

function M.get(section)
    assert(ALLOCATED[section], "Unallocated profile section: " .. tostring(section))
    M.load()
    return copy(sections[section] or {})
end

function M.put(section, data)
    assert(ALLOCATED[section], "Unallocated profile section: " .. tostring(section))
    assert(type(data) == "table", "Profile section data must be a table")
    M.load()
    sections[section] = copy(data)
    dirty = true
end

local function write(path, data)
    -- sys.save returns nothing on success and raises on failure. Also reject
    -- a false result from hosts that expose failure that way.
    local ok, result = pcall(sys.save, path, copy(data))
    if not ok then return false, tostring(result) end
    if result == false then return false, "save_failed" end
    return true
end

function M.flush(force)
    -- Lazy to avoid a load-time cycle with checkpoint/provider dependencies.
    -- This guard applies even to forced and clean flushes.
    if require("mvtk.core.checkpoint").is_save_sandboxed() then
        return false, "save_suspended:sandbox"
    end
    M.load()
    if blocked then return false, blocked end
    if not dirty then return true end
    local now = os.time()
    if not force and last_flush and now - last_flush < M.FLUSH_INTERVAL then
        return false, "throttled"
    end
    local ok, path = pcall(SavePaths.path, "mvtk_profile")
    if not ok then return false, tostring(path) end
    if previous_good then
        local backup_ok, backup_path = pcall(SavePaths.path, "mvtk_profile_backup")
        if not backup_ok then return false, tostring(backup_path) end
        local saved, err = write(backup_path, previous_good)
        if not saved then return false, err end
    end
    local game_id = SavePaths.game_id()
    local payload = { version = 1, game_id = nonempty(game_id) and game_id or nil,
        sections = copy(sections) }
    local saved, err = write(path, payload)
    if not saved then return false, err end
    previous_good = copy(payload)
    dirty, last_flush = false, now
    return true
end

return M
