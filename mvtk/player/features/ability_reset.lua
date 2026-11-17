-- Keep the state module lazy: loading the host registry must not load it.
local M = { id = "ability_reset", order = 5 }

function M.reset(self, reason)
    require("mvtk.player.player_state").reset_ability_state(self, reason)
end

return M
