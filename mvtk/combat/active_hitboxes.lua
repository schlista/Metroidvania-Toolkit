-- Shared player swing geometry. No physics groups or engine calls.
-- Actor-owned rectangles stay live until retirement. Other callers can use
-- a wall-time lease, renewed on each move.
local Time = require "mvtk.core.time"
local M = {}
local entries = {}

local function expire(now)
    for id, rect in pairs(entries) do
        if rect.expires_at and rect.expires_at <= now then entries[id] = nil end
    end
end

function M.register(id, rect)
    expire(Time.gettime())
    entries[id] = {x=rect.x, y=rect.y, hw=rect.hw, hh=rect.hh,
        ttl=rect.ttl, expires_at=rect.ttl and Time.gettime() + rect.ttl}
end

function M.move(id, x, y)
    local rect = entries[id]
    if rect then
        rect.x, rect.y = x, y
        if rect.ttl then rect.expires_at = Time.gettime() + rect.ttl end
        return true
    end
    return false
end

function M.remove(id) entries[id] = nil end

function M.first_overlap(x, y, hw, hh)
    local now = Time.gettime()
    expire(now)
    for id, rect in pairs(entries) do
        if math.abs(x-rect.x) <= hw+rect.hw and math.abs(y-rect.y) <= hh+rect.hh then
            return id, rect
        end
    end
    return nil
end

function M.clear() entries = {} end
return M
