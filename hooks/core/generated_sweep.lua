-- hooks/core/generated_sweep.lua
--
-- Stale generated-file sweep (CP05b, docs/metroidvania/STAGE_7_WORLD_SCALE_PLAN.md
-- slice f "2.3 Rows", decision D-CP05-3 (a)). After a full Create Rooms has
-- baked and audited every room, delete the top-level files in the generated
-- rooms folder that nothing references and that carry a current or removed
-- room's prefix. Until this row nothing removed them: a deleted Tiled object
-- left its .go behind for good, and every owned object left its source <id>.go.
--
-- References come from developer/tools/generated_census.lua (every room
-- collection and factory, followed through each generated resource they name,
-- embedded data included). CP05e: unreferenced files in the shared store
-- (the `shared` subfolder, content-addressed by mvtk/editor/shared_proto.lua
-- and written only by Create Rooms) are swept too, though their names carry
-- no room prefix. Never touched: dot files (.generation_cache, .gitkeep),
-- other subfolders (_mvtk_elevators is reconciled by ElevatorResources),
-- other names without a room prefix, and KEEP_SUFFIXES. The sweep deletes nothing
-- when a current room's collection cannot be read, because its references are
-- then unknown.
--
-- The editor's os.remove can delete a file and still return a falsy value, so
-- the return value of remove is ignored and each path is read back instead.
-- Pure Lua for the editor (LuaJ) and headless runs: no frontier patterns, no
-- %.Nf formats, no editor calls except through the passed functions.
local Census = require "developer.tools.generated_census"

local M = {}

M.CACHE_NAME = ".generation_cache"
M.COLLECTIONS_DIR = "/developer/rooms/collections"
M.FACTORIES_DIR = "/developer/rooms/factories"

-- Bake-time intermediates that are read back on the next run, never named by
-- a resource. hooks/editor_script.lua ensure_pushable_bake_context compares
-- the room's tilemap with <room>_pushable_source.tilemap.
M.KEEP_SUFFIXES = {"_pushable_source.tilemap"}

local function ends_with(text, suffix)
    return #text >= #suffix and text:sub(-#suffix) == suffix
end

-- Room ids whose prefix marks a file as room-derived: the current rooms, the
-- rooms in the previous generation cache, and every <room>_level.go still in
-- the folder (each baked room writes one, so a removed room keeps its prefix
-- until its files are gone).
function M.room_ids(current, cache_text, names)
    local ids, seen = {}, {}
    local function add(id)
        if type(id) == "string" and id ~= "" and not seen[id] then
            seen[id] = true
            ids[#ids+1] = id
        end
    end
    for _, id in ipairs(current or {}) do add(id) end
    for line in tostring(cache_text or ""):gmatch("[^\r\n]+") do add(line:match("^([^|]+)|")) end
    for _, name in ipairs(names or {}) do add(name:match("^(.+)_level%.go$")) end
    table.sort(ids)
    return ids
end

-- True when the sweep may delete this file name, relative to the generated
-- folder: a top-level name, or "shared/<name>" in the shared store.
function M.sweepable(name, ids)
    local store = Census.STORE_SUBDIR .. "/"
    if name:sub(1, #store) == store then
        local rest = name:sub(#store + 1)
        return rest ~= "" and rest:sub(1, 1) ~= "." and not rest:find("/", 1, true)
    end
    if name:sub(1, 1) == "." or name:find("/", 1, true) then return false end
    for _, suffix in ipairs(M.KEEP_SUFFIXES) do
        if ends_with(name, suffix) then return false end
    end
    for _, id in ipairs(ids) do
        if name:sub(1, #id + 1) == id .. "_" then return true end
    end
    return false
end

-- opts:
--   room_ids  current room ids (a full generation's list)
--   read(resource_path) -> text or nil
--   list(resource_dir) -> file names in that folder (no folders); called
--             for the generated folder and its shared store
--   remove(resource_path)   its return value is ignored
--   exists(resource_path) -> boolean, read back after each remove
--   dir       the generated folder (default Census.GENERATED_DIR)
--   info(msg) optional log
-- Returns {removed=paths, failed=paths, kept=n} or nil, reason when nothing
-- was deleted because references could not be established.
function M.sweep(opts)
    opts = opts or {}
    local read, list, remove, exists = opts.read, opts.list, opts.remove, opts.exists
    if type(read) ~= "function" or type(list) ~= "function"
        or type(remove) ~= "function" or type(exists) ~= "function" then
        return nil, "missing sweep dependency"
    end
    local dir = Census.normalize_dir(opts.dir or Census.GENERATED_DIR)
    local roots = {}
    for _, id in ipairs(opts.room_ids or {}) do
        local path = M.COLLECTIONS_DIR .. "/" .. id .. ".collection"
        if not read(path) then return nil, "cannot read room collection " .. path end
        roots[#roots+1] = path
        roots[#roots+1] = M.FACTORIES_DIR .. "/" .. id .. "_factory.collectionfactory"
    end
    local names = list(dir) or {}
    local ids = M.room_ids(opts.room_ids, read(dir .. "/" .. M.CACHE_NAME), names)
    local census = Census.count({read=read, list=list, dir=dir, root_files=roots})
    local removed, failed, kept = {}, {}, 0
    for _, path in ipairs(census.unused_paths) do
        local name = path:sub(#dir + 2)
        if M.sweepable(name, ids) then
            pcall(remove, path)
            if exists(path) then
                failed[#failed+1] = path
            else
                removed[#removed+1] = path
            end
        else
            kept = kept + 1
        end
    end
    if type(opts.info) == "function" then
        opts.info(string.format("[GENERATED_SWEEP] Removed %d unreferenced generated file(s); kept %d without a room prefix or kept for the next bake.",
            #removed, kept))
        for _, path in ipairs(failed) do
            opts.info("[GENERATED_SWEEP][WARNING] Could not remove " .. path .. "; the next full Create Rooms retries it.")
        end
    end
    return {removed=removed, failed=failed, kept=kept}
end

-- Editor and headless entry point: C is the shared hooks context.
function M.run(C, room_ids)
    local function fs(path) return C.join(C.ROOT, (path:gsub("^/", ""))) end
    local result, reason = M.sweep({
        room_ids = room_ids,
        dir = C.GENERATED_ROOMS_RESOURCE_DIR,
        read = function(path) return C.read_text(fs(path)) end,
        list = function(path)
            local _, files = C.list_dir_filesystem(fs(path), {force_process=true})
            return files
        end,
        remove = function(path) return C.remove_path_filesystem(fs(path)) end,
        exists = function(path) return C.file_exists_any(fs(path)) end,
        info = C.info,
    })
    if not result and type(C.info) == "function" then
        C.info("[GENERATED_SWEEP][WARNING] Skipped: " .. tostring(reason))
    end
    return result, reason
end

return M
