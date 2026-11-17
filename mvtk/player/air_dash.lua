-- Pure air-dash direction policy; legacy fixtures keep their horizontal feel.
local Direction8 = require "mvtk.core.direction8"
local M = {}

function M.direction(input, facing, on_wall, wall_side, cfg)
    cfg = cfg or {}
    local dir = (facing ~= 0 and facing) or 1
    local x = input and input.move_x or 0
    local threshold = cfg.stick_threshold or 0.2
    if cfg.directions ~= "eight" then
        if on_wall then
            if math.abs(x) >= threshold then
                dir = x > 0 and -1 or 1
            elseif (wall_side or 0) ~= 0 then
                dir = -wall_side
            end
        elseif math.abs(x) >= threshold then
            dir = x > 0 and 1 or -1
        end
        return dir, 0
    end
    local vector = Direction8.quantize(x, input and input.move_y or 0, {
        mode = cfg.diagonal_snap == false and "free" or "eight",
        deadzone = threshold, allow_down = cfg.allow_down,
    })
    if vector then
        return on_wall and -vector.x or vector.x, vector.y
    end
    -- Neutral (including a stripped down-only input) starts from facing.
    -- Wall inversion applies to its horizontal component just like stick input.
    return on_wall and -dir or dir, 0
end

return M
