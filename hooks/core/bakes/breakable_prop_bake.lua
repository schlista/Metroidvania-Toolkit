local Kit = require "hooks.core.bake_kit"
local Layers = require "mvtk.editor.tilemap_regen"
local M = {TYPES = {"breakable_prop"}}

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local x, y, _, _, w, h = Kit.rect(C, room, obj, defold_y, 32, 32, 64, 64)
    local layer = Kit.opt(C.get_prop_value(obj, "painted_layer"))
    local interact = Kit.bool(C, obj, "break_on_interact", false)
    local tiles, offset_x, offset_y
    if layer ~= "" and (Layers.is_control_tile_layer(layer) or Layers.is_tag_tile_layer(layer)) then
        Kit.warn(C, room, obj, "painted_layer must be a decorative layer; no tiles cut")
        layer = ""
    elseif layer ~= "" and (tonumber(obj.rotation) or 0) ~= 0 then
        Kit.warn(C, room, obj, "painted_layer requires an unrotated rectangle; no tiles cut")
        layer = ""
    end
    if layer ~= "" then
        if not room.chunk_failed and not room.chunk_ctx then
            room.chunk_ctx = C.ensure_pushable_bake_context(room.id, room.tile_w, room.tile_h)
            room.chunk_failed = room.chunk_ctx == nil
        end
        local captured
        tiles, captured, offset_x, offset_y = C.bake_object_chunk_tilemap(
            room.chunk_ctx, room.id, obj, defold_y, w, h, {
                kind = "breakable_prop", layer_filter = function(name) return name == layer end,
            })
        if not captured then
            -- A missing/empty layer is a content warning; still bake an editable prop.
            tiles = nil
            Kit.warn(C, room, obj, "painted_layer has no cut cells: " .. layer)
        end
    end
    local function trigger(id, group, mask)
        local shape = 'type: COLLISION_OBJECT_TYPE_TRIGGER\nmass: 0.0\nfriction: 0.0\nrestitution: 0.0\n'
            .. 'group: "' .. group .. '"\nmask: "' .. mask .. '"\nembedded_collision_shape {\n'
            .. 'shapes { shape_type: TYPE_BOX position {} rotation { w: 1 } index: 0 count: 3 }\n'
            .. 'data: ' .. C.fmt_num(w / 2) .. '\ndata: ' .. C.fmt_num(h / 2) .. '\ndata: 10.0\n}\n'
        return 'embedded_components { id: "' .. id .. '" type: "collisionobject" data: "'
            .. C.proto_escape(shape) .. '" }\n'
    end
    local source = 'components { id: "script" component: "/mvtk/world/breakable_prop.script" }\n'
        .. trigger("attack_trigger", "breakable", "attack")
    if interact.value == "true" then source = source .. trigger("co", "interactable", "player") end
    if tiles then
        source = source .. 'components { id: "tiles" component: "' .. C.proto_escape(tiles)
            .. '" position { x: ' .. C.fmt_num(offset_x or 0) .. ' y: ' .. C.fmt_num(offset_y or 0) .. ' } }\n'
    end
    local name = room.id .. "_breakable_prop_" .. obj.id .. ".go"
    C.write_if_changed(C.join(C.PATH.generated_go, name), source)
    local props = {Kit.text(C, obj, "prop_id", obj_id), C.text_prop("room_id", room.id, ""),
        Kit.number(C, obj, "health", 1), interact, Kit.bool(C, obj, "stays_broken", false),
        Kit.number(C, obj, "drop_count", 1), Kit.number(C, obj, "drop_chance", 1),
        Kit.text(C, obj, "set_flag", ""), Kit.text(C, obj, "target_id", ""),
        Kit.text(C, obj, "label", "Search"), C.text_prop("painted_layer", tiles and layer or "", "")}
    -- Blank template identity uses the same generated id in runtime, lint and saves.
    props[1].value = props[1].value:match("^%s*(.-)%s*$")
    if props[1].value == "" then props[1].value = obj_id end
    for _, row in ipairs({{"required_ability", ""}, {"drop_collectible", ""}, {"sound_break", "wall_break"}}) do
        local prop = Kit.text(C, obj, row[1], row[2]); prop.value = Kit.opt(prop.value)
        props[#props + 1] = prop
    end
    Kit.instance(C, room, obj_id, C.GENERATED_ROOMS_RESOURCE_DIR .. "/" .. name, x, y, props)
    return true
end

return M
