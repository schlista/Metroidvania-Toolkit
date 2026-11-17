-- Pure carried-light record; radius stays in unscaled world pixels like torches.
local M = {}

function M.entry(settings, darkness, player_pos, t)
    settings = settings or {}
    if not player_pos or (tonumber(darkness) or 0) < (tonumber(settings.min_darkness) or 0.2) then
        return nil
    end
    local intensity = tonumber(settings.intensity) or 0.9
    local flicker = tonumber(settings.flicker) or 0.08
    local hz = tonumber(settings.flicker_hz) or 6
    intensity = intensity * (1 - flicker * 0.5 * (1 + math.sin(2 * math.pi * hz * (t or 0))))
    return { x = player_pos.x, y = player_pos.y, radius = tonumber(settings.radius) or 280,
        intensity = math.max(0, math.min(4, intensity)) }
end

return M
