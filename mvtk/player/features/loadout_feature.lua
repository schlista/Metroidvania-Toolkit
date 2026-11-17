local Loadout = require "mvtk.player.loadout"
local Pause = require "mvtk.core.pause"
local M = {id="loadout", order=46}
function M.actions(self, input, stunned)
    if stunned or Pause.get() or not input or not input.loadout_down then return end
    input.loadout_down = false
    return Loadout.cycle()
end
return M
