-- Scale transitions advanced only by the owning boss's gameplay update.
-- No engine animation completion can teleport/change a boss during menu pause.
local Pause = require "mvtk.core.pause"
local Fallbacks = {
    teleport_min_scale = 0.02,
}
local Defaults = require("mvtk.core.util").require_config("developer.config.boss_defaults", Fallbacks)
local M = {}
local active = {}
local base_scales = {}
-- Centered box half-extents at unit scale in boss_runtime.go.
local PREFAB_HALF_WIDTH, PREFAB_HALF_HEIGHT = 64, 64
-- Defold rejects zero in any component, before a tween can complete.
local POSITIVE_SCALE_FLOOR = 0.000001

function M.config_scale(size, defaults)
    if not size then return 1, 1 end
    local source = tonumber(defaults.default_sprite_size) or PREFAB_HALF_WIDTH
    return (tonumber(size.width) or source) / source, (tonumber(size.height) or source) / source
end

function M.collision_body(scale_x, scale_y)
    -- Legacy Box2D applies the smaller XY scale to both polygon axes.
    local scale = math.min(scale_x, scale_y)
    return {half_width = PREFAB_HALF_WIDTH * scale, half_height = PREFAB_HALF_HEIGHT * scale}
end

local function key(url)
    local u = msg.url(url)
    return tostring(u.socket) .. ":" .. tostring(u.path)
end

function M.capture_base_scale(url, boss)
    local scale = go.get_scale(url)
    base_scales[key(url)] = scale
    if boss then
        boss._body = M.collision_body(scale.x, scale.y)
    end
    return scale
end

function M.get_base_scale(url)
    return base_scales[key(url)] or go.get_scale(url)
end

function M.disappear_scale(base_scale)
    local authored = tonumber(Defaults.teleport_min_scale) or Fallbacks.teleport_min_scale
    local fraction = math.min(1, math.max(POSITIVE_SCALE_FLOOR, authored))
    return base_scale * fraction
end

function M.scale(url, target, duration, easing, pingpong, complete)
    active[key(url)] = {
        url = url, from = go.get_scale(url), target = target,
        duration = math.max(0, duration), elapsed = 0,
        easing = easing, pingpong = pingpong, complete = complete,
    }
end

function M.clear(url)
    local id = key(url)
    active[id], base_scales[id] = nil, nil
end

function M.set_scale_at(url, from, target, progress, easing)
    if easing == "in_cubic" then progress = progress ^ 3
    elseif easing == "out_cubic" then progress = 1 - (1 - progress) ^ 3
    elseif easing == "out_quad" then progress = 1 - (1 - progress) ^ 2 end
    local scale = progress >= 1 and target or from + (target - from) * progress
    go.set_scale(vmath.vector3(math.max(POSITIVE_SCALE_FLOOR, scale.x),
        math.max(POSITIVE_SCALE_FLOOR, scale.y), math.max(POSITIVE_SCALE_FLOOR, scale.z)), url)
end

function M.update(url, dt)
    if Pause.get() or dt <= 0 then return end
    local id = key(url)
    local motion = active[id]
    if not motion then return end
    local Clock = require "mvtk.bosses.boss_clock"
    while motion do
        local remaining = math.max(0, motion.duration - motion.elapsed)
        local spent = math.min(dt, remaining)
        motion.elapsed = motion.elapsed + spent
        local finished = Clock.reached(motion.elapsed, motion.duration)
        local t = finished and 1 or motion.elapsed / motion.duration
        local progress = motion.pingpong and (t < 0.5 and t * 2 or (1 - t) * 2) or t
        M.set_scale_at(url, motion.from, motion.target, progress, motion.easing)
        if not finished then return end
        active[id] = nil
        if motion.complete then motion.complete() end
        dt = dt - spent
        if dt <= 0 then return end
        motion = active[id]
    end
end

return M
