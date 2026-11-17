-- Shared registry of loaded, unrevealed secrets. Bounds are in world pixels.
-- Secrets own their registration lifetime; only the player scans this table.
local M = {}
local secrets = {}

function M.requirement_matches(required, lens_id)
    return required == "" or required == lens_id
end

function M.should_reveal(center, half_w, half_h, player_pos, radius_px)
    if radius_px < 0 then return false end
    local dx = math.max(0, math.abs(player_pos.x - center.x) - half_w)
    local dy = math.max(0, math.abs(player_pos.y - center.y) - half_h)
    return dx * dx + dy * dy <= radius_px * radius_px
end

function M.register(url, center, half_w, half_h, required)
    secrets[tostring(url)] = {
        url = url, center = { x = center.x, y = center.y },
        half_w = half_w, half_h = half_h, required = required,
    }
end

function M.unregister(url)
    secrets[tostring(url)] = nil
end

function M.registered()
    return pairs(secrets)
end

return M
