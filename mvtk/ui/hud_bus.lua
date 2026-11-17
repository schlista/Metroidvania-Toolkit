-- Safe from GUI, gameobject and event-listener contexts, including boot-only.
local Util = require "mvtk.core.util"
local M = {}
function M.post(block, data)
    -- Resolve the socket only inside safe_post's protected msg.post call.
    return Util.safe_post("main:/feature_hud#feature_hud", "hud_block", { block = block, data = data })
end
return M
