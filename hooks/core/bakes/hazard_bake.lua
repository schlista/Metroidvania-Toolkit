local OP = require "mvtk.tiled.object_props"
local Kit = require "hooks.core.bake_kit"
local Points = require "hooks.core.path_points"
local M = {TYPES = {"hazard"}}

-- Shared with relationship validation. No engine/editor dependency.
function M.reference(map, ref, shape)
    local id = tonumber(type(ref) == "table" and ref.id or ref)
    local target, state
    local function visit(layers, ox, oy, visible, templates)
        for _, layer in ipairs(layers or {}) do
            local x, y = ox + (tonumber(layer.offsetx) or 0), oy + (tonumber(layer.offsety) or 0)
            local shown = visible and layer.visible ~= false
            local on_templates = templates or layer.name == "templates"
            for _, obj in ipairs(layer.objects or {}) do
                if id and tonumber(obj.id) == id then
                    target, state = obj, {x=x,y=y,visible=shown and obj.visible ~= false,templates=on_templates}
                end
            end
            visit(layer.layers, x, y, shown, on_templates)
        end
    end
    visit(map and map.layers, 0, 0, true, false)
    local fix = "; select a visible, unrotated " .. tostring(shape or "object") .. " on an object layer outside templates in this map."
    if not target then return nil, "is missing or outside this map" .. fix end
    if shape == nil then return target, state end
    if not state.visible then return nil, "selects a hidden object" .. fix end
    if state.templates then return nil, "selects an object on templates" .. fix end
    if (tonumber(target.rotation) or 0) % 360 ~= 0 then return nil, "selects a rotated object" .. fix end
    if shape == "point" and not (target.point == true or target.shape == "point") then
        return nil, "must select a point" .. fix
    end
    if shape == "polyline" and (type(target.polyline) ~= "table" or #target.polyline < 2) then
        return nil, "must select a polyline with at least 2 points" .. fix
    end
    return target, state
end

-- Preserve gen_collection's existing sentinel handling, including whitespace.
local function opt(value)
    if value == nil then return "" end
    local text = tostring(value)
    if text == "" or text == "none" then return "" end
    return value
end

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local rid, map_tile_w, map_tile_h = room.id, room.tile_w, room.tile_h
    local rect_center_and_scale, join, PATH = C.rect_center_and_scale, C.join, C.PATH
    local write_if_changed, info = C.write_if_changed, C.info
    local get_prop_value = C.get_prop_value
    local number_to_proto, bool_to_proto = C.number_to_proto, C.bool_to_proto
    local px, py, _, _, w, h = rect_center_and_scale(obj, defold_y, map_tile_w, map_tile_h, 64, 32, 128, 64)
    local drawn_x, drawn_y = px, py
    local hazard_go_name = string.format("%s_hazard_%d.go", rid, obj.id)
    local hazard_go_path = join(PATH.generated_go, hazard_go_name)
    local hazard_proto = require("mvtk.editor.shared_proto").generated_dir(C) .. "/" .. hazard_go_name
    local hazard_id = get_prop_value(obj, "hazard_id") or obj.name or string.format("hazard_%s_%d", rid, obj.id)
    local props = {
        { id = "hazard_id", value = hazard_id, type = "PROPERTY_TYPE_TEXT" },
        { id = "hazard_type", value = get_prop_value(obj, "hazard_type") or "spikes", type = "PROPERTY_TYPE_TEXT" },
        { id = "damage", value = number_to_proto(get_prop_value(obj, "damage"), 1), type = "PROPERTY_TYPE_NUMBER" },
        { id = "damage_interval", value = number_to_proto(get_prop_value(obj, "damage_interval"), 0.5), type = "PROPERTY_TYPE_NUMBER" },
        { id = "stun_t", value = number_to_proto(get_prop_value(obj, "stun_t"), -1), type = "PROPERTY_TYPE_NUMBER" },
        { id = "knockback_force", value = number_to_proto(OP.get_via(get_prop_value, obj, "knockback_force"), 300), type = "PROPERTY_TYPE_NUMBER" },
        { id = "required_resistance", value = opt(OP.get_via(get_prop_value, obj, "required_resistance", "")), type = "PROPERTY_TYPE_TEXT" },
        { id = "instant_kill", value = bool_to_proto(get_prop_value(obj, "instant_kill"), false), type = "PROPERTY_TYPE_BOOLEAN" },
        { id = "on_contact", value = get_prop_value(obj, "on_contact") or "", type = "PROPERTY_TYPE_TEXT" },
        { id = "return_damage", value = number_to_proto(get_prop_value(obj, "return_damage"), -1), type = "PROPERTY_TYPE_NUMBER" },
        { id = "enabled", value = bool_to_proto(get_prop_value(obj, "enabled"), true), type = "PROPERTY_TYPE_BOOLEAN" },
        { id = "sound_on_hit", value = get_prop_value(obj, "sound_on_hit") or "", type = "PROPERTY_TYPE_TEXT" },
        { id = "retractable", value = bool_to_proto(get_prop_value(obj, "retractable"), false), type = "PROPERTY_TYPE_BOOLEAN" },
        { id = "retract_time", value = number_to_proto(get_prop_value(obj, "retract_time"), 2.0), type = "PROPERTY_TYPE_NUMBER" },
        { id = "extend_time", value = number_to_proto(get_prop_value(obj, "extend_time"), 2.0), type = "PROPERTY_TYPE_NUMBER" },
        { id = "start_retracted", value = bool_to_proto(get_prop_value(obj, "start_retracted"), false), type = "PROPERTY_TYPE_BOOLEAN" },
        { id = "arena_id", value = get_prop_value(obj, "arena_id") or "", type = "PROPERTY_TYPE_TEXT" },
        { id = "active_phases", value = get_prop_value(obj, "active_phases") or "", type = "PROPERTY_TYPE_TEXT" },
        { id = "pattern", value = opt(get_prop_value(obj, "pattern")), type = "PROPERTY_TYPE_TEXT" },
        { id = "pattern_speed", value = number_to_proto(get_prop_value(obj, "pattern_speed"), 1.0), type = "PROPERTY_TYPE_NUMBER" },
        -- Retract visuals (painted spike tiles) need the zone size and layer.
        { id = "zone_width", value = number_to_proto(w, 0), type = "PROPERTY_TYPE_NUMBER" },
        { id = "zone_height", value = number_to_proto(h, 0), type = "PROPERTY_TYPE_NUMBER" },
        { id = "retract_visual_layer", value = get_prop_value(obj, "retract_visual_layer") or "player", type = "PROPERTY_TYPE_TEXT" },
        { id = "retract_hides_tiles", value = bool_to_proto(get_prop_value(obj, "retract_hides_tiles"), true), type = "PROPERTY_TYPE_BOOLEAN" },
        { id = "room_id", value = rid, type = "PROPERTY_TYPE_TEXT" },
    }
    -- Arena leaves are optional; leave all unlinked bake bytes unchanged.
    local arena_id = Kit.opt(OP.get_via(get_prop_value, obj, "arena_id"))
    local boss_id = Kit.opt(OP.get_via(get_prop_value, obj, "boss_id"))
    for _, prop in ipairs(props) do
        if prop.id == "arena_id" then prop.value = arena_id end
        if prop.id == "active_phases" then prop.value = OP.get_via(get_prop_value, obj, "active_phases", "") end
    end
    if arena_id ~= "" or boss_id ~= "" then
        props[#props+1] = C.text_prop("boss_id", boss_id, "")
        props[#props+1] = C.bool_prop("hide_when_inactive", OP.get_via(get_prop_value, obj, "hide_when_inactive"), true)
        props[#props+1] = C.number_prop("warn_time", OP.get_via(get_prop_value, obj, "warn_time"), 0)
    end
    -- Explicit authoring bridge for typed arena hazards; empty defaults preserve
    -- frozen rooms. The damage payload integration is owned by the world row.
    local damage_type = Kit.opt(OP.get_via(get_prop_value, obj, "damage_type"))
    if damage_type ~= "" then
        props[#props + 1] = {id="damage_type", value=damage_type, type="PROPERTY_TYPE_TEXT"}
    end
    -- Omit defaults to preserve every existing baked hazard byte for byte.
    local status = Kit.opt(OP.get_via(get_prop_value, obj, "status_effect"))
    if status ~= "" then props[#props+1] = {id="status_effect", value=status, type="PROPERTY_TYPE_TEXT"} end
    for _, row in ipairs({{"status_duration",-1},{"status_chance",1}}) do
        local value = tonumber(OP.get_via(get_prop_value, obj, row[1])) or row[2]
        if value ~= row[2] then props[#props+1] = C.number_prop(row[1], value, row[2]) end
    end
    local kind = Kit.opt(get_prop_value(obj, "motion_type"))
    if kind ~= "" then
        local encoded, points
        if kind == "path" then
            local err
            encoded, err = Points.resolve(room.tiled, get_prop_value(obj, "motion_path_ref"),
                room.map_height, px, py, C.fmt_num, obj.id)
            if not encoded then return nil, room.id .. ": " .. err:gsub("path_ref", "motion_path_ref") end
            -- Paths are editor helpers, outside the gameplay templates layer.
            local ok, problem = M.reference(room.tiled, get_prop_value(obj, "motion_path_ref"), "polyline")
            if not ok then return nil, room.id .. " object " .. obj.id .. ": motion_path_ref " .. problem end
            encoded, points = Points.resolve(room.tiled, get_prop_value(obj, "motion_path_ref"),
                room.map_height, 0, 0, C.fmt_num, obj.id)
            px, py = points[1].x, points[1].y
            encoded = Points.resolve(room.tiled, get_prop_value(obj, "motion_path_ref"),
                room.map_height, px, py, C.fmt_num, obj.id)
        end
        props[#props+1] = C.text_prop("motion_type", kind, "")
        props[#props+1] = C.text_prop("motion_points", encoded or "", "")
        props[#props+1] = C.text_prop("motion_loop", Kit.opt(get_prop_value(obj, "motion_loop")), "pingpong")
        for _, pair in ipairs({{"motion_distance_x",0},{"motion_distance_y",0},{"motion_radius",128},
            {"motion_speed",200},{"motion_offset",0},{"motion_wait",0},
            {"slam_warn",-1},{"slam_rest",-1},{"slam_drop_speed",1200},{"slam_rise_speed",200}}) do
            props[#props+1] = Kit.number(C, obj, pair[1], pair[2])
        end
        if kind == "orbit" then
            local ref = get_prop_value(obj, "motion_pivot_ref")
            local id = tonumber(type(ref) == "table" and ref.id or ref) or 0
            local x, y = -math.abs(tonumber(get_prop_value(obj, "motion_radius")) or 128), 0
            if id ~= 0 then
                local target, state = M.reference(room.tiled, ref, "point")
                if not target then return nil, room.id .. " object " .. obj.id .. ": motion_pivot_ref " .. state end
                x, y = (tonumber(target.x) or 0) + state.x - px, room.map_height - (tonumber(target.y) or 0) - state.y - py
                -- A selected centre point has radius zero, regardless of the fallback field.
                for _, prop in ipairs(props) do
                    if prop.id == "motion_radius" then prop.value = C.number_to_proto(math.sqrt(x*x+y*y), 0) end
                end
            end
            props[#props+1] = C.number_prop("motion_pivot_x", x, 0)
            props[#props+1] = C.number_prop("motion_pivot_y", y, 0)
        end
    end
    local level_mode = Kit.opt(get_prop_value(obj, "level_mode"))
    if level_mode ~= "" then
        props[#props+1] = C.text_prop("level_mode", level_mode, "")
        props[#props+1] = C.text_prop("level_art_layer", get_prop_value(obj,"level_art_layer"), "")
        props[#props+1] = C.text_prop("rise_start", Kit.opt(get_prop_value(obj,"rise_start")), "signal")
        for _, row in ipairs({{"level_offset",0},{"level_speed",96},{"rise_speed",48},
            {"rise_limit",4},{"rise_delay",0}}) do
            props[#props+1] = C.number_prop(row[1], get_prop_value(obj,row[1]), row[2])
        end
        props[#props+1] = C.number_prop("tile_height",room.tile_h,64)
        local offset = tonumber(get_prop_value(obj,level_mode == "rise" and "rise_limit" or "level_offset"))
            or (level_mode == "rise" and 4 or 0)
        if py+h/2+math.max(0,offset*room.tile_h) > room.map_height then
            Kit.warn(C,room,obj,"raised hazard level passes the room top")
        end
    end
    local go_text = C.gen_hazard_zone_go(w, h, level_mode ~= "" and {shape_id="zone"} or nil)
    if kind ~= "" and get_prop_value(obj, "retract_hides_tiles") ~= false and PATH.tilemaps then
        local source_layer = tostring(Kit.opt(get_prop_value(obj, "retract_visual_layer"))):match("^%s*(.-)%s*$"):match("([^/]+)$") or "player"
        if source_layer == "none" then source_layer = "player" end
        local art = require("hooks.core.platform_resources").capture(
            C.read_text(join(PATH.tilemaps, rid .. ".tilemap")), {
                x = drawn_x - w * 0.5, y = drawn_y - h * 0.5,
                width = w, height = h, tile_width = map_tile_w, tile_height = map_tile_h,
                source_layer = source_layer,
            })
        if art then
            local name = string.format("%s_hazard_%d.tilemap", rid, obj.id)
            local path = join(PATH.generated_go, name)
            if write_if_changed(path, art.tilemap) then info("Created " .. path) end
            go_text = require("hooks.core.go_generation").gen_moving_hazard_go(w, h,
                require("mvtk.editor.shared_proto").generated_dir(C) .. "/" .. name, art.x - drawn_x, art.y - drawn_y)
            props[#props+1] = C.bool_prop("moving_art", true, false)
            props[#props+1] = C.number_prop("moving_art_source_x", drawn_x - px, 0)
            props[#props+1] = C.number_prop("moving_art_source_y", drawn_y - py, 0)
            -- Only moving art uses the flattened layer id; static output is frozen.
            for _, prop in ipairs(props) do
                if prop.id == "retract_visual_layer" then prop.value = art.source_layer end
            end
        end
    end
    if write_if_changed(hazard_go_path, go_text) then info("Created " .. hazard_go_path) end
    C.add_prefab_instance(room.rows, obj_id, hazard_proto, px, py, nil, nil, "hazard_zone", props)
    return true
end
return M
