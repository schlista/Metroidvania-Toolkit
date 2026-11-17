-- The shared damage multiplier site. Type-specific factors belong here too.
local Multipliers = require "mvtk.combat.multipliers"
local Elements = require "mvtk.combat.elements"
local PlayerStats = require "mvtk.player.player_stats"
local RuntimeSettings = require "developer.config.runtime_settings"
local M = {}

-- Returns amount, immune, verdict. A missing target means enemy.
function M.apply(amount, dtype, opts)
    local a = tonumber(amount) or 0
    local target = opts and opts.target or "enemy"
    if target == "player" then
        if Multipliers.immune_all() then return 0, true, "normal" end
        if opts.lethal then return a, false, "normal" end
        local cfg = RuntimeSettings.section("damage_types", require "developer.config.damage_types")
        local t = Elements.type_id(dtype)
        local f = Elements.lookup(cfg.player_taken, t, cfg, 1)
            * PlayerStats.sub_mult("damage_taken_mult", t, Elements.family(t, cfg))
            * Multipliers.get("damage_to_player")
        return a * f, f == 0, f == 0 and "immune" or "normal"
    end
    local cfg = RuntimeSettings.section("damage_types", require "developer.config.damage_types")
    local t, profile = Elements.type_id(dtype), opts and opts.profile or {}
    local affinity, verdict = Elements.multiplier(t, profile, cfg)
    local entry = (cfg.types or {})[t]
    local f = (entry and entry.outgoing or 1) * affinity
    for _, tag in ipairs(profile.tags or {}) do
        f = f * Elements.lookup((cfg.tag_multipliers or {})[tag], t, cfg, 1)
    end
    -- Extensions append per-target numeric factors here; never multiply at a
    -- second health-change site. Elements' affinity verdict stays independent.
    for _, factor in ipairs(profile.factors or {}) do f = f * factor end
    f = f * Multipliers.get("damage_to_" .. target)
    return a * f, f == 0, f == 0 and "immune" or verdict
end

return M
