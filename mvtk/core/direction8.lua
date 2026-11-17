-- Pure stick direction shared by movement and aiming. No engine dependencies.
local M = {}

-- Return a unit {x, y} vector, or nil for neutral/filtered input.
-- Restrictions remove components before snapping; four-way ties prefer X.
function M.quantize(x, y, opts)
    opts = opts or {}
    x, y = tonumber(x) or 0, tonumber(y) or 0
    local deadzone = math.max(0, tonumber(opts.deadzone) or 0.2)
    if x*x + y*y <= deadzone*deadzone then return nil end
    if opts.allow_vertical == false then y = 0 end
    if opts.allow_down == false and y < 0 then y = 0 end
    if x == 0 and y == 0 then return nil end
    local mode = opts.mode or "eight"
    if mode == "four" then
        if math.abs(x) >= math.abs(y) then y = 0 else x = 0 end
    elseif mode == "eight" then
        -- tan(22.5 degrees) separates cardinal and diagonal sectors.
        local boundary = math.sqrt(2) - 1
        if math.abs(y) < math.abs(x) * boundary then y = 0
        elseif math.abs(x) < math.abs(y) * boundary then x = 0 end
        if x ~= 0 then x = x < 0 and -1 or 1 end
        if y ~= 0 then y = y < 0 and -1 or 1 end
    end
    local length = math.sqrt(x*x + y*y)
    return { x = x / length, y = y / length }
end

return M
