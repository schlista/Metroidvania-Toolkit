-- Shared handoff between the toast GUI and the player's Interact caller.
-- A GUI-owned token reserves the action; only the GUI consumes the request.
-- No callback crosses script contexts and no input-focus slot is acquired.
local M = {}
local owner, pending

function M.set(token, visible)
    if visible then
        if owner ~= token then owner, pending = token, false end
    elseif owner == token then
        owner, pending = nil, false
    end
end

function M.active()
    return owner ~= nil
end

function M.request()
    if not owner then return false end
    pending = true
    return true
end

function M.take(token)
    if owner ~= token or not pending then return false end
    pending = false
    return true
end

function M.release(token)
    M.set(token, false)
end

return M
