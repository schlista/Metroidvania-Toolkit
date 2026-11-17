-- Live world-space water rectangles. Keys are baked gameobject ids, so streamed
-- volumes sharing a switch channel remain independent. No engine dependency.
local M = {}
local volumes = {}
function M.register(id, volume) volumes[id] = volume end
function M.update(id, volume) volumes[id] = volume end
function M.unregister(id) volumes[id] = nil end
function M.find(x, y, margin)
    margin = margin or 0
    local highest
    for _, volume in pairs(volumes) do
        if x >= volume.left - margin and x <= volume.right + margin
            and y >= volume.bottom - margin
            and (not highest or volume.surface_y > highest.surface_y) then
            highest = volume
        end
    end
    return highest
end
return M
