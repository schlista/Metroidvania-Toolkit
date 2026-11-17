-- World-state presence service (G8-09): decides whether an object with
-- appear_when / remove_when text should exist now. Presence is derived from
-- flags, abilities and items, so it saves nothing.
--
-- revision() changes whenever an answer may change: Flags.revision() covers
-- flags (and abilities, which mirror into flags), and a local counter covers
-- the inventory events. A load replaces the flag store through Flags.import,
-- which bumps its revision, so muted events during a restore lose nothing.
-- Callers re-evaluate only when revision() moves; never per frame or room.
local Flags = require "mvtk.core.flags"
local GameEvents = require "mvtk.core.game_events"
local Condition = require "mvtk.world.presence_condition"
local Requirements = require "mvtk.world.gates.requirements"
local M = {}

local bumps = 0
local parsed, warned = {}, {}

local live_flags = setmetatable({}, {__index = function(_, key) return Flags.get(key) end})
local function has_ability(id)
    local Abilities = require "mvtk.abilities.ability_manager"
    return Abilities.has_ability(id) and true or false
end
local function has_item(id, amount)
    local Inventory = require "mvtk.core.inventory"
    return Inventory.has_item(id, amount) and true or false
end

-- Live state for Requirements.evaluate, also used by mvtk/game/goals.lua.
-- Flags are read through Flags.get, never copied (Flags.all() copies the whole
-- store); abilities and items answer true or false. resources (optional) is
-- kept as given, such as {currency = n}.
function M.requirement_state(resources)
    return {flags = live_flags, has_ability = has_ability, has_item = has_item, resources = resources}
end

local state = M.requirement_state()

local function bump() bumps = bumps + 1 end
for _, name in ipairs({"ability_unlocked", "item_added", "item_removed"}) do GameEvents.on(name, bump) end

function M.revision() return Flags.revision() + bumps end

-- Parsed requirement for text, cached by the exact text. Unparseable text
-- warns once and returns nil; Prepare & Check reports it as an error.
local function requirement(text)
    local entry = parsed[text]
    if entry == nil then
        local req, err = Condition.parse(text)
        entry = req or false
        parsed[text] = entry
        if not req and not warned[text] then
            warned[text] = true
            print("[PRESENCE] Ignoring condition '" .. tostring(text) .. "': " .. tostring(err))
        end
    end
    return entry or nil
end

-- True when the condition holds; nil for blank or unparseable text.
function M.holds(text)
    if Condition.is_blank(text) then return nil end
    local req = requirement(text)
    if not req then return nil end
    return (Requirements.evaluate(req, state))
end

-- An object is present unless appear_when does not hold yet or remove_when
-- holds. Blank or unparseable text never hides an object.
function M.present(appear_when, remove_when)
    if M.holds(appear_when) == false then return false end
    if M.holds(remove_when) == true then return false end
    return true
end

return M
