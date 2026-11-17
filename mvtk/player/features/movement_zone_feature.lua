-- Escape jumps reuse the ordinary coyote jump path; no motion owner is added.
local M = {id = "movement_zone", order = 26, messages = {mvtk_zone_escape = "body"}}

function M.on_message(self, message_id)
    if message_id ~= hash("mvtk_zone_escape") then return false end
    if require("mvtk.core.pause").get() then return true end
    self._host.features.movement_zone.frame = (self._frame_counter or 0) + 1
    return true
end

function M.pre_physics(self)
    if require("mvtk.core.pause").get() then return end
    local state = self._host.features.movement_zone
    if state.frame and (self._frame_counter or 0) - state.frame <= 2 then
        self._coyote_t = math.max(self._coyote_t or 0, self._cfg.coyote_time or 0)
    else state.frame = nil end
end

function M.reset(self)
    self._host.features.movement_zone.frame = nil
end

return M
