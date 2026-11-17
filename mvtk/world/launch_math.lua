-- Shared angle policy for authored launchers; degrees anticlockwise from right.
local M = {}

function M.vector(angle_deg, speed)
    local angle = math.rad(angle_deg)
    return math.cos(angle) * speed, math.sin(angle) * speed
end

function M.is_vertical(angle_deg)
    return math.abs(math.cos(math.rad(angle_deg))) < 0.000001
end

-- Sweep symmetrically around base, starting at its low end. Speed is degrees/s.
function M.sweep_angle(base, range, speed, t)
    range = math.abs(range)
    if range == 0 then return base end
    local offset = (speed * t) % (range * 2)
    if offset > range then offset = range * 2 - offset end
    return base - range * 0.5 + offset
end

return M
