local Kit = require "hooks.core.bake_kit"
local M = {TYPES={"strike_switch"}}
function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local x, y, _, _, w, h = Kit.rect(C, room, obj, defold_y, 16, 16, 32, 32)
    local name = room.id .. "_strike_switch_" .. obj.id .. ".go"
    local solid = Kit.bool(C, obj, "solid", false).value == "true"
    C.write_if_changed(C.join(C.PATH.generated_go, name), C.gen_strike_switch_go(w, h, solid, false))
    local props = {
        Kit.text(C, obj, "switch_id", obj.name or ("switch_" .. room.id .. "_" .. obj.id)),
        Kit.text(C, obj, "target_id", ""),
        C.text_prop("room_id", room.id, ""),
        C.text_prop("persist_key", room.id .. "_" .. obj.id, ""),
        Kit.bool(C, obj, "starts_on", false), Kit.bool(C, obj, "persist_state", false),
        Kit.text(C, obj, "mode", "toggle"), Kit.text(C, obj, "accepts", "any"),
        Kit.number(C, obj, "timer_seconds", 5), Kit.number(C, obj, "cooldown", -1),
        Kit.bool(C, obj, "accept_enemy_hits", false),
        Kit.text(C, obj, "message_on", "activate"), Kit.text(C, obj, "message_off", "deactivate"),
        Kit.text(C, obj, "call_landing", ""),
        Kit.text(C, obj, "set_flag_on", ""), Kit.text(C, obj, "set_flag_off", ""),
        Kit.text(C, obj, "requires_flag", ""),
    }
    for _, id in ipairs({"sound_on", "sound_off", "sound_reject", "tick_sound"}) do
        local prop = Kit.text(C, obj, id, "")
        prop.value = Kit.opt(prop.value)
        props[#props+1] = prop
    end
    Kit.instance(C, room, obj_id, C.GENERATED_ROOMS_RESOURCE_DIR .. "/" .. name, x, y, props)
    return true
end
return M
