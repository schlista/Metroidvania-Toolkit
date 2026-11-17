local Kit = require "hooks.core.bake_kit"
local Points = require "hooks.core.path_points"
local M = {TYPES = {"zip_line"}}

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local encoded, err = Points.resolve(room.tiled, C.get_prop_value(obj, "path_ref"),
        room.map_height, tonumber(obj.x) or 0, defold_y, C.fmt_num, obj.id)
    if not encoded then return nil, err end
    local props = {Kit.text(C, obj, "zip_id", obj_id), C.text_prop("room_id", room.id, ""),
        C.text_prop("path_points", encoded, ""), Kit.text(C, obj, "label", "Ride"),
        Kit.number(C, obj, "range", 96), Kit.number(C, obj, "speed", 800),
        Kit.number(C, obj, "exit_boost", 0), Kit.bool(C, obj, "auto_start", false)}
    local prototype = C.visual_helpers.resolve_visual_proto(room.id, obj, obj_type,
        "/developer/game/prefabs/zip_line.go")
    Kit.instance(C, room, obj_id, prototype, obj.x, defold_y, props)
    return true
end
return M
