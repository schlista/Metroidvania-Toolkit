-- Shared fallbacks for attack execution, telegraphs and legacy scheduler reach.
-- Creators can keep their old boss_defaults file or override individual fields.
local M = {
    zone = {
        shape = "circle", radius = 96, width = 160, height = 80, target = "boss",
        delay = 0.25, duration = 3, tick = 1, damage = 2, status_duration = 0, knockback = 0,
    },
    ground_wave = {
        speed = 320, distance = 320, height = 64, width = 40, both_sides = false,
        damage = 2, knockback = 150,
    },
    sweep = {
        from_angle = 0, to_angle = 45, duration = 1, windup = 0.25, length = 400,
        width = 40, damage = 2, knockback = 100,
    },
    rain = {
        count = 8, gap_width = 128, gap_at = "player", stagger = 0,
        speed = 280, lifetime = 4, damage = 2,
    },
    ring = {
        count = 8, volleys = 1, volley_delay = 0.25, rotate_per_volley = 0,
        speed = 240, lifetime = 3, damage = 2,
    },
}

function M.options(pattern, defaults)
    local kind = pattern.type
    local result = {}
    for key, value in pairs(M[kind]) do result[key] = value end
    local configured = defaults and defaults["default_" .. kind]
    for key, value in pairs(configured or {}) do result[key] = value end
    for key, value in pairs(pattern[kind] or {}) do result[key] = value end
    return result
end

return M
