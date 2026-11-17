-- Sample a moving box without starting rays on a wall-touching collider face.
-- physics.raycast ignores bodies containing the origin (official physics API).
local M = {}

local function samples(extent, spacing)
    local count = math.max(2, math.ceil(2 * extent / spacing))
    local result = {}
    for i = 0, count do result[#result + 1] = -extent + 2 * extent * i / count end
    return result
end

-- raycast is injectable; production uses the synchronous world-space API.
-- All origins stay on centre lines INSIDE the original player box, including
-- destination probes. Never start at the destination, which might be in a wall.
function M.sweep(self, from, to, groups, spacing, raycast)
    raycast = raycast or physics.raycast
    spacing = math.max(0.001, spacing)
    local hx = math.max(0.001, self.collider_half_width - 0.25)
    local hy = math.max(0.001, self.collider_half_height - 0.25)
    local xs, ys = samples(hx, spacing), samples(hy, spacing)
    local dx, dy = to.x - from.x, to.y - from.y
    local function blocked(ox, oy, tx, ty)
        if ox == tx and oy == ty then return false end
        return raycast(vmath.vector3(ox, oy, from.z or 0),
            vmath.vector3(tx, ty, to.z or 0), groups) ~= nil
    end
    -- Intermediate leading faces close the corner wedges of a diagonal sweep;
    -- every face and motion sample is at most half a tile apart.
    local steps = math.max(1, math.ceil(math.max(math.abs(dx), math.abs(dy)) / spacing))
    for step = 1, steps do
        local x, y = from.x + dx * step / steps, from.y + dy * step / steps
        if dx ~= 0 then
            for _, offset in ipairs(ys) do
                if blocked(from.x, from.y + offset, x + (dx < 0 and -hx or hx), y + offset) then return false end
            end
        end
        if dy ~= 0 then
            for _, offset in ipairs(xs) do
                if blocked(from.x + offset, from.y, x + offset, y + (dy < 0 and -hy or hy)) then return false end
            end
        end
    end
    -- Probe both axes of the destination interior from known-safe origins.
    for _, offset in ipairs(ys) do
        for _, sign in ipairs({-1, 1}) do
            if blocked(from.x, from.y + offset, to.x + sign * hx, to.y + offset) then return false end
        end
    end
    for _, offset in ipairs(xs) do
        for _, sign in ipairs({-1, 1}) do
            if blocked(from.x + offset, from.y, to.x + offset, to.y + sign * hy) then return false end
        end
    end
    return true
end

return M
