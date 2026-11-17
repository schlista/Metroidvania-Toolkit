-- Baked controller and point registrations, shared by streamed room instances.
local M = {}
local controllers, spawns = {}, {}

function M.register_controller(room, id, record)
    controllers[room] = controllers[room] or {}
    controllers[room][id] = record
end
function M.unregister_controller(room, id)
    if controllers[room] then
        controllers[room][id] = nil
        if not next(controllers[room]) then controllers[room] = nil end
    end
end
function M.controller(room, id)
    return controllers[room] and controllers[room][id]
end
function M.register_spawn(room, id, record)
    spawns[room] = spawns[room] or {}
    spawns[room][id] = record
end
function M.unregister_spawn(room, id)
    if spawns[room] then
        spawns[room][id] = nil
        if not next(spawns[room]) then spawns[room] = nil end
    end
end
function M.points(room, encounter_id)
    local out = {}
    for _, record in pairs(spawns[room] or {}) do
        if record.encounter_id == encounter_id then out[#out+1] = record end
    end
    table.sort(out, function(a,b) return a.spawn_id < b.spawn_id end)
    return out
end
function M.reset_all(reason)
    -- Reset callbacks can change registrations; iterate a snapshot.
    local snapshot = {}
    for _, room in pairs(controllers) do
        for _, record in pairs(room) do snapshot[#snapshot+1] = record end
    end
    for _, record in ipairs(snapshot) do
        if record.reset then record.reset(reason) end
    end
end
return M
