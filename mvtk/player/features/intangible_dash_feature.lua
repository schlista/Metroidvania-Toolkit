local M = { id = "intangible_dash", order = 32 }

function M.apply_abilities(overrides, base, is_unlocked)
    local settings = require("developer.config.runtime_settings").get_player_settings()
    local config = {}
    for key, value in pairs(settings.intangible_dash or {}) do config[key] = value end
    config.enabled = is_unlocked("intangible_dash")
    overrides.intangible_dash = config
end

function M.post_physics(self)
    local config = self._cfg.intangible_dash or {}
    local active = config.enabled == true and (
        (config.during_air_dash == true and (self._dash_t or 0) > 0)
        or (config.during_slide == true and (self._slide_t or 0) > 0))
    require("mvtk.player.intangibility").set(active)
    local state = self._host.features.intangible_dash
    local invulnerable = active and config.invulnerable == true
    local Stats = require "mvtk.player.player_stats"
    if invulnerable then
        Stats.set_source("ability:intangible_dash", { invulnerable = true }, { lease = true })
    elseif state.invulnerable then
        Stats.clear_source("ability:intangible_dash")
    end
    state.invulnerable = invulnerable
end

function M.reset(self, reason)
    require("mvtk.player.intangibility").set(false)
    require("mvtk.player.player_stats").clear_source("ability:intangible_dash")
    self._host.features.intangible_dash.invulnerable = false
end

return M
