-- Floor geometry shared by the warning, hit and selection paths.
local Locomotion = require "mvtk.bosses.boss_locomotion"
local Motion = require "mvtk.bosses.boss_motion"
local Defaults = require("mvtk.core.util").require_config("developer.config.boss_defaults", {})

local M = {}

function M.feet_y(boss, pos)
    local measured = Locomotion.feet_y(boss, pos)
    if measured then return measured end
    local config = boss.config or {}
    local offset = tonumber(config.feet_offset)
    if not offset or offset <= 0 then offset = tonumber(Defaults.feet_offset) end
    if not offset or offset <= 0 then
        local sx, sy = Motion.config_scale(config.size, Defaults)
        offset = (boss._body or Motion.collision_body(sx, sy)).half_height
    end
    return pos.y - offset
end

function M.slam_floor(boss, pos, target, decision)
    if Locomotion.enabled(boss) then return Locomotion.attack_floor(boss, target or pos, decision) end
    -- A boss without terrain motion keeps the feet line of its placed body.
    return M.feet_y(boss, pos), true
end

function M.reaches(body, floor_y, height)
    if not body or not floor_y then return false end
    local rise = body.y - body.half_h - floor_y
    return rise >= -(tonumber(Defaults.floor_attack_contact_slop) or 0) and rise <= height
end

return M
