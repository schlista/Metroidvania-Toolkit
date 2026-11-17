local Kit = require "hooks.core.bake_kit"
local M = { TYPES = { "grapple_point" } }

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local px = (tonumber(obj.x) or 0) + ((tonumber(obj.width) or 0) * 0.5)
    local py = room.map_height - (tonumber(obj.y) or 0) - ((tonumber(obj.height) or 0) * 0.5)
    -- Fixed anchors expose a sprite and a grapple collider only.
    Kit.instance(C, room, obj_id, "/developer/game/prefabs/grapple_point.go", px, py)
    return true
end

return M
