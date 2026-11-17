-- Pure world-to-GUI mapping. Picture bounds are already design coordinates:
-- Viewport.design_bounds applies the frame's gui_scale exactly once.
local M = {}
function M.project(pos, view, picture)
    if not view or not picture or view.max_x <= view.min_x or view.max_y <= view.min_y then
        return nil, nil, false
    end
    local u = (pos.x - view.min_x) / (view.max_x - view.min_x)
    local v = (pos.y - view.min_y) / (view.max_y - view.min_y)
    return picture.min_x + u * (picture.max_x - picture.min_x),
        picture.min_y + v * (picture.max_y - picture.min_y),
        u >= 0 and u <= 1 and v >= 0 and v <= 1
end
return M
