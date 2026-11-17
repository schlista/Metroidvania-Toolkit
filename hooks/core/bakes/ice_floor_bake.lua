local Kit = require "hooks.core.bake_kit"
local Ice = require "hooks.core.ice_layer_bake"
local M = {TYPES = {"ice_floor"}}

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local x, y, _, _, w, h = Kit.rect(C, room, obj, defold_y, 128, 16, 256, 32)
    local margin = Ice.probe_margin()
    local prototype, err = Kit.sized_go(C, room, obj_type, obj,
        "/developer/game/prefabs/ice_floor.go", w, h + margin, 128, 16, 256, 32)
    if not prototype then Kit.warn(C, room, obj, err); return false end
    Kit.instance(C, room, obj_id, prototype, x, y + margin / 2, {
        Kit.text(C, obj, "ice_id", ""), Kit.text(C, obj, "preset", "ice"),
        Kit.number(C, obj, "accel_mult", -1), Kit.number(C, obj, "decel_mult", -1),
        Kit.number(C, obj, "turn_brake_mult", -1), Kit.bool(C, obj, "enabled", true),
    })
    return true
end
return M
