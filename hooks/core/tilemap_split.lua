-- Tilemap layer splitting shared by the parallax bake and the world-state
-- layer bake (G8-10). split() moves whole protobuf layer blocks, so every
-- cell keeps its flip flags and tile: 0 (the first tile, never "empty").
--
-- state_layers(map) decides which Tiled tile layers are world-state layers:
-- a tile layer whose appear_when or remove_when holds a condition. A layer
-- that cannot leave the main tilemap is reported and stays where it is.
--
-- No hooks dependency, so hooks/core/tilesource.lua can call it without a
-- require cycle. LuaJ-safe: plain patterns, no number precision formats.
local Proto = require "mvtk.editor.proto_utils"
local Background = require "mvtk.editor.background_atlas"
local Props = require "mvtk.tiled.visual_ownership"
local M = {}

M.CONDITION_FIELDS = {"appear_when", "remove_when"}

-- Object fields that name a tile layer of the room's main tilemap. Those
-- objects read the layer by name at runtime, so the layer must stay there.
M.REFERENCE_FIELDS = {"wall_layer", "broken_wall_layer", "painted_layer", "level_art_layer",
    "retract_visual_layer", "visual_layer", "source_layer", "anim_layer"}

M.COLLISION_MODES = {auto = true, none = true}

local function trim(value)
    if value == nil then return "" end
    return (tostring(value):match("^%s*(.-)%s*$"))
end

local function moving(entry)
    return (tonumber(entry.parallaxx) or 1) ~= 1 or (tonumber(entry.parallaxy) or 1) ~= 1
end

-- Split `text` (a .tilemap) by layer id. `selected` maps a layer id to any
-- value (kept as part.entry). Returns the remaining text and the parts, each
-- a complete .tilemap holding one selected layer, in file order. With nothing
-- selected the text is returned unchanged.
function M.split(text, selected)
    if not next(selected or {}) then return text, {} end
    local top, static, parts = {}, {}, {}
    local lines = Proto.split_proto_lines(text:gsub("\r\n", "\n"))
    local i = 1
    while i <= #lines do
        if lines[i]:match("^%s*layers%s*{") then
            local block, depth = {}, 0
            repeat
                block[#block + 1] = lines[i]; depth = depth + Proto.brace_delta(lines[i]); i = i + 1
            until depth == 0 or i > #lines
            assert(depth == 0, "Unclosed tilemap layer")
            local content = table.concat(block, "\n")
            local name = content:match('id:%s*"([^"]+)"')
            if selected[name] then
                parts[#parts + 1] = {entry = selected[name], text = content, name = name}
            else static[#static + 1] = content end
        else top[#top + 1] = lines[i]; i = i + 1 end
    end
    local header = table.concat(top, "\n") .. "\n"
    for _, part in ipairs(parts) do part.text = header .. part.text .. "\n" end
    return header .. table.concat(static, "\n") .. "\n", parts
end

-- Trimmed condition text of a layer, "" when blank.
function M.condition(layer, field)
    return trim(Props.property_value(layer, field))
end

local function is_candidate(layer)
    if type(layer) ~= "table" or layer.type ~= "tilelayer" then return false end
    for _, field in ipairs(M.CONDITION_FIELDS) do
        if M.condition(layer, field) ~= "" then return true end
    end
    return false
end

-- Layer names that an object field reads from the main tilemap.
local function referenced_names(flat)
    local Flattener = require "mvtk.tiled.property_flattener"
    local names = {}
    for _, entry in ipairs(flat) do
        local layer = entry.layer
        if layer.type == "objectgroup" and type(layer.objects) == "table" then
            for _, obj in ipairs(layer.objects) do
                local props = type(obj) == "table" and type(obj.properties) == "table"
                    and Flattener.flatten(obj.properties) or {}
                for _, field in ipairs(M.REFERENCE_FIELDS) do
                    local name = trim(props[field])
                    if name ~= "" and not names[name] then
                        names[name] = {object_id = obj.id, field = field}
                    end
                end
            end
        end
    end
    return names
end

-- Returns the accepted state layers, in Tiled order, and the problems found.
-- Each accepted record: {entry, name, id, appear_when, remove_when, collision}.
-- Each problem: {code, layer, property, message, fix, rejected}; a rejected
-- layer stays in the main tilemap and the shared tile collision.
function M.state_layers(map)
    local accepted, problems = {}, {}
    local flat = Background.flatten_tiled_layers(type(map) == "table" and map.layers or nil)
    local candidates, counts = {}, {}
    for _, entry in ipairs(flat) do
        local layer = entry.layer
        if layer.type == "tilelayer" then
            local name = tostring(layer.name or "")
            counts[name] = (counts[name] or 0) + 1
            if is_candidate(layer) then candidates[#candidates + 1] = entry end
        end
    end
    if #candidates == 0 then return accepted, problems end

    local Regen = require "mvtk.editor.tilemap_regen"
    local Condition = require "mvtk.world.presence_condition"
    local references = referenced_names(flat)
    local function problem(code, name, property, message, fix, rejected)
        problems[#problems + 1] = {code = code, layer = name, property = property,
            message = message, fix = fix, rejected = rejected}
    end
    for _, entry in ipairs(candidates) do
        local layer = entry.layer
        local name = tostring(layer.name or "")
        local reject
        if Regen.is_control_tile_layer(name) or Regen.is_tag_tile_layer(name) then
            reject = "it is a control or tag layer (bounds, doors, solid, grapple, ice and similar)"
        elseif moving(entry) then
            reject = "it moves with parallax"
        elseif counts[name] > 1 then
            reject = "another tile layer has the same name"
        elseif layer.id == nil then
            reject = "it has no Tiled layer id"
        end
        if reject then
            problem("state_layer_forbidden", name, "appear_when",
                "Tile layer '" .. name .. "' cannot be a world-state layer: " .. reject .. ".",
                "Paint the changing tiles on their own uniquely named art layer with Parallax 1, and move appear_when or remove_when there.",
                true)
        elseif references[name] then
            local ref = references[name]
            problem("state_layer_referenced", name, "appear_when",
                "Tile layer '" .. name .. "' cannot be a world-state layer: object " .. tostring(ref.object_id)
                    .. " reads it through " .. ref.field .. ".",
                "Give the object its own layer, or paint the changing tiles on a separate layer.",
                true)
        else
            local record = {entry = entry, name = name, id = layer.id, collision = "auto"}
            local valid, first = 0, #problems + 1
            for _, field in ipairs(M.CONDITION_FIELDS) do
                local text = M.condition(layer, field)
                record[field] = text
                if text ~= "" then
                    local req, err = Condition.parse(text)
                    if req then valid = valid + 1 else
                        problem("presence_condition_invalid", name, field,
                            "World-state condition '" .. text .. "' on tile layer '" .. name
                                .. "' does not parse: " .. tostring(err) .. ".",
                            "Use a comma list of flag, !flag, ability:<id> or item:<id>[:count], with | between alternatives; leave blank for none.",
                            false)
                    end
                end
            end
            local mode = trim(Props.property_value(layer, "state_collision")):lower()
            if mode ~= "" and not M.COLLISION_MODES[mode] then
                problem("state_layer_forbidden", name, "state_collision",
                    "state_collision '" .. mode .. "' on tile layer '" .. name .. "' is not auto or none; using auto.",
                    "Set state_collision to auto (collide where the tiles have collision shapes) or none.",
                    false)
            elseif mode == "none" then
                record.collision = "none"
            end
            if valid > 0 then
                accepted[#accepted + 1] = record
            else
                -- Every condition fails to parse: the game would ignore them,
                -- so the layer stays in the main tilemap.
                for i = first, #problems do problems[i].rejected = true end
            end
        end
    end
    return accepted, problems
end

-- Set of accepted state layer names, for name-keyed skips.
function M.state_layer_names(map)
    local names = {}
    for _, record in ipairs((M.state_layers(map))) do names[record.name] = record end
    return names
end

return M
