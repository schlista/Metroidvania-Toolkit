-- World-state presence bake (G8-09). For every baked object with appear_when or
-- remove_when text, add a companion instance '<instance id>__presence' (the
-- presence prefab) at the object's position, so the room collection shows it
-- in the Defold editor. A room with no condition emits nothing.
--
-- Called once through _C after gen_collection's object loop, so gen_collection
-- gains no upvalue. LuaJ-safe: plain patterns only, and no number precision
-- in string formats (AGENTS.md, editor-script sandbox).
local Kit = require "hooks.core.bake_kit"
local Flattener = require "mvtk.tiled.property_flattener"
local Condition = require "mvtk.world.presence_condition"
local M = {}

M.PROTOTYPE = "/developer/game/prefabs/presence.go"
M.SUFFIX = "__presence"
M.COMPONENT = "presence"

-- Kinds baked as more than one game object (a body plus a separate collision
-- or cabin object, or world-owned elevator markers). Removing one instance
-- would leave the rest, so they cannot be presence targets.
M.MULTI_INSTANCE = {
    platform = true, moving_platform = true, crumble_platform = true,
    elevator = true, elevator_node = true,
}

local TIMINGS = {enter = true, live = true}

local function text(C, obj, id)
    local value = Kit.opt(C.get_prop_value(obj, id))
    if value == "" then return "" end
    return (tostring(value):match("^%s*(.-)%s*$"))
end

-- Every instance id the room collection holds so far.
local function instance_ids(rows)
    local ids = {}
    local body = "\n" .. table.concat(rows, "\n")
    for id in body:gmatch('\n  id: "([^"\n]*)"') do ids[id] = true end
    return ids
end

-- Objects in the order gen_collection bakes them, with flattened properties,
-- the layer offset applied and the same type resolution.
local function each_object(C, room, visit)
    local layers = room.tiled and room.tiled.layers
    if type(layers) ~= "table" then return end
    local known
    for _, entry in ipairs(C.flatten_tiled_layers(layers)) do
        local layer = entry.layer
        if entry.visible ~= false and layer and layer.type == "objectgroup" and type(layer.objects) == "table" then
            for _, raw in ipairs(layer.objects) do
                if raw and raw.visible ~= false then
                    local props = Flattener.flatten(raw.properties)
                    if props.appear_when ~= nil or props.remove_when ~= nil or props.presence_timing ~= nil then
                        local obj = {}
                        for k, v in pairs(raw) do obj[k] = v end
                        obj.properties = props
                        obj.x = (tonumber(raw.x) or 0) + (tonumber(entry.offsetx) or 0)
                        obj.y = (tonumber(raw.y) or 0) + (tonumber(entry.offsety) or 0)
                        known = known or C.load_object_type_set()
                        local kind = C.resolve_object_type(obj, known)
                        if C.is_background_visual_object_candidate(obj, layer.name) then kind = "background_visual" end
                        visit(obj, kind or obj.type)
                    end
                end
            end
        end
    end
end

-- Returns the number of companions added. Problems print a
-- [CREATE ROOMS][WARNING] line and never stop the bake.
function M.append(C, room)
    local ids, added = nil, 0
    each_object(C, room, function(obj, kind)
        local appear, remove = text(C, obj, "appear_when"), text(C, obj, "remove_when")
        local timing = text(C, obj, "presence_timing")
        if appear == "" and remove == "" then
            -- The World state group repeats its default "enter" on every placed
            -- template, so only a non-default timing without a condition is a mistake.
            if timing ~= "" and timing ~= "enter" then
                Kit.warn(C, room, obj, "presence_timing is set but there is no appear_when or remove_when; ignored.")
            end
            return
        end
        local valid = 0
        for _, field in ipairs({{"appear_when", appear}, {"remove_when", remove}}) do
            if field[2] ~= "" then
                local req, err = Condition.parse(field[2])
                if req then
                    valid = valid + 1
                else
                    Kit.warn(C, room, obj, "presence_condition_invalid: " .. field[1] .. " '" .. field[2]
                        .. "': " .. tostring(err) .. ". The game ignores it.")
                end
            end
        end
        if valid == 0 then return end
        if timing == "" then
            timing = "enter"
        elseif not TIMINGS[timing] then
            Kit.warn(C, room, obj, "presence_timing_invalid: '" .. timing .. "' is not enter or live; using enter.")
            timing = "enter"
        end
        local target = C.generated_object_id(room.id, kind, obj.id)
        ids = ids or instance_ids(room.rows)
        if M.MULTI_INSTANCE[kind] or not ids[target] then
            Kit.warn(C, room, obj, "presence_target_not_instance: a " .. tostring(kind)
                .. " object is not baked as one game object, so appear_when and remove_when cannot remove it.")
            return
        end
        local props = {C.text_prop("target", target), C.text_prop("room_id", room.id)}
        if appear ~= "" then props[#props + 1] = C.text_prop("appear_when", appear) end
        if remove ~= "" then props[#props + 1] = C.text_prop("remove_when", remove) end
        if timing ~= "enter" then props[#props + 1] = C.text_prop("timing", timing) end
        local map_height = tonumber(room.map_height) or 0
        C.add_prefab_instance(room.rows, target .. M.SUFFIX, M.PROTOTYPE, obj.x, map_height - obj.y,
            nil, nil, M.COMPONENT, props)
        added = added + 1
    end)
    if added > 0 and C.info then
        C.info(string.format("[CREATE ROOMS] room %s: %d presence companions", tostring(room.id), added))
    end
    return added
end

return M
