-- Shared in the single runtime Lua state; the player host publishes passage.
local M = {}
local active = false

function M.set(value) active = value == true end
function M.is_active() return active end

return M
