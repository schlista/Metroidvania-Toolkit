-- Shared passenger-carry helper for moving platform style prefabs.

local C = require "mvtk.core.constants"

local M = {}
local Carrier = {}
Carrier.__index = Carrier

local MSG_PLATFORM_DELTA = hash("platform_delta")
local carriers = setmetatable({}, {__mode = "v"})
local moving = setmetatable({}, {__mode = "v"})

local function registered(bodies, id)
    if id == nil then return false end
    if bodies[id] then return true end
    -- Generated platforms can put the collider on a child and the motion
    -- script on its parent. A ray hit contains the collider owner's id.
    if not go or not go.get_parent then return false end
    local ok, parent = pcall(go.get_parent, id)
    return ok and parent ~= nil and bodies[parent] ~= nil
end

function M.is_carrier(id)
    return registered(carriers, id)
end

function M.is_moving_body(id)
    return registered(moving, id)
end

function M.new()
    local carrier = setmetatable({passengers = {}}, Carrier)
    -- A solid carrier is still a platform while waiting for its first move.
    local id = go and go.get_id and go.get_id()
    if id then carriers[id] = carrier end
    return carrier
end

function Carrier:add(url, group)
    if not url then
        return
    end
    self.passengers[url] = { group = group }
end

function Carrier:remove(url)
    if not url then
        return
    end
    self.passengers[url] = nil
end

function Carrier:clear()
    for url in pairs(self.passengers) do
        self.passengers[url] = nil
    end
end

function Carrier:any()
    for _ in pairs(self.passengers) do
        return true
    end
    return false
end

function Carrier:apply_delta(dx, dy, opts)
    dx = tonumber(dx) or 0
    dy = tonumber(dy) or 0
    opts = opts or {}
    if (dx ~= 0 or dy ~= 0) and go and go.get_id then
        local id = go.get_id()
        if id then moving[id] = self end
    end

    for url, info in pairs(self.passengers) do
        if go.exists(url) then
            local group = info and info.group
            if group == C.GROUPS.PLAYER or group == C.GROUPS.ENEMY then
                local should_carry = true
                if group == C.GROUPS.PLAYER and opts.carry_player == false then
                    should_carry = false
                elseif group == C.GROUPS.ENEMY and opts.carry_enemies == false then
                    should_carry = false
                end
                if should_carry then
                    msg.post(url, MSG_PLATFORM_DELTA, { dx = dx, dy = dy })
                end
            else
                local pos = go.get_position(url)
                pos.x = pos.x + dx
                pos.y = pos.y + dy
                go.set_position(pos, url)
            end
        else
            self.passengers[url] = nil
        end
    end
end

return M
