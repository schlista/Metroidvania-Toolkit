-- Escape jumps reuse the ordinary coyote jump path; no motion owner is added.
local Timers = require "mvtk.player.timers"
local M = {id = "movement_zone", order = 26, messages = {mvtk_zone_escape = "body"}}

function M.on_message(self, message_id)
    if message_id ~= hash("mvtk_zone_escape") then return false end
    if require("mvtk.core.pause").get() then return true end
    -- The contact used to refresh coyote on three successive 60 Hz updates.
    local state = self._host.features.movement_zone
    Timers.start_window(state, "assist", 3 * Timers.REFERENCE_STEP)
    state.elapsed = 0
    return true
end

function M.pre_physics(self, dt)
    if require("mvtk.core.pause").get() then return end
    local state = self._host.features.movement_zone
    local elapsed = state.elapsed
    if not elapsed then return end
    local active = Timers.step_window(state, "assist", dt)
    -- The last reference refresh opens two updates after contact. If a
    -- frame crosses that opening, honor the refresh on that frame.
    local last_refresh = 2 * Timers.REFERENCE_STEP
    local edge = last_refresh * (1 + 1e-6)
    local crosses = elapsed <= edge and elapsed + dt > edge
    if active or crosses then
        local offset = (crosses or elapsed >= last_refresh) and elapsed - last_refresh or 0
        Timers.extend_window(self, "_coyote_t", self._cfg.coyote_time or 0, offset)
    end
    state.elapsed = active and elapsed + dt or nil
end

function M.reset(self)
    local state = self._host.features.movement_zone
    Timers.clear_window(state, "assist")
    state.elapsed = nil
end

return M
