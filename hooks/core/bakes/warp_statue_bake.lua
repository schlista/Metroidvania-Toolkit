local Kit = require "hooks.core.bake_kit"
local M = {TYPES = {"warp_statue"}}

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local props = {
        Kit.text(C, obj, "statue_id", obj_id),
        Kit.text(C, obj, "label", "Return to checkpoint"), Kit.number(C, obj, "range", 96),
        Kit.text(C, obj, "requires_flag", ""), Kit.number(C, obj, "cost_currency", 0),
        Kit.number(C, obj, "cooldown", 1), Kit.number(C, obj, "fade_out", 0.5),
        Kit.number(C, obj, "fade_in", 0.5), Kit.bool(C, obj, "show_toast", true),
        Kit.text(C, obj, "toast_success", "Returned to your checkpoint"),
        Kit.text(C, obj, "toast_fail", "No checkpoint to return to"),
        Kit.text(C, obj, "toast_cost", ""),
        Kit.text(C, obj, "toast_blocked", "You cannot return right now"),
        Kit.text(C, obj, "set_flag", ""),
    }
    for _, sound in ipairs({{"sound_warp", "fast_travel"}, {"sound_fail", "gate_locked"}}) do
        local prop = Kit.text(C, obj, sound[1], sound[2])
        prop.value = Kit.opt(prop.value)
        props[#props + 1] = prop
    end
    local prototype = C.visual_helpers.resolve_visual_proto(room.id, obj, obj_type,
        "/developer/game/prefabs/warp_statue.go")
    Kit.instance(C, room, obj_id, prototype, obj.x, defold_y, props)
    return true
end
return M
