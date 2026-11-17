-- mvtk/tiled/retired_types.lua
-- Identifiers recognized only to explain old maps; these types have no runtime
-- handler or baker. Keep genuine unknown types on the existing error path.
local Product = require "mvtk.core.product"
local M = {}

M.MESSAGE = "retired object type, not supported by the " .. Product.name

-- Compatibility identifiers, not supported authoring types.
-- BEGIN GENERATED: object_ownership object_types
local OBJECT_TYPES = {
    bank = true,
    offering_altar = true,
    shop = true,
    shop_npc = true,
    quest_trigger = true,
    skill_trainer = true,
    upgrade_station = true,
    zip_line = true,
    wind_current = true,
    ice_floor = true,
    pendulum_hazard = true,
    warp_statue = true,
    enemy_nest = true,
    spawn_wave = true,
    enemy_spawner = true,
    turret_rotating = true,
    arena_hazard_spawner = true,
    background_interactable = true,
    ambient_sound = true,
    death_drop = true,
    bloodstain = true,
}
-- END GENERATED: object_ownership object_types

-- Saved and authored identifiers retained solely for compatibility diagnostics.
local ABILITY_IDS = { high_jump = true, phase = true }

local function normalize(value)
    local id = tostring(value or ""):match("^%s*(.-)%s*$"):lower()
    return id:gsub("[%s%-]+", "_"):gsub("_+", "_")
end

local function normalized_set(values)
    local set = {}
    for _, value in ipairs(values or {}) do set[normalize(value)] = true end
    return set
end

local UNRETIRED_OBJECT_TYPES = normalized_set((Product.unretire or {}).object_types)
local UNRETIRED_ABILITIES = normalized_set((Product.unretire or {}).abilities)

function M.is_object_type(value)
    local id = normalize(value)
    return OBJECT_TYPES[id] == true and not UNRETIRED_OBJECT_TYPES[id]
end

function M.is_ability(value)
    local id = normalize(value)
    return ABILITY_IDS[id] == true and not UNRETIRED_ABILITIES[id]
end

function M.is_unretired_object_type(value)
    return UNRETIRED_OBJECT_TYPES[normalize(value)] == true
end

function M.unretires_any_ability()
    return next(UNRETIRED_ABILITIES) ~= nil
end

function M.required_ability_warning(object, room_id, value)
    if not M.is_ability(value) then return nil end
    return string.format("%s: object id=%s required_ability='%s': %s",
        tostring(room_id or "<room>"), tostring(object and object.id),
        tostring(value), M.MESSAGE)
end

local function sorted_ids(values, include)
    local ids = {}
    for id in pairs(values) do
        if not include or include(id) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

function M.object_type_ids()
    return sorted_ids(OBJECT_TYPES, M.is_object_type)
end

function M.ability_ids()
    return sorted_ids(ABILITY_IDS, M.is_ability)
end

function M.unretired_object_type_ids()
    return sorted_ids(UNRETIRED_OBJECT_TYPES)
end

function M.warning(object, room_id)
    local object_type
    for _, field in ipairs({ "type", "class", "className" }) do
        if object and normalize(object[field]) ~= "" then
            object_type = object[field]
            break
        end
    end
    local message = M.MESSAGE
    local hint = (Product.retired_hints or {})[normalize(object_type)]
    if hint and hint ~= "" then message = message .. " " .. hint end
    return string.format("%s: object id=%s type='%s': %s",
        tostring(room_id or "<room>"), tostring(object and object.id),
        tostring(object_type), message)
end

return M
