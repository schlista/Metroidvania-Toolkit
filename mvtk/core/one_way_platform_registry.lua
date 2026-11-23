-- The platform collision group contains both directions. Only the inverted
-- instances participate in an upward player sweep.
local inverted = {}
local M = {}

function M.register(id, left, right, underside)
    inverted[id] = {left = left, right = right, underside = underside}
end
function M.unregister(id) inverted[id] = nil end
function M.is_inverted(id) return inverted[id] ~= nil end
function M.candidates() return pairs(inverted) end

return M
