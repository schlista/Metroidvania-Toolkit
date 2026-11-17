-- Fixed-decimal number text that prints the same in the game and the editor.
--
-- The Defold editor runs LuaJ 3.0.1, whose string.format ignores the precision
-- of %e/%f/%g and prints Java's full double text ("%.3f" of 0.1+0.2 gives
-- 0.30000000000000004). %d behaves the same in both, so round with integers.
local M = {}

-- Text for value rounded half away from zero to `places` decimals (default 0).
function M.format(value, places)
    value, places = tonumber(value) or 0, math.max(0, math.floor(tonumber(places) or 0))
    if value ~= value then return "nan" end
    if value == math.huge or value == -math.huge then return value > 0 and "inf" or "-inf" end
    local scale = 10 ^ places
    local scaled = math.floor(math.abs(value) * scale + 0.5)
    local sign = (value < 0 and scaled > 0) and "-" or ""
    local whole = string.format("%d", math.floor(scaled / scale))
    if places == 0 then return sign .. whole end
    return sign .. whole .. "." .. string.format("%0" .. places .. "d", scaled % scale)
end

return M
