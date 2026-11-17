-- Checks a saved checkpoint against the current world layout.
-- main.script, the player spawner and the session save loader share this one
-- rule, so the room the streamer requests and the room the player spawns in
-- always come from the same decision.
local M = {}

-- Room ids appear as "developer/rooms/x.collection", "/x" or "x".
function M.normalize(value)
    local s = tostring(value or "")
    s = s:gsub("^developer/rooms/", "")
    s = s:gsub("%.collection$", "")
    s = s:gsub("^/+", "")
    return s
end

-- True when the world point lies inside the room's bounds. The layout stores
-- the bounds corner as (x + ox, y + oy).
function M.room_contains(room, x, y)
    local rx = tonumber(room and room.x)
    local ry = tonumber(room and room.y)
    local rw = tonumber(room and room.w)
    local rh = tonumber(room and room.h)
    if not (rx and ry and rw and rh) then
        return false
    end
    local min_x = rx + (tonumber(room.ox) or 0)
    local min_y = ry + (tonumber(room.oy) or 0)
    return x >= min_x and x <= (min_x + rw) and y >= min_y and y <= (min_y + rh)
end

-- A checkpoint is valid when its room still exists and contains its position,
-- or, for an old checkpoint without a room id, when any room contains it.
-- Without usable layout bounds the checkpoint is kept (legacy behaviour).
function M.is_valid(checkpoint, layout)
    if type(checkpoint) ~= "table" then return false end
    local x = tonumber(checkpoint.x)
    local y = tonumber(checkpoint.y)
    if not (x and y) then return false end
    if not (layout and type(layout.rooms) == "table" and #layout.rooms > 0) then
        return true
    end

    local cp_room = M.normalize(checkpoint.room_id)
    local in_any_room = false
    for _, room in ipairs(layout.rooms) do
        local rid = M.normalize(room.id or room.path)
        local inside = M.room_contains(room, x, y)
        if inside then
            in_any_room = true
            if cp_room == "" or cp_room == rid then
                return true
            end
        end
        if cp_room ~= "" and rid == cp_room then
            -- The claimed room exists, so the checkpoint must be inside it.
            return inside
        end
    end
    return in_any_room and cp_room == ""
end

-- The layout entry for a room id, or nil when the layout has no such room.
function M.layout_room(layout, room_id)
    if room_id == nil or not (layout and type(layout.rooms) == "table") then return nil end
    local wanted = M.normalize(room_id)
    if wanted == "" then return nil end
    for _, room in ipairs(layout.rooms) do
        if M.normalize(room.id or room.path) == wanted then return room end
    end
    return nil
end

return M
