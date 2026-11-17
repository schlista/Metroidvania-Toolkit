local M = { id = "bomb", order = 38 }

function M.actions(self, input, stunned)
    if stunned then return end
    return require("mvtk.player.bomb").request(self, input)
end

function M.reset(self, reason)
    require("mvtk.player.bomb").reset(self, reason)
end

return M
