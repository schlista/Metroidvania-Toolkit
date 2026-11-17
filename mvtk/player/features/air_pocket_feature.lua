local M = { id = "air_pocket", order = 60, messages = { mvtk_air_pocket = "any" } }

function M.on_message(self, message_id, message)
    if message_id ~= hash("mvtk_air_pocket") then return false end
    local rate
    if message.inside then rate = tonumber(message.rate) or -1 end
    require("mvtk.player.swim_state").set_air_pocket(message.key, rate)
    return true
end

function M.reset(self, reason)
    require("mvtk.player.swim_state").clear_air_pockets()
end

function M.init(self)
    M.reset(self, "init")
end

return M
