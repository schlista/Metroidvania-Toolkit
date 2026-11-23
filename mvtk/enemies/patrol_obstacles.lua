-- Terrain ray groups also contain some baked bodies that do not stop patrols.
-- Weak values follow the lifetime of the scripts on those existing objects.
local M = {}
local moving, sweep_only = {}, {}

function M.track(id, group, owner, only_sweep)
    if id == nil then return end
    local registry = only_sweep and sweep_only or moving
    local bodies = registry[group]
    if not bodies then
        bodies = setmetatable({}, {__mode = "v"})
        registry[group] = bodies
    end
    bodies[id] = owner
end

function M.excludes(id, group, face_probe)
    local moving_bodies, sweep_bodies = moving[group], sweep_only[group]
    return (moving_bodies and moving_bodies[id] ~= nil)
        or (face_probe and sweep_bodies and sweep_bodies[id] ~= nil)
end

return M
