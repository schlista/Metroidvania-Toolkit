-- Unlocked abilities contribute typed stats, never another damage multiply site.
local RuntimeSettings = require "developer.config.runtime_settings"
local PlayerStats = require "mvtk.player.player_stats"
local M = {}
local listener

local function recompute()
    local cfg = RuntimeSettings.section("damage_types", require "developer.config.damage_types")
    local abilities = require "mvtk.abilities.ability_manager"
    local values = {}
    for ability, types in pairs(cfg.ability_taken or {}) do
        if abilities.is_ability_unlocked(ability) then
            for t, n in pairs(types) do
                local key = "damage_taken_mult:" .. t
                values[key] = (values[key] or 1) * n
            end
        end
    end
    -- One source holds the combined abilities; keep its values within the
    -- accepted stat range so stacking strong resistances cannot drop the key.
    for key, n in pairs(values) do values[key] = math.max(0.1, math.min(10, n)) end
    PlayerStats.set_source("abilities_resist", values, {layer = "permanent"})
end

function M.on_session_start()
    local abilities = require "mvtk.abilities.ability_manager"
    if listener then abilities.unregister_listener(listener) end
    listener = abilities.register_listener(function(event)
        if event ~= "use" then recompute() end
    end)
    recompute()
end

return M
