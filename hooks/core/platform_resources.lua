-- Bake moving-platform art from the regenerated room tilemap. Reading the
-- Defold cells preserves tilesource-local indices and authored flip/rotation
-- flags, including tile 0 (the first real tile, not an empty placeholder).
local TilemapText = require "hooks.core.elevator_resources"

local M = {}

function M.capture(source_text, opts)
    opts = opts or {}
    local parsed, err = TilemapText.parse_tilemap(source_text)
    if not parsed then return nil, err end
    local tw, th = tonumber(opts.tile_width), tonumber(opts.tile_height)
    if not tw or not th or tw <= 0 or th <= 0 then return nil, "invalid_tile_size" end
    local left, bottom = tonumber(opts.x) or 0, tonumber(opts.y) or 0
    local min_x, min_y = math.floor(left / tw), math.floor(bottom / th)
    local max_x = math.ceil((left + (tonumber(opts.width) or tw)) / tw) - 1
    local max_y = math.ceil((bottom + (tonumber(opts.height) or th)) / th) - 1

    -- Current room art is authored on art/player; old exports used environment.
    -- Tilemap regeneration flattens those group paths to their leaf layer ids.
    local requested = tostring(opts.source_layer or ""):match("([^/]+)$")
    local candidates = requested and requested ~= "" and requested ~= "none"
        and { requested } or { "player", "environment" }
    for _, wanted in ipairs(candidates) do
        for _, layer in ipairs(parsed.layers) do
            if layer.id == wanted then
                local cells = {}
                for _, cell in ipairs(layer.cells) do
                    if cell.x >= min_x and cell.x <= max_x and cell.y >= min_y and cell.y <= max_y then
                        cells[#cells + 1] = {
                            x = cell.x - min_x, y = cell.y - min_y,
                            tile = cell.tile, h_flip = cell.h_flip,
                            v_flip = cell.v_flip, rotate90 = cell.rotate90,
                        }
                    end
                end
                if #cells > 0 then
                    return {
                        tilemap = TilemapText.serialize_tilemap({
                            top_lines = {
                                string.format('tile_set: "%s"', parsed.tile_set),
                                'material: "/builtins/materials/tile_map.material"',
                            },
                            layers = {{
                                pre_lines = { '  id: "solid"', '  z: 0.1',
                                    '  is_visible: ' .. tostring(layer.is_visible or 1) },
                                cells = cells,
                            }},
                        }),
                        source_layer = wanted,
                        x = min_x * tw, y = min_y * th,
                        width = (max_x - min_x + 1) * tw,
                        height = (max_y - min_y + 1) * th,
                        copied_cells = #cells,
                    }
                end
            end
        end
    end
    return nil, requested and ("no_platform_art_on_" .. requested) or "no_platform_art_on_player_or_environment"
end

function M.vehicle_enabled(obj, get)
    local control = get(obj, "vehicle_control")
    return control ~= nil and control ~= "" and control ~= "none"
end

-- Shared bake/validation checks; name lookup feeds the existing offset-aware
-- path resolver. Return one contextual error, then let the caller raise once.
function M.vehicle_tracks(map, obj, get)
    if not M.vehicle_enabled(obj, get) then return {enabled=false} end
    local function fail(code, message)
        return nil, "Vehicle object " .. tostring(obj.id) .. ": " .. message, code
    end
    if get(obj, "platform_type") ~= "path" or not get(obj, "path_name") or get(obj, "path_name") == "" then
        return fail("vehicle_needs_path", "choose Path and a Path name; draw tracks through open space inside this room.")
    end
    local function resolve(name)
        local ids = {}
        local function visit(layers)
            for _, layer in ipairs(layers or {}) do
                for _, o in ipairs(layer.objects or {}) do if o.name == name then ids[#ids+1] = o.id end end
                visit(layer.layers)
            end
        end
        visit(map.layers)
        if #ids ~= 1 then return nil, "track '" .. tostring(name) .. "' must name exactly one polyline in this room" end
        local height = (map.height or 0)*(map.tileheight or 0)
        local encoded, points = require("hooks.core.path_points").resolve(map, ids[1], height, 0, 0, nil, obj.id)
        -- path_points words its errors for Zip Line path_ref; name the vehicle's track instead.
        if not encoded then
            return nil, "track '" .. tostring(name) .. "' must be a visible, unrotated polyline with at least 2 distinct points"
        end
        local width = (map.width or 0)*(map.tilewidth or 0)
        for _, p in ipairs(points) do
            if p.x < 0 or p.y < 0 or p.x > width or p.y > height then
                return nil, "track '" .. name .. "' leaves the room; move every point inside the room bounds"
            end
        end
        return points
    end
    local points, err = resolve(get(obj, "path_name"))
    if not points then return fail("vehicle_needs_path", err) end
    local alt_name = get(obj, "vehicle_alt_path")
    local alt
    if alt_name and alt_name ~= "" and alt_name ~= "none" then
        alt, err = resolve(alt_name)
        if not alt then return fail("vehicle_alt_path_detached", err) end
        local K = require "mvtk.world.kinematic_path"
        if not require("mvtk.world.path_vehicle").junction(K.polyline(points), alt[1], 2) then
            return fail("vehicle_alt_path_detached", "the second track must start on the first track (within 2 px)")
        end
    end
    return {enabled=true, points=points, alternate=alt}
end

function M.vehicle_props(props, obj, get, Prop, collision_id)
    if not M.vehicle_enabled(obj, get) then return props end
    for _, entry in ipairs({{"vehicle_max_speed",400},{"vehicle_acceleration",600},
        {"vehicle_brake",1200},{"vehicle_drag",0},{"vehicle_return_delay",2}}) do
        props[#props+1] = Prop.number(entry[1], get(obj, entry[1]), entry[2])
    end
    for _, entry in ipairs({{"vehicle_control",""},{"vehicle_end","stop"},
        {"vehicle_switch_id",""},{"vehicle_alt_path",""}}) do
        local value = get(obj, entry[1])
        if value == nil then value = entry[2] end
        if value == "none" then value = "" end
        props[#props+1] = Prop.text(entry[1], value)
    end
    props[#props+1] = Prop.bool("vehicle_rider_walks", get(obj, "vehicle_rider_walks"), false)
    if get(obj, "vehicle_float") == true then
        props[#props+1] = Prop.bool("vehicle_float", true, false)
        props[#props+1] = Prop.number("vehicle_float_offset", get(obj, "vehicle_float_offset"), 16)
    end
    props[#props+1] = Prop.text("vehicle_collision_id", collision_id)
    return props
end

return M
