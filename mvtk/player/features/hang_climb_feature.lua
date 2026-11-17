local function settings()
    return require("developer.config.runtime_settings").get_player_settings().ladder_climb or {}
end
local cfg = settings()
local M = { id = "hang_climb", order = 22, movement_anims = {
    cfg.hang_idle_animation or "hang", cfg.hang_move_animation or "hang", cfg.mesh_animation or "",
} }

function M.anim_state(self)
    if not self._in_climb or self._in_water then return nil end
    -- The load-time copy: get_player_settings deep-copies the scaled settings,
    -- which would allocate a whole table every climbing frame.
    local current = cfg
    if self._climb_axis == "hang" then
        if math.abs(self.vx or 0) > 0 then return current.hang_move_animation or "hang" end
        return current.hang_idle_animation or "hang"
    elseif self._climb_axis == "mesh" and current.mesh_animation and current.mesh_animation ~= "" then
        return current.mesh_animation
    end
end

return M
