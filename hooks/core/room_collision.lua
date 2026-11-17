-- Shared editor/headless collision policy. Scrolling art never owns terrain hulls.
local Background = require "mvtk.editor.background_atlas"
local Regen = require "mvtk.editor.tilemap_regen"
local Split = require "hooks.core.tilemap_split"
local Selection = require "mvtk.editor.tileset_selection"
local M = {}

function M.scrolls(entry)
    return entry.parallaxx ~= 1 or entry.parallaxy ~= 1
end

function M.scrolling_layer_names(map)
    local names = {}
    for _, entry in ipairs(Background.flatten_tiled_layers(map and map.layers)) do
        if entry.layer.type == "tilelayer" and M.scrolls(entry) then
            names[entry.layer.name] = true
        end
    end
    return names
end

-- LuaJ ignores floating-point precision. Round first and format integers only.
local function factor(value)
    local rounded = math.floor(math.abs(value) * 1000000 + 0.5)
    local whole, fraction = math.floor(rounded / 1000000), rounded % 1000000
    local text = string.format("%d", whole)
    if fraction ~= 0 then text = text .. "." .. string.format("%06d", fraction):gsub("0+$", "") end
    return (value < 0 and rounded ~= 0 and "-" or "") .. text
end

local function normalize_tiled_layer_name(name)
    local normalized = tostring(name or ""):lower()
    normalized = normalized:gsub("[%s%-]+", "_")
    normalized = normalized:gsub("[^%w_]", "_")
    normalized = normalized:gsub("_+", "_")
    normalized = normalized:gsub("^_+", "")
    normalized = normalized:gsub("_+$", "")
    return normalized
end

local SOLID_COLLISION_OBJECT_TYPES = {
    collision_box = true,
    solid_box = true,
    solid = true,
    ground = true,
    collision = true,
    collision_slope = true,
    solid_slope = true,
    slope = true,
}

local function normalize_tiled_object_type(value)
    if value == nil then
        return nil
    end
    local normalized = normalize_tiled_layer_name(value)
    if normalized == "" then
        return nil
    end
    return normalized
end

local function get_object_property(object, key)
    local props = type(object) == "table" and object.properties or nil
    if type(props) ~= "table" then
        return nil
    end
    if props[key] ~= nil then
        return props[key]
    end
    for _, entry in ipairs(props) do
        if type(entry) == "table" and (entry.name == key or entry.Name == key) then
            if entry.value ~= nil then return entry.value end
            if entry.Value ~= nil then return entry.Value end
        end
    end
    return nil
end

local function object_has_solid_collision_type(object)
    local candidates = {
        object and object.type,
        object and object.class,
        object and object.className,
    }
    local template_file = get_object_property(object, "template_file")
    if template_file ~= nil then
        candidates[#candidates + 1] = tostring(template_file):match("([^/\\]+)%.tx$") or template_file
    end
    candidates[#candidates + 1] = object and object.name

    for _, value in ipairs(candidates) do
        local normalized = normalize_tiled_object_type(value)
        if normalized and SOLID_COLLISION_OBJECT_TYPES[normalized] then
            return true
        end
    end

    local solid = get_object_property(object, "solid")
    if solid == true then
        return true
    end
    if solid ~= nil then
        local s = tostring(solid):lower()
        return s == "true" or s == "1" or s == "yes" or s == "on"
    end
    return false
end

-- get_meta is the baker's tileset reader, supplied by the caller so this
-- policy has no dependency back into tilesource or the editor context.
function M.scan(map, export_path, room, get_meta)
    local counts = {shaped_tiles=0, solid_objects=0}
    local diagnostics = {}
    local primary = Selection.select_primary_tileset(map)
    local meta = primary and get_meta(primary, export_path)
    local firstgid = tonumber(primary and primary.firstgid)
    local lastgid = Selection.TILED_GID_MASK
    for _, ts in ipairs(map.tilesets or {}) do
        local start = tonumber(ts.firstgid)
        if start and firstgid and start > firstgid then lastgid = math.min(lastgid, start - 1) end
    end
    local states = Split.state_layer_names(map)
    for _, entry in ipairs(Background.flatten_tiled_layers(map.layers)) do
        local layer = entry.layer
        if layer.type == "tilelayer" then
            local shaped = 0
            for _, chunk in ipairs(layer.chunks or {layer}) do
                local data = Regen.decode_tiled_layer_data({data=chunk.data,
                    encoding=chunk.encoding or layer.encoding, compression=chunk.compression or layer.compression}, room, layer.name)
                for _, raw in ipairs(type(data) == "table" and data or {}) do
                    local gid = Selection.decode_gid_value(raw)
                    if firstgid and gid >= firstgid and gid <= lastgid
                        and meta and meta.tile_collision and meta.tile_collision[gid - firstgid] then
                        shaped = shaped + 1
                    end
                end
            end
            if shaped > 0 and M.scrolls(entry) then
                local fx, fy = factor(entry.parallaxx), factor(entry.parallaxy)
                local factors = fx == fy and fx or ("X " .. fx .. ", Y " .. fy)
                diagnostics[#diagnostics+1] = {severity="warning",code="scrolling_layer_collision",
                    room=room,layer=layer.name,file=export_path,property="parallaxx/parallaxy",
                    message="Room " .. tostring(room) .. ": layer " .. tostring(layer.name)
                        .. " scrolls (Parallax " .. factors .. ") and uses tiles with collision shapes; scrolling layers never collide.",
                    fix="Use tiles without collision shapes there, or set its Parallax to 1."}
            elseif not M.scrolls(entry) and not Regen.is_tag_tile_layer(layer.name)
                and not (states[layer.name] and states[layer.name].collision == "none") then
                counts.shaped_tiles = counts.shaped_tiles + shaped
            end
        elseif layer.type == "objectgroup" then
            for _, object in ipairs(layer.objects or {}) do
                if entry.visible ~= false and object.visible ~= false and object_has_solid_collision_type(object) then
                    counts.solid_objects = counts.solid_objects + 1
                end
            end
        end
    end
    if counts.shaped_tiles == 0 and counts.solid_objects == 0 then
        diagnostics[#diagnostics+1] = {severity="warning",code="no_room_collision",room=room,file=export_path,
            message="Room " .. tostring(room) .. ": no collision authored.",
            fix="Paint tiles with Tile Collision Editor shapes on a layer that does not scroll, or add Solid Box/Slope objects before playtesting."}
    end
    return counts, diagnostics
end

return M
