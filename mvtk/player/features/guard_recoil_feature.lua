-- Guard impacts set initial knockback speed; player physics owns its decay.
local M = {id = "guard_recoil", order = 44, messages = {mvtk_guard_recoil = "any"}}

function M.on_message(self, message_id, message, sender)
    require("mvtk.player.player_state").apply_knockback(self, message.vx, 0)
    return true
end

return M
