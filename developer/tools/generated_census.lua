-- Generated-file census (CP05a, docs/metroidvania/STAGE_7_WORLD_SCALE_PLAN.md
-- slice f "2.3 Rows"): counts the files Create Rooms writes into the generated
-- rooms folder, by kind, and how many of them nothing references.
--
-- Read-only and pure Lua for the editor (LuaJ) and headless tests: no frontier
-- patterns, no %.Nf formats. It never deletes anything; the stale-file sweep
-- (hooks/core/generated_sweep.lua, CP05b) deletes from its unused list.
--
-- References are followed from every room collection and factory, through each
-- generated resource they name (a .go to its components, a collision object to
-- its .convexshape, embedded data included), using ResourceText. The top level
-- of the generated folder and the shared store (its `shared` subfolder, CP05e;
-- mvtk/editor/shared_proto.lua) are counted: dot files (.generation_cache,
-- .gitkeep) are bookkeeping, and other subfolders such as _mvtk_elevators are
-- world-owned and reconciled by their own stage.
local Resource = require "mvtk.editor.resource_text"
local M = {}

M.GENERATED_DIR = "/developer/rooms/generated"
M.ROOT_DIRS = {"/developer/rooms/collections", "/developer/rooms/factories"}
-- The content-addressed store inside the generated folder (shared_proto.DIR).
M.STORE_SUBDIR = "shared"
-- Bake-time intermediates Create Rooms reads back on its next run; no resource names them, and the
-- sweep keeps them (hooks/core/generated_sweep.lua KEEP_SUFFIXES, which must list the same names).
-- They count as generated files and stay in unused_paths, but never in unused.
M.KEEP_SUFFIXES = {"_pushable_source.tilemap"}

local function kept(path)
    for _, suffix in ipairs(M.KEEP_SUFFIXES) do
        if #path >= #suffix and path:sub(-#suffix) == suffix then return true end
    end
    return false
end

-- Kinds whose text can name further resources. Tilemaps name only their tile
-- source, read by one line; convex shapes, scripts and images name nothing.
local WALK = {go=true, collection=true, collisionobject=true, factory=true, collectionfactory=true,
    sprite=true, particlefx=true, sound=true, label=true, model=true, mesh=true, gui=true}

local function extension(path) return tostring(path or ""):match("%.([%w_]+)$") end

-- "/a/b/" or "a/b" -> "/a/b".
function M.normalize_dir(dir)
    local path = tostring(dir or ""):gsub("\\", "/"):gsub("/+", "/"):gsub("/$", "")
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    return path
end

local function looks_like_path(value)
    return value:sub(1, 1) == "/" and not value:find("[%s\"{}]") and extension(value) ~= nil
end

-- Every resource path a resource text names, embedded data included.
function M.references(text, found)
    found = found or {}
    local ok, doc = pcall(Resource.parse, text or "")
    if not ok then return found end
    local function walk(node)
        for _, entry in ipairs(node.entries) do
            if entry.node then walk(entry.node)
            elseif type(entry.value) == "string" then
                if looks_like_path(entry.value) then found[entry.value] = true
                elseif entry.name == "data" and entry.value:find("[{:]") then M.references(entry.value, found) end
            end
        end
    end
    walk(doc.root)
    return found
end

local function tilemap_references(text, found)
    for line in (text or ""):gmatch("[^\r\n]+") do
        local path = line:match('^%s*tile_set:%s*"([^"]+)"')
        if path and looks_like_path(path) then found[path] = true end
    end
    return found
end

-- opts: read(resource_path) -> text or nil; list(resource_dir) -> file names
-- in that folder (not recursive); dir (the generated folder, default
-- M.GENERATED_DIR); root_dirs (folders whose files are reference roots);
-- root_files (further root resource paths, optional).
-- Returns {files, unused, kinds, unused_kinds, unused_paths}; kinds count by
-- file extension. unused_paths lists every unreferenced file (the sweep's
-- candidates); unused and unused_kinds leave out the KEEP_SUFFIXES intermediates.
function M.count(opts)
    opts = opts or {}
    local read, list = opts.read, opts.list
    local dir = M.normalize_dir(opts.dir or M.GENERATED_DIR)
    local prefix = dir .. "/"
    local generated, kinds, total = {}, {}, 0
    local function add_files(folder)
        local names = list(folder) or {}
        table.sort(names)
        for _, name in ipairs(names) do
            if name:sub(1, 1) ~= "." and not name:find("/", 1, true) then
                local path = folder .. "/" .. name
                local kind = extension(name) or "other"
                generated[path] = kind
                kinds[kind] = (kinds[kind] or 0) + 1
                total = total + 1
            end
        end
    end
    add_files(dir)
    add_files(prefix .. M.STORE_SUBDIR)

    local referenced, visited, queue = {}, {}, {}
    local function visit(path)
        if visited[path] then return end
        visited[path] = true
        queue[#queue+1] = path
    end
    for _, root_dir in ipairs(opts.root_dirs or M.ROOT_DIRS) do
        local root = M.normalize_dir(root_dir)
        local files = list(root) or {}
        table.sort(files)
        for _, name in ipairs(files) do
            if WALK[extension(name) or ""] and not name:find("/", 1, true) then visit(root .. "/" .. name) end
        end
    end
    -- Named roots (the sweep passes every current room's collection and
    -- factory), walked even when a folder listing omits them.
    for _, path in ipairs(opts.root_files or {}) do
        if WALK[extension(path) or ""] then visit(path) end
    end
    local head = 1
    while queue[head] do
        local path = queue[head]; head = head + 1
        local kind = extension(path)
        local text = read(path)
        if text then
            local found = kind == "tilemap" and tilemap_references(text, {}) or M.references(text, {})
            for ref in pairs(found) do
                -- CP05d: a file in a subfolder is walked too, because a
                -- shared owner can name its room's tilemap; CP05e counts
                -- the shared store's own files as well.
                local inside = generated[ref] or ref:sub(1, #prefix) == prefix
                if inside then
                    if generated[ref] then referenced[ref] = true end
                    local ref_kind = extension(ref)
                    if WALK[ref_kind] or ref_kind == "tilemap" then visit(ref) end
                end
            end
        end
    end

    local unused, unused_kinds, unused_paths = 0, {}, {}
    for path, kind in pairs(generated) do
        if not referenced[path] then
            unused_paths[#unused_paths+1] = path
            if not kept(path) then
                unused = unused + 1
                unused_kinds[kind] = (unused_kinds[kind] or 0) + 1
            end
        end
    end
    table.sort(unused_paths)
    return {files=total, unused=unused, kinds=kinds, unused_kinds=unused_kinds, unused_paths=unused_paths}
end

-- "Generated room files: N (M unused)." for Preparation Status.
function M.line(census)
    return string.format("Generated room files: %d (%d unused).", census.files, census.unused)
end

-- "go 3 (1 unused), tilemap 1" in kind order, for the budget report.
function M.kind_text(census)
    local names = {}
    for kind in pairs(census.kinds) do names[#names+1] = kind end
    table.sort(names)
    local parts = {}
    for _, kind in ipairs(names) do
        local unused = census.unused_kinds[kind] or 0
        parts[#parts+1] = string.format("%s %d", kind, census.kinds[kind]) .. (unused > 0 and string.format(" (%d unused)", unused) or "")
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

return M
