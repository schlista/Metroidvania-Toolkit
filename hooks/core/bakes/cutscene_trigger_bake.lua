local Kit = require "hooks.core.bake_kit"
local CutsceneIds = require "mvtk.game.cutscene_ids"
local M = { TYPES = { "cutscene" } }

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local w, h = C.resolve_rect_size_pixels(tonumber(obj.width) or 0, tonumber(obj.height) or 0,
        room.tile_w, room.tile_h, room.tile_w, room.tile_h)
    local props = {
        Kit.text(C, obj, "trigger_id", ""),
        C.text_prop("cutscene_id", CutsceneIds.resolve({
            cutscene_id=C.get_prop_value(obj, "cutscene_id"),
            cutscene_name=C.get_prop_value(obj, "cutscene_name")}, room.id, obj.id), ""),
        Kit.bool(C, obj, "auto_play", true),
        Kit.bool(C, obj, "trigger_once", true),
        Kit.bool(C, obj, "persist_once", true),
        Kit.text(C, obj, "once_flag", ""),
        Kit.bool(C, obj, "consume_on_fire", true),
        Kit.text(C, obj, "requires_flag", ""),
        Kit.text(C, obj, "skip_if_flag", ""),
        Kit.text(C, obj, "set_flag", ""),
        C.number_prop("width", w, room.tile_w),
        C.number_prop("height", h, room.tile_h),
        C.text_prop("room_id", room.id, ""),
        C.number_prop("object_id", obj.id, 0),
    }
    for _, prop in ipairs(props) do
        if prop.type == "PROPERTY_TYPE_TEXT" and prop.id ~= "cutscene_id" and prop.id ~= "room_id" then
            prop.value = Kit.opt(prop.value)
        end
    end
    Kit.instance(C, room, obj_id, "/developer/game/prefabs/cutscene_trigger.go",
        tonumber(obj.x) or 0, (tonumber(defold_y) or 0) - h, props)
    return true
end

return M
