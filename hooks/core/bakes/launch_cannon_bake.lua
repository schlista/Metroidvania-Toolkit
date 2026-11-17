local Kit = require "hooks.core.bake_kit"
local M = {TYPES = {"launch_cannon"}}

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local px, py, _, _, w, h = Kit.rect(C, room, obj, defold_y, 48, 48, 96, 96)
    local name = room.id .. "_launch_cannon_" .. obj.id .. ".go"
    C.write_if_changed(C.join(C.PATH.generated_go, name),
        C.gen_bounce_pad_go(w, h, "/mvtk/prefabs/launch_cannon.script", "interactable", 48, 48, {"player"}))
    local id = Kit.opt(C.get_prop_value(obj, "cannon_id"))
    if id == "" then id = obj_id end
    local props = {C.text_prop("cannon_id", id, ""), C.text_prop("room_id", room.id, ""),
        Kit.text(C, obj, "aim_mode", "fixed"), Kit.text(C, obj, "fire_on", "jump"),
        C.text_prop("breaks_action", Kit.opt(C.get_prop_value(obj, "breaks_action")), ""),
        C.text_prop("sound_id", Kit.opt(C.get_prop_value(obj, "sound_id")), ""),
        Kit.number(C, obj, "angle", 45), Kit.number(C, obj, "sweep_range", 90),
        Kit.number(C, obj, "sweep_speed", 60), Kit.number(C, obj, "auto_delay", 1),
        Kit.number(C, obj, "launch_speed", 2400), Kit.number(C, obj, "control_lock_time", 0.35),
        Kit.number(C, obj, "cooldown", 0.5), Kit.bool(C, obj, "keep_momentum", true)}
    Kit.instance(C, room, obj_id, C.GENERATED_ROOMS_RESOURCE_DIR .. "/" .. name, px, py, props)
    return true
end

return M
