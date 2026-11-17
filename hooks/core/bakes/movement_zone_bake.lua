local Kit = require "hooks.core.bake_kit"
local M = {TYPES = {"movement_zone"}}
function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local px, py, _, _, w, h = Kit.rect(C, room, obj, defold_y, 128, 128, 256, 256)
    local name = room.id .. "_movement_zone_" .. obj.id .. ".go"
    C.write_if_changed(C.join(C.PATH.generated_go, name),
        C.gen_collision_zone_go("/mvtk/prefabs/movement_zone.script", w, h, 256, 256))
    local id = Kit.opt(C.get_prop_value(obj, "movement_zone_id"))
    if id == "" then id = obj_id end
    Kit.instance(C, room, obj_id, C.GENERATED_ROOMS_RESOURCE_DIR .. "/" .. name, px, py, {
        C.text_prop("movement_zone_id", id, ""), C.text_prop("room_id", room.id, ""),
        Kit.text(C, obj, "preset", "low_gravity"),
        Kit.number(C, obj, "gravity_mult", -1), Kit.number(C, obj, "max_fall_mult", -1),
        Kit.number(C, obj, "speed_mult", -1), Kit.number(C, obj, "jump_mult", -1),
        Kit.number(C, obj, "sink_speed", -1), Kit.bool(C, obj, "enabled", true),
    })
    return true
end
return M
