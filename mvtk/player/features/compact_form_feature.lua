local M = { id = "compact_form", order = 36,
    movement_anims = { "crouch_idle", "crouch_walk", "roll" } }

function M.init(self)
    require("mvtk.player.compact_form").init(self)
end

function M.reset(self, reason)
    require("mvtk.player.compact_form").reset(self, reason)
end

function M.pre_physics(self, dt, input)
    require("mvtk.player.compact_form").pre_physics(self, dt, input)
end

function M.owns_motion(self, dt, input)
    return require("mvtk.player.compact_form").owns_motion(self, dt, input)
end

function M.actions(self, input, stunned)
    if require("mvtk.core.pause").get() or stunned or not input.morph_toggle_down then return end
    input.morph_toggle_down = false
    local Compact = require "mvtk.player.compact_form"
    if self._compact_active then Compact.stand(self) else Compact.enter(self) end
end

function M.anim_state(self)
    if not self._compact_active then return end
    local cfg, state = self._cfg.compact_form or {}, self._host.features.compact_form
    if (state.roll or 0) > 0 then return cfg.roll_animation or "roll" end
    return math.abs(self.vx or 0) > (self._cfg.stop_epsilon or 3)
        and (cfg.move_animation or "crouch_walk") or (cfg.idle_animation or "crouch_idle")
end

return M
