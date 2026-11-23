-- A project can keep its existing boss_defaults.lua when it updates.
local M = {
    behind_player_distance = 56,
    leap = {target = "player", height = 112, time = 0.75, max_distance = 360},
    dive = {rise = 96, rise_time = 0.25, track_time = 0.45, track_speed = 480, speed = 640, recover_time = 0.4},
    reposition = {anchor = "centre", style = "walk", timeout = 1.5},
    land = {radius = 150, damage = 3, knockback = 150, ground_only = false},
    anchor_x = {left = 0, right = 1, centre = 0.5, top_left = 0, top_right = 1, top_centre = 0.5},
    relative = {far_from_player = true, near_player = true, behind_player = true},
    top = {top_left = true, top_right = true, top_centre = true},
}

function M.is_anchor(name)
    return M.anchor_x[name] ~= nil or M.relative[name] == true
end

function M.options(pattern, defaults)
    local kind = pattern.type
    local configured = defaults["default_" .. kind] or {}
    local authored = pattern[kind] or {}
    local settings = {}
    for k, v in pairs(M[kind]) do settings[k] = v end
    for k, v in pairs(configured) do settings[k] = v end
    for k, v in pairs(authored) do settings[k] = v end
    if kind == "reposition" then return settings end

    local land = {}
    for k, v in pairs(M.land) do land[k] = v end
    land.radius = defaults.default_aoe_radius or land.radius
    land.damage = defaults.default_aoe_damage or land.damage
    land.knockback = defaults.default_aoe_knockback or land.knockback
    land.vertical_clearance = defaults.default_slam_dodge_height
    for k, v in pairs(configured.land or {}) do land[k] = v end
    if pattern.damage ~= nil then land.damage = pattern.damage end
    for k, v in pairs(authored.land or {}) do land[k] = v end
    settings.land = land
    return settings
end

return M
