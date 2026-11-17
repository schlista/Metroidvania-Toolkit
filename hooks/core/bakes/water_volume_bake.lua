local Kit = require "hooks.core.bake_kit"
local M = {TYPES = {"water_volume"}}

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local rid, rows, map_tile_w, map_tile_h = room.id, room.rows, room.tile_w, room.tile_h
    local rect_center_and_scale, join, PATH = C.rect_center_and_scale, C.join, C.PATH
    local write_if_changed, info, _C, _visual = C.write_if_changed, C.info, C, C.visual_helpers
    local get_prop_value = C.get_prop_value
    local number_to_proto, bool_to_proto, add_prefab_instance = C.number_to_proto, C.bool_to_proto, C.add_prefab_instance
    local px, py, _, _, w, h = rect_center_and_scale(obj, defold_y, map_tile_w, map_tile_h, 64, 64, 128, 128)
    local water_go_name = string.format("%s_water_volume_%d.go", rid, obj.id)
    local water_go_path = join(PATH.generated_go, water_go_name)
    local water_proto = require("mvtk.editor.shared_proto").generated_dir(C) .. "/" .. water_go_name
    local level_mode = Kit.opt(get_prop_value(obj, "level_mode"))
    if write_if_changed(water_go_path, _C.gen_water_volume_go(w, h, _visual.uses_defold_sprite(obj, obj_type),
        level_mode ~= "" and {shape_id="volume"} or nil)) then
        info("Created " .. water_go_path)
    end
    local water_id = get_prop_value(obj, "water_id") or obj.name or string.format("water_%s_%d", rid, obj.id)
    local props = {
        { id = "water_id", value = water_id, type = "PROPERTY_TYPE_TEXT" },
        { id = "water_type", value = get_prop_value(obj, "water_type") or "water", type = "PROPERTY_TYPE_TEXT" },
        { id = "width", value = number_to_proto(w, 128), type = "PROPERTY_TYPE_NUMBER" },
        { id = "height", value = number_to_proto(h, 128), type = "PROPERTY_TYPE_NUMBER" },
        { id = "swim_enabled", value = bool_to_proto(get_prop_value(obj, "swim_enabled"), true), type = "PROPERTY_TYPE_BOOLEAN" },
        { id = "swim_speed_mult", value = number_to_proto(get_prop_value(obj, "swim_speed_mult"), 0.7), type = "PROPERTY_TYPE_NUMBER" },
        { id = "damage", value = number_to_proto(get_prop_value(obj, "damage"), 0), type = "PROPERTY_TYPE_NUMBER" },
        { id = "damage_interval", value = number_to_proto(get_prop_value(obj, "damage_interval"), 1.0), type = "PROPERTY_TYPE_NUMBER" },
        { id = "current_direction", value = get_prop_value(obj, "current_direction") or "none", type = "PROPERTY_TYPE_TEXT" },
        { id = "current_strength", value = number_to_proto(get_prop_value(obj, "current_strength"), 0), type = "PROPERTY_TYPE_NUMBER" },
        { id = "room_id", value = rid, type = "PROPERTY_TYPE_TEXT" },
        { id = "buoyancy", value = number_to_proto(get_prop_value(obj, "buoyancy"), 0.5), type = "PROPERTY_TYPE_NUMBER" },
        { id = "water_drag", value = number_to_proto(get_prop_value(obj, "water_drag"), 0.85), type = "PROPERTY_TYPE_NUMBER" },
        { id = "oxygen_drain", value = bool_to_proto(get_prop_value(obj, "oxygen_drain"), true), type = "PROPERTY_TYPE_BOOLEAN" },
        { id = "oxygen_drain_rate", value = number_to_proto(get_prop_value(obj, "oxygen_drain_rate"), 1.0), type = "PROPERTY_TYPE_NUMBER" },
        { id = "surface_y_offset", value = number_to_proto(get_prop_value(obj, "surface_y_offset"), 0), type = "PROPERTY_TYPE_NUMBER" },
        { id = "splash_effect", value = bool_to_proto(get_prop_value(obj, "splash_effect"), true), type = "PROPERTY_TYPE_BOOLEAN" },
        { id = "tint_color", value = get_prop_value(obj, "tint_color") or "", type = "PROPERTY_TYPE_TEXT" },
    }
    if level_mode ~= "" then
        props[#props+1] = C.text_prop("level_mode", level_mode, "")
        props[#props+1] = C.text_prop("level_art_layer", get_prop_value(obj, "level_art_layer"), "")
        props[#props+1] = C.text_prop("rise_start", Kit.opt(get_prop_value(obj, "rise_start")) , "signal")
        for _, row in ipairs({{"level_offset",0},{"level_speed",96},{"rise_speed",48},
            {"rise_limit",4},{"rise_delay",0}}) do
            props[#props+1] = C.number_prop(row[1], get_prop_value(obj,row[1]), row[2])
        end
        props[#props+1] = C.number_prop("tile_height",room.tile_h,64)
        local offset = tonumber(get_prop_value(obj,level_mode == "rise" and "rise_limit" or "level_offset"))
            or (level_mode == "rise" and 4 or 0)
        if py+h/2+math.max(0,offset*room.tile_h) > room.map_height then
            Kit.warn(C,room,obj,"raised water level passes the room top")
        end
    end
    add_prefab_instance(rows,obj_id,water_proto,px,py,nil,nil,"script",props)
    return true
end
return M
