-- Pure room-lock bookkeeping. Callers own the room table and door blockers.
local M = {}

function M.family(source)
    if source == nil or source == "" or source == "boss_manager" or source == "boss_arena" then
        return "boss"
    end
    return source
end

-- True only for the first family: the caller then needs door blockers.
function M.add(rooms, room_id, source)
    local families = rooms[room_id]
    local spawn_needed = families == nil
    if not families then families = {}; rooms[room_id] = families end
    families[M.family(source)] = true
    return spawn_needed
end

-- True only when the last family releases the room. An omitted source keeps
-- the legacy any-unlock contract; an empty source releases only the boss family.
function M.remove(rooms, room_id, source)
    local families = rooms[room_id]
    if not families then return false end
    if source == nil then
        rooms[room_id] = nil
        return true
    end
    families[M.family(source)] = nil
    if next(families) then return false end
    rooms[room_id] = nil
    return true
end

-- Clear in place so every caller retains the same state table.
function M.clear(rooms)
    for room_id in pairs(rooms) do rooms[room_id] = nil end
end

return M
