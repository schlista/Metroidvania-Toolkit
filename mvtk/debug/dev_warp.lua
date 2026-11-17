-- Debug menu arrival requests use the ordinary player streaming/save path.
local Rooms = require "mvtk.map.streaming.room_manager"
local Geometry = require "mvtk.map.streaming.room_geometry"
local Census = require "mvtk.world.census"
local Tile = require "developer.config.tile_settings"
local Prefab = require "mvtk.prefabs.prefab_utils"
local C = require "mvtk.core.constants"
local M = {}

function M.rooms() return Rooms.list_rooms() end

local function priority(kind)
    if kind == "player_start" then return 1 end
    if kind == "save_point" then return 2 end
    if kind == "fast_travel" or kind == "map_station" or kind == "health_station" or kind == "energy_station" then return 3 end
end

function M.target(room_id)
    local err = Rooms.get_room_error(room_id)
    if err then return nil, err end
    local room = Rooms.get_room_data(room_id)
    local bounds = Geometry.make_room_bounds(room)
    if not bounds then return nil, "unknown_room" end
    local best, rank, kind
    -- travel_points has already added compute_spawn_xy (including collection
    -- offsets). Its x/y are world positions; never add the origin twice.
    for _, point in ipairs(Census.travel_points()) do
        local p = priority(point.kind)
        if point.room_id == room_id and p and (not rank or p < rank)
            and Geometry.point_in_bounds(point, bounds) then
            best, rank, kind = point, p, point.kind
        end
    end
    -- Ordinary saves and stations may not be fast-travel destinations. Raw
    -- census entries are collection-relative, so add the baked collection's
    -- world origin (layout x+ox/y+oy PLUS collection_offset_x/y) here.
    local origin_x, origin_y = Geometry.compute_spawn_xy(room)
    for _, entry in ipairs(Census.entries(room_id)) do
        local p = priority(entry.type)
        local point = { x = origin_x + (entry.x or 0), y = origin_y + (entry.y or 0), facing = entry.facing }
        if p and (not rank or p < rank) and Geometry.point_in_bounds(point, bounds) then
            best, rank, kind = point, p, entry.type
        end
    end
    if best then return vmath.vector3(best.x, best.y, 0), rank == 3 and "station" or kind, best.facing end
    local door = Rooms.get_room_doors(room_id)[1]
    if door then
        -- Door centres are bounds-relative: layout x+ox/y+oy + cx/cy.
        -- Collection offsets do NOT participate in doorway placement.
        local x, y = bounds.min_x + door.cx, bounds.min_y + door.cy
        local side = Geometry.normalize_side(door.side)
        if side == "left" then x = x + Tile.width * 1.5
        elseif side == "right" then x = x - Tile.width * 1.5
        elseif side == "up" then y = y - Tile.height * 1.5
        elseif side == "down" then y = y + Tile.height * 1.5 end
        local point = vmath.vector3(x, y, 0)
        if Geometry.point_in_bounds(point, bounds) then return point, "door" end
    end
    return vmath.vector3((bounds.min_x + bounds.max_x) / 2, (bounds.min_y + bounds.max_y) / 2, 0), "centre"
end

function M.warp(room_id)
    local position, kind, facing = M.target(room_id)
    if not position then return false, "Cannot warp: " .. tostring(kind) end
    -- No go.* here: the requester is a GUI script. RoomArrival reports any
    -- asynchronous failure and releases its fade/pin. Normal saving stays on.
    local ok, err = pcall(msg.post, C.URL.PLAYER, C.MSG.SET_POSITION, {
        position = position, room_id = room_id, facing = facing, position_kind = "feet",
        update_camera = true, arrival_fade_out = 0.3, reset_motion = true, reason = "dev_warp",
    })
    if not ok then return false, "Cannot warp: " .. tostring(err) end
    if kind == "centre" then Prefab.toast("No landing marker or door: warping to room centre.", 4) end
    return true
end

return M
