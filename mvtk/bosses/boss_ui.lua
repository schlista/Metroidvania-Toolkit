--- Boss UI Registry
-- Decouples boss_manager from the concrete boss health bar URL.
-- The boss HUD gui_script calls register() from init() with its own URL;
-- boss_manager uses send() which dispatches to every registered listener.
-- If no HUD is registered, messages are silently dropped.
--
-- @module boss_ui

local M = {}

local listeners = {}
local next_token = 0

-- Register a HUD listener URL (or string path). Safe to call multiple times.
function M.register(url)
    if not url then return end
    local key = tostring(url)
    if not listeners[key] then listeners[key] = {url = url, pending = {}} end
end

-- Unregister a previously registered URL.
function M.unregister(url)
    if not url then return end
    listeners[tostring(url)] = nil
end

-- Dispatch a message to every registered HUD. Failures are swallowed so a
-- missing/renamed GUI doesn't break boss logic.
function M.send(message_id, message)
    local hashed = type(message_id) == "string" and hash(message_id) or message_id
    for _, listener in pairs(listeners) do
        local ok = pcall(msg.post, listener.url, hashed, message or {})
        if not ok and type(message) == "table" then
            -- Long authored names can exceed the engine message buffer.
            -- Each listener consumes its own copy in queue order.
            next_token = next_token + 1
            local token = next_token
            local payload = {}
            for key, value in pairs(message) do payload[key] = value end
            listener.pending[token] = payload
            if not pcall(msg.post, listener.url, hashed, {boss_ui_payload = token}) then
                listener.pending[token] = nil
            end
        end
    end
end

function M.receive(url, token)
    local listener = listeners[tostring(url)]
    if not listener then return nil end
    local payload = listener.pending[token]
    listener.pending[token] = nil
    return payload
end

-- Number of active listeners (for debug).
function M.count()
    local n = 0
    for _ in pairs(listeners) do n = n + 1 end
    return n
end

return M
