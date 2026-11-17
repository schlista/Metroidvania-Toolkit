local Kit = require "hooks.core.bake_kit"
local M = { TYPES = { "quest_trigger" } }

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local w, h = C.resolve_rect_size_pixels(tonumber(obj.width) or 0, tonumber(obj.height) or 0,
        room.tile_w, room.tile_h, 128, 128)
    local props = {}
    props[#props + 1] = Kit.text(C, obj, "quest_id", "")
    props[#props + 1] = Kit.text(C, obj, "trigger_id", "")
    props[#props + 1] = Kit.text(C, obj, "action", "advance")
    props[#props + 1] = Kit.text(C, obj, "step_id", "")
    props[#props + 1] = Kit.text(C, obj, "once_flag", "")
    props[#props + 1] = Kit.text(C, obj, "requires_quest", "")
    props[#props + 1] = Kit.text(C, obj, "requires_quest_state", "any")
    props[#props + 1] = Kit.text(C, obj, "requires_flag", "")
    props[#props + 1] = Kit.text(C, obj, "skip_if_flag", "")
    props[#props + 1] = Kit.text(C, obj, "set_flag", "")
    props[#props + 1] = Kit.bool(C, obj, "auto_play", true)
    props[#props + 1] = Kit.bool(C, obj, "trigger_once", true)
    props[#props + 1] = Kit.bool(C, obj, "persist_once", true)
    props[#props + 1] = Kit.bool(C, obj, "consume_on_fire", true)
    for _, prop in ipairs(props) do
        if prop.type == "PROPERTY_TYPE_TEXT" then prop.value = Kit.opt(prop.value) end
        if prop.id == "requires_quest_state" and prop.value == "any" then prop.value = "" end
    end
    props[#props + 1] = C.number_prop("width", w, 128)
    props[#props + 1] = C.number_prop("height", h, 128)
    props[#props + 1] = C.text_prop("room_id", room.id, "")
    props[#props + 1] = C.number_prop("object_id", obj.id, 0)
    Kit.instance(C, room, obj_id, "/developer/game/prefabs/quest_trigger.go",
        tonumber(obj.x) or 0, (tonumber(defold_y) or 0) - h, props)
    return true
end
return M
