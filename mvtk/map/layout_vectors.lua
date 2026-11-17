-- Map outlines exported beside the overview image (G8-06).
--
-- Layout Editor Export and Prepare & Check write
-- developer/assets/minimap/layout_vectors.lua through
-- developer/tools/layout_minimap.lua, which calls M.encode. The world map
-- reads it with M.load. Coordinates are baked-map space, the same space as
-- layout_map.lua's world_min/world_max: a runtime world position becomes a map
-- position by adding the layout's origin_shift (mvtk/map/map_view.lua).
--
-- Pure: no engine API except the optional sys.load_resource fallback in
-- M.load, and LuaJ-safe (integers through %d only: no quoted-string format,
-- frontier pattern or float precision),
-- because the editor runs M.encode.
local M = {}

M.VERSION = 1
M.RESOURCE_PATH = "/developer/assets/minimap/layout_vectors.lua"
M.DISK_PATH = "./developer/assets/minimap/layout_vectors.lua"

local function int(value)
    local n = tonumber(value) or 0
    return string.format("%d", math.floor(n + 0.5))
end

-- Room ids are file names; escape the few characters that would end a string.
local function quote(text)
    text = tostring(text or "")
    text = text:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
    return '"' .. text .. '"'
end

local function int_list(values)
    local out = {}
    for i = 1, #(values or {}) do out[i] = int(values[i]) end
    return "{" .. table.concat(out, ",") .. "}"
end

local function point(p)
    return "{x=" .. int(p and p.x) .. ",y=" .. int(p and p.y) .. "}"
end

local HEADER = "-- Generated map outlines. DO NOT EDIT: Layout Editor Export and Prepare & Check write it."

-- data = {tile_width, tile_height, world_min={x,y}, world_max={x,y}, rooms={
--   {id, color={r,g,b,a}, poly={x1,y1,x2,y2,...},
--    doors={x0,y0,x1,y1,locked(0|1), ...}, platforms={x0,y0,x1,y1, ...}}}}
-- Rooms are written sorted by id, one function each, so no single chunk
-- function collects every room's constants.
function M.encode(data)
    data = data or {}
    local rooms = {}
    for _, room in ipairs(data.rooms or {}) do rooms[#rooms + 1] = room end
    table.sort(rooms, function(a, b) return tostring(a.id) < tostring(b.id) end)
    local rows = { HEADER, "local R = {}" }
    for i, room in ipairs(rooms) do
        rows[#rows + 1] = "R[" .. i .. "] = function() return {id=" .. quote(room.id)
            .. ",color=" .. int_list(room.color or { 0, 0, 0, 0 })
            .. ",poly=" .. int_list(room.poly)
            .. ",doors=" .. int_list(room.doors)
            .. ",platforms=" .. int_list(room.platforms) .. "} end"
    end
    rows[#rows + 1] = "local rooms = {}"
    rows[#rows + 1] = "for i = 1, #R do rooms[i] = R[i]() end"
    rows[#rows + 1] = "return {version=" .. int(M.VERSION)
        .. ",tile_width=" .. int(data.tile_width) .. ",tile_height=" .. int(data.tile_height)
        .. ",world_min=" .. point(data.world_min) .. ",world_max=" .. point(data.world_max)
        .. ",rooms=rooms}"
    return table.concat(rows, "\n") .. "\n"
end

-- The empty toolkit's committed stub (mvtk/editor/reset_baseline.lua).
M.EMPTY = M.encode({ tile_width = 0, tile_height = 0,
    world_min = { x = 0, y = 0 }, world_max = { x = 0, y = 0 }, rooms = {} })

function M.decode(src)
    if type(src) ~= "string" or src == "" then return nil, "empty" end
    local loader = loadstring or load
    local chunk, err = loader(src)
    if not chunk then return nil, "compile: " .. tostring(err) end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then return nil, "eval: " .. tostring(data) end
    return data
end

local function rounded(v)
    local n = tonumber(v)
    return n and math.floor(n + 0.5) or nil
end

local function same_point(a, b)
    return type(a) == "table" and type(b) == "table"
        and rounded(a.x) ~= nil and rounded(a.x) == rounded(b.x)
        and rounded(a.y) ~= nil and rounded(a.y) == rounded(b.y)
end

-- Mismatch guard: outlines are usable only when they were written by the same
-- export as layout_map.lua. regenerate_minimap.lua rewrites the image alone,
-- so a stale outline file must fall back to the overview image.
function M.compatible(vectors, map_meta)
    if type(vectors) ~= "table" then return false, "missing" end
    if vectors.version ~= M.VERSION then return false, "version" end
    if type(vectors.rooms) ~= "table" or #vectors.rooms == 0 then return false, "no rooms" end
    if type(map_meta) ~= "table" then return false, "no map metadata" end
    if not (same_point(vectors.world_min, map_meta.world_min) and same_point(vectors.world_max, map_meta.world_max)) then
        return false, "bounds differ from layout_map.lua"
    end
    return true
end

-- Reads the loose file first (editor builds see a fresh export at once), then
-- the bundled custom resource. opts.open and opts.load_resource replace
-- io.open and sys.load_resource in tests.
function M.read(opts)
    opts = opts or {}
    local open = opts.open
    if open == nil and io then open = io.open end
    if open then
        local fh = open(opts.disk_path or M.DISK_PATH, "r")
        if fh then
            local src = fh:read("*a")
            fh:close()
            if src and #src > 0 then return src, "disk" end
        end
    end
    local load_resource = opts.load_resource
    if load_resource == nil and sys then load_resource = sys.load_resource end
    if not load_resource then return nil, "no loader" end
    local ok, src = pcall(load_resource, opts.resource_path or M.RESOURCE_PATH)
    if ok and type(src) == "string" and #src > 0 then return src, "resource" end
    return nil, "not found"
end

-- Returns the outlines, or nil and a reason; the map then stays overview-only.
function M.load(map_meta, opts)
    local src, source = M.read(opts)
    if not src then return nil, source end
    local data, err = M.decode(src)
    if not data then return nil, err end
    local ok, why = M.compatible(data, map_meta)
    if not ok then return nil, why end
    return data, source
end

return M
