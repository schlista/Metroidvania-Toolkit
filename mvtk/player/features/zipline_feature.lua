local M = {id="zipline", order=6, messages={zipline_start="body"}}
function M.on_message(self, message_id, message)
    if message_id ~= hash("zipline_start") then return false end
    require("mvtk.player.zipline_ride").start(self,message)
    return true
end
function M.pre_physics(self, dt, input) require("mvtk.player.zipline_ride").pre_physics(self,dt,input) end
function M.owns_motion(self, dt, input)
    local owned=require("mvtk.player.zipline_ride").owns_motion(self,dt,input)
    -- PSTATE.update is skipped while the ride owns motion; keep its timers running.
    if owned and dt>0 then require("mvtk.player.player_state").tick_owned_timers(self,dt) end
    return owned
end
function M.post_physics(self, dt) require("mvtk.player.zipline_ride").post_physics(self,dt) end
function M.holds_presses(self) return require("mvtk.player.zipline_ride").active(self) end
function M.anim_state(self)
    if require("mvtk.player.zipline_ride").active(self) then return self._host.features.zipline.animation end
end
function M.reset(self, reason) require("mvtk.player.zipline_ride").reset(self,reason) end
return M
