-- Countdown Zone (WM09): a baked rectangle that starts, finishes or cancels
-- the countdown it names. main.script owns the overlap; no collision object.
local Kit = require "hooks.core.bake_kit"
local M = { TYPES = { "countdown_zone" } }
M.ROLES = { start = true, finish = true, cancel = true }

local function trimmed(C, obj, id)
    local value = Kit.opt(C.get_prop_value(obj, id))
    return tostring(value):match("^%s*(.-)%s*$")
end

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local w, h = C.resolve_rect_size_pixels(tonumber(obj.width) or 0, tonumber(obj.height) or 0,
        room.tile_w, room.tile_h, 128, 128)
    local countdown_id = trimmed(C, obj, "countdown_id")
    local role = trimmed(C, obj, "role")
    if role == "" then role = "start" end
    -- Prepare & Check's countdown checks name unknown ids; the bake only warns.
    if countdown_id == "" then Kit.warn(C, room, obj, "Countdown Zone has no countdown_id; it does nothing") end
    if not M.ROLES[role] then Kit.warn(C, room, obj, "Countdown Zone role must be start, finish or cancel; got " .. role) end
    local props = {
        C.text_prop("countdown_id", countdown_id, ""),
        C.text_prop("role", role, "start"),
        C.number_prop("width", w, 128),
        C.number_prop("height", h, 128),
        C.text_prop("room_id", room.id, ""),
        C.number_prop("object_id", obj.id, 0),
    }
    Kit.instance(C, room, obj_id, "/developer/game/prefabs/countdown_zone.go",
        tonumber(obj.x) or 0, (tonumber(defold_y) or 0) - h, props)
    return true
end
return M
