-- Shared checkpoint destination rule for death respawns and return callers.
local RoomGeometry = require "mvtk.map.streaming.room_geometry"

local M = {}

-- Resolve saved world coordinates against the published layout. Callers that
-- already loaded the layout pass it here; no checkpoint save is read or changed.
function M.resolve(checkpoint, layout)
    if type(checkpoint) ~= "table" then return nil, "no_checkpoint" end
    local x, y = tonumber(checkpoint.x), tonumber(checkpoint.y)
    if not (x and y) then return nil, "no_checkpoint" end
    if layout == nil then
        local LayoutIO = require "mvtk.rooms.layout_io"
        layout = LayoutIO.load({ runtime_preferred = true })
    end
    if not (type(layout) == "table" and type(layout.rooms) == "table" and #layout.rooms > 0) then
        return nil, "no_layout"
    end

    local claimed = RoomGeometry.normalize_room_id(checkpoint.room_id)
    local position = vmath.vector3(x, y, 0)
    for _, room in ipairs(layout.rooms) do
        if type(room) == "table" and tonumber(room.x) and tonumber(room.y)
            and tonumber(room.w) and tonumber(room.h) then
            local room_id = RoomGeometry.normalize_room_id(room.id or room.path)
            local inside = RoomGeometry.point_in_bounds(position, RoomGeometry.make_room_bounds(room))
            if claimed and room_id == claimed then
                if inside then return { position = position, room_id = room_id,
                    position_kind = checkpoint.position_kind } end
                return nil, "room_mismatch"
            end
            if not claimed and inside then return { position = position, room_id = room_id,
                position_kind = checkpoint.position_kind } end
        end
    end
    return nil, claimed and "room_mismatch" or "outside_layout"
end

return M
