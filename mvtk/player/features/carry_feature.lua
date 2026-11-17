local M = {id="carry", order=28, messages={mvtk_carry_begin="body"}}
function M.on_message(self, message_id, message)
    if message_id ~= hash("mvtk_carry_begin") then return false end
    require("mvtk.player.carry").begin(self, message)
    return true
end
function M.pre_physics(self, dt, input) require("mvtk.player.carry").pre_physics(self, dt, input) end
function M.post_physics(self) require("mvtk.player.carry").post_physics(self) end
function M.anim_state(self) return require("mvtk.player.carry").anim_state(self) end
function M.reset(self) require("mvtk.player.carry").release(self, "lost") end
return M
