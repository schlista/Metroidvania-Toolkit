-- Shared world-default contract for preparation and runtime. No disk/engine APIs.
local OP = require "mvtk.tiled.object_props"
local M = {}
local active, members = {}, {}

local function selected(value)
    return value ~= nil and value ~= "" and value ~= "inherit"
end

function M.validate(properties)
    local result = {}
    for _, key in ipairs({"world_name", "default_biome", "default_music", "default_ambience", "default_map_color"}) do
        local value = (properties or {})[key]
        if value ~= nil then
            assert(type(value) == "string", "World property " .. key .. " must be a string")
            if key == "default_map_color" and value ~= "" then
                assert(value:match("^#%x%x%x%x%x%x$") or value:match("^#%x%x%x%x%x%x%x%x$"),
                    "default_map_color must be a Tiled Color (#RRGGBB or #AARRGGBB)")
            end
            result[key] = value
        end
    end
    return result
end

-- `regions` is the optional developer/config/biomes.lua table. When given, a
-- room's music and ambient sound fall back from the room value to its
-- region's `music` and `ambience`, and only then to the world defaults.
function M.resolve(properties, world, regions)
    properties, world = properties or {}, world or {}
    local result = {}
    for key, value in pairs(properties) do result[key] = value end
    local function inherit(key, value, default, fallback)
        if selected(value) then result[key] = value
        elseif selected(fallback) then result[key] = fallback
        else result[key] = selected(default) and default or nil end
    end
    inherit("biome", OP.get(properties, "biome"), world.default_biome)
    local region = type(regions) == "table" and result.biome and regions[result.biome]
    region = type(region) == "table" and region or {}
    inherit("music", OP.get(properties, "music"), world.default_music, region.music)
    -- `ambience` is a legacy music alias. Ambient loops use their own property.
    inherit("ambient_sound", properties.ambient_sound, world.default_ambience, region.ambience)
    local tint = world.default_map_color
    -- Transparent world color means inherit the biome/project color. Room
    -- biome_color keeps its existing RGB-only behavior, regardless of alpha.
    if tint and tint:match("^#00%x%x%x%x%x%x$") then tint = nil end
    inherit("biome_color", properties.biome_color, tint)
    return result
end

-- Called with the published layout; defaults never leak to unrelated rooms or
-- another world. Reading a cached room again resolves against the new snapshot.
function M.set_layout(layout)
    active, members = {}, {}
    if layout and layout.source and layout.source.kind == "tiled" then
        active = M.validate(layout.world_properties)
        for _, room in ipairs(layout.rooms or {}) do members[room.id] = true end
    end
end

function M.for_room(id)
    return members[id] and active or {}
end

-- `regions` (optional biomes.lua table) adds the region music and ambience ids.
function M.validate_domains(world, config, regions)
    local function check(value, label, filename, entries)
        if not selected(value) or value == "none" or value == "hush" then return end
        local domain = config(filename)
        domain = entries and domain[entries] or domain
        assert(type(domain) == "table" and domain[value] ~= nil,
            "Unknown " .. label .. " '" .. value .. "' in developer/config/" .. filename .. ".lua")
    end
    check(world.default_biome, "default_biome", "biomes")
    check(world.default_music, "default_music", "music_tracks_generated", "tracks")
    check(world.default_ambience, "default_ambience", "ambient_sounds")
    if type(regions) ~= "table" then return end
    local ids = {}
    for id, entry in pairs(regions) do
        if type(entry) == "table" then ids[#ids + 1] = tostring(id) end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local entry = regions[id]
        check(entry.music, "music of region " .. id, "music_tracks_generated", "tracks")
        check(entry.ambience, "ambience of region " .. id, "ambient_sounds")
    end
end

return M
