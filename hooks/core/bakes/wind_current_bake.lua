local Kit = require "hooks.core.bake_kit"
local M = {TYPES = {"wind_current"}}

-- Match content_relationships.object_default_id, including explicit blanks.
local function current_id(C, room, obj, obj_id)
    local value = C.get_prop_value(obj, "current_id")
    if value == "" then return obj_id end
    local id = value ~= nil and tostring(value):match("^%s*(.-)%s*$") or ""
    if id ~= "" then return id end
    local name = obj.name ~= nil and tostring(obj.name):match("^%s*(.-)%s*$") or ""
    if name ~= "" then return name end
    if obj.name == "" then return obj_id end
    return "current_" .. room.id .. "_" .. obj.id
end

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local x, y, _, _, w, h = Kit.rect(C, room, obj, defold_y, 64, 64, 256, 256)
    local prototype, err = Kit.sized_go(C, room, obj_type, obj,
        "/developer/game/prefabs/wind_current.go", w, h, 64, 64, 256, 256)
    if not prototype then Kit.warn(C, room, obj, err); return false end
    local direction = C.normalize_string_enum(C.get_prop_value(obj, "direction"), "right",
        {left = true, right = true, up = true, down = true})
    local mode = C.normalize_string_enum(C.get_prop_value(obj, "wind_mode"), "push", {push = true, lift = true})
    Kit.instance(C, room, obj_id, prototype, x, y, {
        C.text_prop("current_id", current_id(C, room, obj, obj_id), ""),
        C.text_prop("room_id", room.id, ""), C.text_prop("direction", direction, "right"),
        C.text_prop("wind_mode", mode, "push"), Kit.number(C, obj, "push_speed", 300),
        Kit.number(C, obj, "angle", 0), Kit.number(C, obj, "lift_gravity_multiple", 1.6),
        Kit.number(C, obj, "max_rise_speed", 600), Kit.number(C, obj, "on_seconds", 0),
        Kit.number(C, obj, "off_seconds", 0), Kit.number(C, obj, "start_delay", 0),
        Kit.bool(C, obj, "enabled", true),
    })
    return true
end
return M
