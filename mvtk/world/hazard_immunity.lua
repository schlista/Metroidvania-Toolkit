-- Shared hazard protection rules; no engine calls or state at module load.
local M = {}

-- An explicit placed ability replaces both type defaults. Blank/none inherits.
function M.resolve(required_resistance, hazard_config)
    if required_resistance == "none" then required_resistance = "" end
    if required_resistance ~= "" and required_resistance ~= nil then
        return required_resistance, nil
    end
    local config = hazard_config or {}
    return config.immunity_ability or "", config.immunity_item
end

-- Load runtime services only when needed. A missing service never grants immunity.
function M.player_immune(ability_id, item_id)
    local immune = false
    if ability_id and ability_id ~= "" then
        pcall(function()
            local AbilityManager = require "mvtk.abilities.ability_manager"
            immune = AbilityManager.has_ability(ability_id)
        end)
    end
    if not immune and item_id then
        pcall(function()
            local Inventory = require "mvtk.core.inventory"
            immune = Inventory.has_item(item_id)
        end)
    end
    return immune
end

return M
