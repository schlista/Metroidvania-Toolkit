-- Pure picture fractions. The camera owns world reads and message delivery.
local M = {}
local function fraction(value, span)
    return math.max(0, math.min(1, value / span))
end

function M.room_rect(room, padding)
    if type(room) ~= "table" then return nil end
    local x, y, w, h = tonumber(room.x), tonumber(room.y), tonumber(room.w), tonumber(room.h)
    if not x or not y or not w or not h or w <= 0 or h <= 0 then return nil end
    local pad = tonumber(padding) or 0
    x, y = x + (tonumber(room.ox) or 0), y + (tonumber(room.oy) or 0)
    return { min_x = x + pad, min_y = y + pad, max_x = x + w - pad, max_y = y + h - pad }
end

function M.mask(view, room)
    local mask = { left = 0, right = 0, bottom = 0, top = 0 }
    if not view or not room then return mask end
    local w, h = view.max_x - view.min_x, view.max_y - view.min_y
    if w <= 0 or h <= 0 then return mask end
    mask.left = fraction(room.min_x - view.min_x, w)
    mask.right = fraction(view.max_x - room.max_x, w)
    mask.bottom = fraction(room.min_y - view.min_y, h)
    mask.top = fraction(view.max_y - room.max_y, h)
    return mask
end

function M.changed(previous, current, epsilon)
    if not previous then return true end
    for _, key in ipairs({ "left", "right", "bottom", "top" }) do
        if math.abs((previous[key] or 0) - (current[key] or 0)) > (epsilon or 0.000001) then return true end
    end
    return false
end

return M
