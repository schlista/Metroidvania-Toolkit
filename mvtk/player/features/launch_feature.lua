local M = { id = "launch", order = 24, messages = {
    mvtk_launch = "body", mvtk_cannon_load = "body", mvtk_cannon_cancel = "body",
} }

function M.on_message(self, message_id, message)
    if message_id == hash("mvtk_cannon_load") then
        require("mvtk.player.launch").load(self, message)
    elseif message_id == hash("mvtk_cannon_cancel") then
        require("mvtk.player.launch").cancel_cannon(self, message.cannon)
    elseif message_id == hash("mvtk_launch") then
        require("mvtk.player.launch").start(self, message)
    else return false end
    return true
end

function M.owns_motion(self, dt)
    local owned = require("mvtk.player.launch").owns_motion(self)
    -- PSTATE.update is skipped while the cannon holds the body; keep its timers running.
    if owned and (dt or 0) > 0 then require("mvtk.player.player_state").tick_owned_timers(self, dt) end
    return owned
end

-- A loaded cannon fires on Jump in pre_physics; no press reaches PSTATE.
function M.holds_presses(self)
    return self._host.features.launch.loaded ~= nil
end

function M.anim_state(self)
    if self._host.features.launch.loaded then
        return ((self._cfg or {}).launch or {}).cannon_animation or "crouch_idle"
    end
end

function M.pre_physics(self, dt, input)
    require("mvtk.player.launch").pre_physics(self, dt, input)
end

function M.post_physics(self, dt, input, collision)
    if require("mvtk.core.pause").get() then return end
    require("mvtk.player.launch").post_physics(self, collision)
end

function M.reset(self)
    require("mvtk.player.launch").clear(self)
end

return M
