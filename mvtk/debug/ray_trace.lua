-- mvtk/debug/ray_trace.lua
-- Debug builds only: debug_overlay_gate.script installs it with the dev tools,
-- and Export Game removes that overlay. Box2D ignores a ray whose two ends meet
-- after physics scaling and logs "Ray had 0 length when ray casting after
-- applying physics scale", which names no script. This wrapper prints the call
-- stack of the first such ray from each place, so a play log names the script
-- (Stage 9 A46). developer/config/debug_config.lua dev_tools.trace_zero_rays
-- turns it off.
local M = {}

-- Box2D compares 32-bit float ends, so a sub-pixel ray far from the world origin
-- warns as well as an exact zero.
M.EPSILON = 0.01

local installed, seen = false, {}

function M.is_near_zero(from, to)
    return math.abs(from.x - to.x) < M.EPSILON and math.abs(from.y - to.y) < M.EPSILON
end

-- Returns true when the wrapper is in place. Every module reads physics.raycast
-- when it casts, so wrapping the table field covers them.
function M.install()
    if installed then return true end
    if not (physics and physics.raycast) then return false end
    installed = true
    local raycast = physics.raycast
    physics.raycast = function(from, to, ...)
        if from and to and M.is_near_zero(from, to) then
            local stack = debug.traceback("", 2)
            -- The caller's line, below the "stack traceback:" header.
            local site = stack:match("traceback:\n%s*([^\n]+)") or stack
            if not seen[site] then
                seen[site] = true
                print(string.format("[RAY_TRACE] near-zero raycast from (%.3f, %.3f) to (%.3f, %.3f)%s",
                    from.x, from.y, to.x, to.y, stack))
            end
        end
        return raycast(from, to, ...)
    end
    return true
end

return M
