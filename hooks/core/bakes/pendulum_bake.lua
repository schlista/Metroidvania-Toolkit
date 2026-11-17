local Kit = require "hooks.core.bake_kit"
local M = {TYPES = {"pendulum_hazard"}}

-- Keep identity identical to content_relationships.object_default_id.
local function pendulum_id(C, room, obj, obj_id)
    local value = C.get_prop_value(obj, "pendulum_id")
    if value == "" then return obj_id end
    local id = value ~= nil and tostring(value):match("^%s*(.-)%s*$") or ""
    if id ~= "" then return id end
    local name = obj.name ~= nil and tostring(obj.name):match("^%s*(.-)%s*$") or ""
    if name ~= "" then return name end
    if obj.name == "" then return obj_id end
    return "pendulum_" .. room.id .. "_" .. obj.id
end

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local w, h = tonumber(obj.width) or 64, tonumber(obj.height) or 0
    if h <= 0 then return nil, "Pendulum object " .. tostring(obj.id) .. ": draw it as a rectangle from pivot to blade" end
    if w <= 0 then w = 64 end
    local bw = tonumber(C.get_prop_value(obj, "blade_width")) or 0
    if bw <= 0 then bw = w end
    local bh = tonumber(C.get_prop_value(obj, "blade_height")) or 48
    local n = C.fmt_num
    local shape = 'type: COLLISION_OBJECT_TYPE_TRIGGER\nmass: 0.0\nfriction: 0.0\nrestitution: 0.0\n'
        .. 'group: "hazard"\nmask: "player"\nembedded_collision_shape {\n'
        .. 'shapes { shape_type: TYPE_BOX position { y: ' .. n(-(h - bh / 2)) .. ' } rotation { w: 1 } index: 0 count: 3 }\n'
        .. 'data: ' .. n(bw / 2) .. '\ndata: ' .. n(bh / 2) .. '\ndata: 10.0\n}\n'
    local text = 'components { id: "script" component: "/mvtk/hazards/pendulum_hazard.script" }\n'
        .. 'embedded_components { id: "blade" type: "collisionobject" data: "' .. C.proto_escape(shape) .. '" }\n'
    local name = room.id .. "_pendulum_hazard_" .. obj.id .. ".go"
    C.write_if_changed(C.join(C.PATH.generated_go, name), text)
    local props = {C.text_prop("pendulum_id", pendulum_id(C, room, obj, obj_id), ""),
        C.text_prop("room_id", room.id, ""), C.number_prop("rect_width", w, 64), C.number_prop("rect_height", h, 256),
        Kit.text(C, obj, "on_contact", ""), Kit.number(C, obj, "return_damage", -1),
        Kit.bool(C, obj, "start_from_right", false), Kit.bool(C, obj, "enabled", true)}
    for _, pair in ipairs({{"arc_degrees", 70}, {"swing_seconds", 1.2}, {"start_delay", 0},
        {"blade_width", 0}, {"blade_height", 48}, {"damage", 1}, {"damage_cooldown", 0.5},
        {"stun_t", -1}, {"knockback_force", 300}, {"knockback_lift", 150}}) do
        props[#props + 1] = Kit.number(C, obj, pair[1], pair[2])
    end
    local dtype = Kit.opt(C.get_prop_value(obj, "damage_type"))
    if dtype ~= "" then props[#props + 1] = C.text_prop("damage_type", dtype, "") end
    Kit.instance(C, room, obj_id, C.GENERATED_ROOMS_RESOURCE_DIR .. "/" .. name,
        (tonumber(obj.x) or 0) + w / 2, room.map_height - (tonumber(obj.y) or 0), props)
    return true
end
return M
