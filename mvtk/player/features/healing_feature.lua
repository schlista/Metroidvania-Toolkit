local Healing = require "mvtk.player.healing"
local M = { id="healing", order=48 }
M.init=Healing.init
M.pre_physics=Healing.update
M.reset=Healing.reset
M.restore=Healing.restore
function M.actions(self,input,stunned)
    if stunned or not input then return end
    if input.quick_use_tap then Healing.on_tap(self)
    elseif input.quick_use_hold then Healing.on_hold(self) end
end
function M.anim_state(self)
    local s=self._host and self._host.features.healing
    if not s or not s.drink then return end
    local animation=Healing.settings().use.use_animation
    if s and s.drink and animation~="" then return animation end
end
return M
