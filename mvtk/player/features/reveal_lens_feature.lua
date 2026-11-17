local M = { id = "reveal_lens", order = 40 }

function M.pre_physics(self, dt)
    local Util = require "mvtk.core.util"
    local cfg = Util.require_config("developer.config.secret_settings").reveal_lens
    local state = self._host.features.reveal_lens
    if not require("mvtk.abilities.ability_manager").has_ability(cfg.ability_id) then
        state.remaining = 0
        return
    end
    state.remaining = (state.remaining or 0) - dt
    if state.remaining > 0 then return end
    state.remaining = cfg.check_interval

    local Lens = require "mvtk.abilities.reveal_lens"
    local radius = cfg.radius_tiles * Util.require_config("developer.config.tile_settings").width
    for _, secret in Lens.registered() do
        if Lens.requirement_matches(secret.required, cfg.ability_id)
            and Lens.should_reveal(secret.center, secret.half_w, secret.half_h, self.pos, radius) then
            msg.post(secret.url, "reveal_secret")
        end
    end
end

function M.reset(self, reason)
    self._host.features.reveal_lens.remaining = 0
end

return M
