-- NPC Behavior group bake (WM12a-b). gen_collection's literal npc branch calls
-- this through _C, so gen_collection gains no upvalue:
--
--   local entry = NpcBehaviorBake.preset(_C, obj) -- its npc_types.lua preset, once
--   NpcBehaviorBake.props(_C, obj, list, entry)    -- push non-default behaviour values
--   NpcBehaviorBake.prefab(_C, obj, entry)         -- the NPC prototype to bake
--
-- An NPC with no behaviour opted in bakes exactly as before: npc.go and no
-- extra property. One that shows the new-dialogue marker or has ambient
-- lines (barks), from its Tiled Behavior group or its npc_types.lua preset,
-- uses npc_living.go, whose `bubble` label shows them. Face player and wander
-- need no label: they push their properties and keep npc.go. Only values that
-- differ from the npc.script defaults are pushed. The placed NPC is still a
-- baked instance in the room collection, with a different prototype.
--
-- Not a FeatureBakes module: npc keeps its literal branch. npc_types.lua is
-- read fresh by each preset() call, once per typed NPC, and never kept between
-- NPCs (Prepare & Check is a full rebuild and npc_types.lua is a freshness
-- input). Every function below that takes `entry` reads it itself when it is
-- nil. LuaJ-safe: plain patterns, no number formats.
local M = {}

M.PLAIN = "/developer/game/prefabs/npc.go"
M.LIVING = "/developer/game/prefabs/npc_living.go"
M.TYPES_FILE = "developer/config/npc_types.lua"

local function truthy(value)
    if value == true then return true end
    if type(value) == "string" then
        local s = value:match("^%s*(.-)%s*$"):lower()
        return s == "true" or s == "1"
    end
    return false
end

-- The NPC's npc_types.lua preset table, or false when it has none.
function M.preset(C, obj)
    local npc_type = C.get_prop_value(obj, "npc_type")
    npc_type = npc_type ~= nil and tostring(npc_type):match("^%s*(.-)%s*$") or ""
    if npc_type == "" or type(C.load_project_lua_table) ~= "function" then return false end
    local types = C.load_project_lua_table(M.TYPES_FILE)
    local entry = type(types) == "table" and types[npc_type] or nil
    return type(entry) == "table" and entry or false
end

-- The Tiled box turns it on; a type preset turns it on for every NPC of that
-- type. A Tiled object always exports the group's false default, so false
-- there cannot turn a preset off.
function M.shows_marker(C, obj, entry)
    if truthy(C.get_prop_value(obj, "show_new_dialogue_marker")) then return true end
    if entry == nil then entry = M.preset(C, obj) end
    return entry and entry.show_new_dialogue_marker == true or false
end

-- Number fields and their npc.script defaults (WM12b), in push order.
M.NUMBERS = {
    { "bark_range", 96 }, { "bark_cooldown", 8 }, { "wander_width", 0 }, { "wander_speed", 30 },
}

local function text_of(C, obj, id)
    local value = C.get_prop_value(obj, id)
    return value ~= nil and tostring(value):match("^%s*(.-)%s*$") or ""
end

-- Barks on the object, or a nonblank line in its type preset's `barks`.
function M.has_barks(C, obj, entry)
    if text_of(C, obj, "barks"):gsub("|", ""):match("%S") then return true end
    if entry == nil then entry = M.preset(C, obj) end
    if not entry or type(entry.barks) ~= "table" then return false end
    for _, line in ipairs(entry.barks) do
        if type(line) == "string" and line:match("%S") then return true end
    end
    return false
end

function M.living(C, obj, entry)
    if entry == nil then entry = M.preset(C, obj) end
    return M.shows_marker(C, obj, entry) or M.has_barks(C, obj, entry)
end

function M.props(C, obj, list, entry)
    if M.shows_marker(C, obj, entry) then
        list[#list + 1] = C.bool_prop("show_new_dialogue_marker", true, false)
    end
    if truthy(C.get_prop_value(obj, "face_player")) then
        list[#list + 1] = C.bool_prop("face_player", true, false)
    end
    local barks = text_of(C, obj, "barks")
    if barks:gsub("|", ""):match("%S") then list[#list + 1] = C.text_prop("barks", barks) end
    for _, spec in ipairs(M.NUMBERS) do
        local value = tonumber(C.get_prop_value(obj, spec[1]))
        if value ~= nil and value ~= spec[2] then list[#list + 1] = C.number_prop(spec[1], value, spec[2]) end
    end
    return list
end

function M.prefab(C, obj, entry)
    return M.living(C, obj, entry) and M.LIVING or M.PLAIN
end

return M
