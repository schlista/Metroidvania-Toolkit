-- The engine message table has a 2 KB limit. Transport only a token through
-- the message queue and deliver the original Lua values in the same order.
local Proxy = require "mvtk.prefabs.tiled_proxy_util"

local M = {}
local pending = {}
local next_token = 0

function M.post(owner, name, payload)
    next_token = next_token + 1
    local token = next_token
    pending[token] = payload
    if Proxy.post_to_main(name, {boss_payload = token}) then
        owner.boss_payloads = owner.boss_payloads or {}
        owner.boss_payloads[#owner.boss_payloads + 1] = token
    else
        pending[token] = nil
    end
end

function M.receive(message)
    local token = message and message.boss_payload
    if not token then return message end
    local payload = pending[token]
    pending[token] = nil
    return payload
end

function M.cancel(owner)
    for _, token in ipairs(owner.boss_payloads or {}) do
        pending[token] = nil
    end
end

return M
