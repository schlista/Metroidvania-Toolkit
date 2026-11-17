-- World-state tile layer bake (G8-10). Each accepted state layer (a tile
-- layer with appear_when or remove_when; hooks/core/tilemap_split.lua)
-- leaves the room's main tilemap and shared tile collision and becomes its
-- own baked game object in the room collection, editable in the Defold
-- editor:
--
--   /developer/rooms/generated/<room>_state_layer_<layer id>.tilemap  that layer only
--   /developer/rooms/generated/<room>_state_layer_<layer id>.go       tilemap, presence
--       component and that layer's tile-collision hulls (tilecol_<n>)
--   instance '<room>_state_layer_<layer id>_tiles' with the condition as TEXT
--       properties on its presence component
--
-- The instance id ends in "_tiles", not digits, so bake_audit's id-suffix
-- match never pairs it with a Tiled object (layer and object ids are separate
-- counters). The .go is written as is: sanitize_collision_group_text would
-- blank its "solid" group. A room with no state layer emits nothing.
--
-- Called once through _C beside the parallax bake, so gen_collection gains no
-- upvalue. LuaJ-safe: plain patterns only, no number precision formats.
local Split = require "hooks.core.tilemap_split"
local Emit = require "mvtk.editor.proto_emit"
local M = {}

M.SCRIPT = "/mvtk/world/presence.script"
M.COMPONENT = "presence"
M.DIR = require("mvtk.editor.shared_proto").generated_dir() .. "/"

function M.resource(rid, layer_id, generated_dir)
    return (generated_dir or M.DIR):gsub("/+$", "") .. "/" .. tostring(rid) .. "_state_layer_" .. tostring(layer_id)
end

function M.instance_id(rid, layer_id)
    return tostring(rid) .. "_state_layer_" .. tostring(layer_id) .. "_tiles"
end

-- The state layer's game object: its tilemap, the presence component and the
-- collision object blocks from the hull generator (may be "").
function M.go_text(resource, collision_blocks)
    return 'components {\n  id: "tilemap"\n  component: "' .. resource .. '.tilemap"\n}\n'
        .. 'components {\n  id: "' .. M.COMPONENT .. '"\n  component: "' .. M.SCRIPT .. '"\n}\n'
        .. (collision_blocks or "")
end

local function warn(room, problem)
    print("[CREATE ROOMS][WARNING] " .. tostring(room.id) .. " layer '" .. tostring(problem.layer) .. "': "
        .. tostring(problem.code) .. ": " .. tostring(problem.message)
        .. (problem.rejected and " The layer stays in the room tilemap." or ""))
end

-- Returns the number of state layer instances added. Problems print a
-- [CREATE ROOMS][WARNING] line and never stop the bake.
function M.append(C, room)
    local accepted, problems = Split.state_layers(room.tiled)
    for _, problem in ipairs(problems) do warn(room, problem) end
    if #accepted == 0 then return 0 end
    local _, _, parts, tilemap_text = C.ParallaxBake.tile_plan(C, room.id, room.tiled)
    local by_name = {}
    for _, part in ipairs(parts) do by_name[part.name] = part end
    local hulls = C.gen_state_layer_collision or require("hooks.core.tilesource").gen_state_layer_collision
    -- One per room: every layer's hulls reuse its export and parsed tilemap.
    local shared = {tilemap_text = tilemap_text}
    local added = 0
    for _, record in ipairs(accepted) do
        local part = by_name[record.name]
        if not part then
            warn(room, {layer = record.name, code = "state_layer_missing",
                message = "the room tilemap has no layer with this name; export the room from Tiled, then run Prepare & Check."})
        else
            local resource = M.resource(room.id, record.id, C.GENERATED_ROOMS_RESOURCE_DIR)
            C.write_if_changed(C.join(C.ROOT, resource:sub(2) .. ".tilemap"), part.text)
            local blocks, count = "", 0
            if record.collision ~= "none" then blocks, count = hulls(room.id, record.name, record.id, shared) end
            count = tonumber(count) or 0
            C.write_if_changed(C.join(C.ROOT, resource:sub(2) .. ".go"), M.go_text(resource, blocks))
            local props = {Emit.text_prop("room_id", room.id)}
            if record.appear_when ~= "" then props[#props + 1] = Emit.text_prop("appear_when", record.appear_when) end
            if record.remove_when ~= "" then props[#props + 1] = Emit.text_prop("remove_when", record.remove_when) end
            props[#props + 1] = Emit.bool_prop("self_mode", true)
            -- 0 is the script default, and the editor drops defaults on save.
            if count > 0 then props[#props + 1] = Emit.number_prop("collision_count", count) end
            C.add_prefab_instance(room.rows, M.instance_id(room.id, record.id), resource .. ".go", 0, 0,
                nil, nil, M.COMPONENT, props)
            added = added + 1
        end
    end
    if added > 0 and C.info then
        C.info(string.format("[CREATE ROOMS] room %s: %d world-state tile layers", tostring(room.id), added))
    end
    return added
end

return M
