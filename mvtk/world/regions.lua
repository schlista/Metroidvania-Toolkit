-- mvtk/world/regions.lua
-- The one region lookup. A region is an entry in developer/config/biomes.lua;
-- a room names one through its Tiled `biome` map property (or the world's
-- default_biome), or, failing that, through its layout tags.
--
--   Regions.of_room(room_id, layout_record) -> region id or nil
--   Regions.info(id)                        -> region record or nil
--   Regions.room_title(room_id)             -> landmark title or nil, card flag
--   Regions.layout_regions(rooms)           -> per-region bounds and centroid
--
-- No file-scope require of room_manager or the Tiled room registry: callers
-- pass the layout record, and the registry is reached by name at call time,
-- so room_manager can require this module later without a cycle. info() reads
-- config alone, so it works at boot before any room exists. Nothing is
-- memoized per call; callers cache (the registry copies a table each call).

local Util = require "mvtk.core.util"

local M = {}

-- Named, not literal: the registry is bundled through its own literal requires.
local REGISTRY_MODULE = "mvtk.tiled.tiled_room_registry"
local registry = nil

local function get_registry()
    if registry == nil then
        local ok, mod = pcall(require, REGISTRY_MODULE)
        registry = (ok and type(mod) == "table") and mod or false
    end
    return registry or nil
end

local function text_id(value)
    return Util.normalize_hash_string(value)
end

local function tags_region(record)
    local tags = type(record) == "table" and record.tags or nil
    if type(tags) ~= "table" then return nil end
    return text_id(tags.biome or tags.area or tags.region)
end

local function biomes()
    return Util.require_config("developer.config.biomes", {})
end

--- Region id for a room: the registry's resolved biome (room value, then the
-- published world default), else the layout record's biome/area/region tag.
function M.of_room(room_id, layout_record)
    local id = text_id(room_id)
    if id then
        local reg = get_registry()
        if reg and reg.get_room_metadata then
            local meta = reg.get_room_metadata(id)
            if type(meta) == "table" then
                local region = text_id(meta.biome or meta.area or meta.region)
                if region then return region end
            end
        end
    end
    return tags_region(layout_record)
end

local function trimmed(value)
    if type(value) ~= "string" then return nil end
    value = Util.trim(value)
    if value == "" then return nil end
    return value
end

--- Region record from biomes.lua, or nil for an unknown id. A blank or missing
-- name stays "" (an unnamed region: no card, no pause line); it never falls
-- back to the id.
function M.info(id, config)
    id = text_id(id)
    if not id then return nil end
    local entry = (config or biomes())[id]
    if type(entry) ~= "table" then return nil end
    return {
        id = id,
        name = trimmed(entry.name) or "",
        subtitle = trimmed(entry.subtitle) or "",
        color = entry.color,
        title_card = trimmed(entry.title_card),
        music = trimmed(entry.music),
        ambience = trimmed(entry.ambience),
    }
end

--- Optional landmark title from the room's Tiled map property `room_title`,
-- and whether its bool map property `room_title_card` asks for a landmark card.
function M.room_title(room_id)
    local id = text_id(room_id)
    local reg = id and get_registry()
    if not (reg and reg.get_room_metadata) then return nil, false end
    local meta = reg.get_room_metadata(id)
    local props = type(meta) == "table" and meta.authored_properties or nil
    if type(props) ~= "table" then return nil, false end
    local title = trimmed(props.room_title)
    local card = props.room_title_card == true or props.room_title_card == "true"
    return title, title ~= nil and card
end

local function record_bounds(room)
    local b = room.r or room.bounds
    if type(b) == "table" and tonumber(b.min_x) then
        return tonumber(b.min_x), tonumber(b.min_y), tonumber(b.max_x), tonumber(b.max_y)
    end
    local x = (tonumber(room.x) or 0) + (tonumber(room.ox) or 0)
    local y = (tonumber(room.y) or 0) + (tonumber(room.oy) or 0)
    return x, y, x + (tonumber(room.w) or 0), y + (tonumber(room.h) or 0)
end

--- Per region: the union of its rooms' bounds and their area-weighted centroid.
-- `rooms` is a layout room list ({id, x, y, w, h, ox, oy, tags}) or
-- MINIMAP_MODULE.snapshot().rooms ({id, r = {min_x, min_y, max_x, max_y}}).
-- Returns { [region_id] = {id, rooms = {sorted ids}, bounds = {...}, centroid = {x, y}} }.
function M.layout_regions(rooms)
    local list = {}
    for _, room in ipairs(rooms or {}) do
        if type(room) == "table" and text_id(room.id) then list[#list + 1] = room end
    end
    table.sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
    local acc, result = {}, {}
    for _, room in ipairs(list) do
        local id = text_id(room.id)
        local region = M.of_room(id, room)
        if region then
            local min_x, min_y, max_x, max_y = record_bounds(room)
            local a = acc[region]
            if not a then
                a = {area = 0, sx = 0, sy = 0, cx = 0, cy = 0, n = 0}
                acc[region] = a
                result[region] = {id = region, rooms = {},
                    bounds = {min_x = min_x, min_y = min_y, max_x = max_x, max_y = max_y}}
            end
            local out = result[region]
            out.rooms[#out.rooms + 1] = id
            local bb = out.bounds
            bb.min_x, bb.min_y = math.min(bb.min_x, min_x), math.min(bb.min_y, min_y)
            bb.max_x, bb.max_y = math.max(bb.max_x, max_x), math.max(bb.max_y, max_y)
            local area = math.max(0, max_x - min_x) * math.max(0, max_y - min_y)
            local cx, cy = (min_x + max_x) * 0.5, (min_y + max_y) * 0.5
            a.area, a.sx, a.sy = a.area + area, a.sx + cx * area, a.sy + cy * area
            a.cx, a.cy, a.n = a.cx + cx, a.cy + cy, a.n + 1
        end
    end
    for region, a in pairs(acc) do
        -- Zero-area rooms (no bounds yet) fall back to the plain mean of centres.
        if a.area > 0 then
            result[region].centroid = {x = a.sx / a.area, y = a.sy / a.area}
        else
            result[region].centroid = {x = a.cx / a.n, y = a.cy / a.n}
        end
    end
    return result
end

-- Tests replace the registry; nil restores the lazy lookup.
function M._set_registry(value)
    registry = value
end

return M
