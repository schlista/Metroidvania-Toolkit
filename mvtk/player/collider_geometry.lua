-- Shared resource geometry, in current player units. No engine/editor APIs.
local M = {}

M.BASE = {
    sprite = { width = 307.0, height = 149.5, offset_y = 43.75 },
    main = { half_width = 15.0, half_height = 30.0, half_depth = 5.0, offset_y = -10.0 },
    small = { half_width = 23.415384, half_height = 29.339373, half_depth = 10.0, offset_y = -21.0 },
    side = { half_width = 30.0, half_height = 60.0, half_depth = 10.0, offset_y = -3.0 },
    bone_body = { half_width = 24.0, half_height = 40.0, half_depth = 10.0 },
    bone_foot = { half_width = 12.0, half_height = 8.0, half_depth = 10.0 },
    bone_head = { radius = 14.0 },
}

-- New units preserve old effective sizes at 1.00; collision sizes also
-- match the crisp four-times template art (D5 body factor 1.10599).
for kind, base in pairs(M.BASE) do
    for field, value in pairs(base) do
        local body = kind ~= "sprite" and field ~= "offset_y"
        base[field] = value * 1.75 * (body and 1.10599 or 1)
    end
end

return M
