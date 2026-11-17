local Kit = require "hooks.core.bake_kit"
local M = { TYPES = { "air_pocket" } }

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local px, py, _, _, w, h = Kit.rect(C, room, obj, defold_y, 64, 64, 128, 128)
    local name = room.id .. "_air_pocket_" .. obj.id .. ".go"
    C.write_if_changed(C.join(C.PATH.generated_go, name),
        C.gen_collision_zone_go("/mvtk/prefabs/air_pocket.script", w, h, 128, 128))
    local id = Kit.opt(C.get_prop_value(obj, "air_pocket_id"))
    if id == "" then id = obj_id end
    Kit.instance(C, room, obj_id, C.GENERATED_ROOMS_RESOURCE_DIR .. "/" .. name, px, py, {
        C.text_prop("air_pocket_id", id, ""), C.text_prop("room_id", room.id, ""),
        Kit.number(C, obj, "refill_rate", -1),
    })
    return true
end

return M
