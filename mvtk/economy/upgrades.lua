-- Permanent purchases share the existing saved stat ledger, not a provider.
local Stats = require "mvtk.player.permanent_stats"
local Config = require "developer.config.upgrades"
local M = {}
function M.get(id) return Config.upgrades[id] end
function M.deltas(id)
    local def = M.get(id)
    if not def then return nil end
    local out = {}
    for _, key in ipairs({"max_health", "max_energy", "max_stamina", "damage_mult"}) do
        out[key] = def[key]
    end
    return out
end
function M.is_applied(id) return Stats.has("upgrade:" .. id) end
function M.requires_met(id)
    local def = M.get(id)
    if not def then return false, id end
    for _, required in ipairs(def.requires or {}) do
        if not M.is_applied(required) then return false, required end
    end
    return true
end
function M.apply(id)
    if M.is_applied(id) then return false, "exhausted" end
    if not M.get(id) then return false, "unknown_upgrade" end
    if not M.requires_met(id) then return false, "prerequisite" end
    return Stats.record("upgrade:" .. id, {kind = "upgrade", id = id, deltas = M.deltas(id)})
end
Stats.set_upgrade_resolver(M.deltas)
return M
