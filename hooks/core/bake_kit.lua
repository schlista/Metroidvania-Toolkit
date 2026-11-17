-- Context-only helpers shared by editor and headless object bakers.
local M = {}

function M.opt(value)
    if value == nil then return "" end
    local trimmed = tostring(value):match("^%s*(.-)%s*$")
    if trimmed == "" or trimmed == "none" then return "" end
    return value
end

function M.text(C, obj, id, default)
    return C.text_prop(id, C.get_prop_value(obj, id), default)
end

function M.number(C, obj, id, default)
    return C.number_prop(id, C.get_prop_value(obj, id), default)
end

function M.bool(C, obj, id, default)
    return C.bool_prop(id, C.get_prop_value(obj, id), default)
end

function M.rect(C, room, obj, defold_y, base_half_w, base_half_h, fallback_w, fallback_h)
    return C.rect_center_and_scale(obj, defold_y, room.tile_w, room.tile_h,
        base_half_w, base_half_h, fallback_w, fallback_h)
end

function M.sized_go(C, room, obj_type, obj, prefab, w, h, base_half_w, base_half_h, fallback_w, fallback_h)
    local name = string.format("%s_%s_%d.go", room.id, obj_type, obj.id)
    local ok, err = C.write_sized_rect_generated_go(C.join(C.PATH.generated_go, name),
        prefab, w, h, base_half_w, base_half_h, fallback_w, fallback_h)
    if not ok then return nil, err end
    -- Resource paths always use "/"; C.join uses the OS file separator.
    return C.GENERATED_ROOMS_RESOURCE_DIR .. "/" .. name
end

function M.instance(C, room, obj_id, prototype, x, y, props)
    C.add_prefab_instance(room.rows, obj_id, prototype, x, y, nil, nil, "script", props)
end

function M.warn(C, room, obj, text)
    print("[CREATE ROOMS][WARNING] " .. tostring(room.id) .. " object " .. tostring(obj.id) .. ": " .. tostring(text))
end

return M
