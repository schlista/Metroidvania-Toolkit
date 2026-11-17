-- Stateless player attack type resolution. No engine calls or saved state.
local M = {}

-- An explicit per-attack type wins over the category default. The first
-- unlocked infusion row then overrides only the categories it names.
function M.resolve(kind, explicit, config, unlocked)
    config = config or require("developer.config.runtime_settings").section(
        "damage_types", require "developer.config.damage_types")
    local base = type(explicit) == "string" and explicit ~= "" and explicit ~= "none" and explicit
        or (config.player_attacks or {})[kind]
        or (kind == "ranged" and "projectile" or kind == "movement" and "impact" or "slash")
    for _, row in ipairs(config.player_attack_infusions or {}) do
        -- Lazy lookup avoids the player/ability-manager load-order cycle.
        local is_unlocked = unlocked or require("mvtk.abilities.ability_manager").is_ability_unlocked
        if is_unlocked(row.ability) then
            return row[kind] or base
        end
    end
    return base
end

return M
