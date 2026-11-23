-- Each front travels along the launch ground line and can hit once.
local C = require "mvtk.bosses.boss_attacks.common"
local Telegraph = require "mvtk.bosses.boss_telegraph"
local Indicator = require "mvtk.bosses.indicator_geometry"
local Locomotion = require "mvtk.bosses.boss_locomotion"
local Floor = require "mvtk.bosses.boss_floor_attacks"

local M = {}

local function travel(boss, pattern, instance, settings, origin, direction, floor_y)
    local front = instance:child({rehit_interval = 0})
    local y, height = Indicator.floor_band(floor_y, settings.height)
    local z = origin.z + 0.1
    local previous_x = origin.x
    local effect = C.stationary_effect(front, "#aoe_effect_factory",
        vmath.vector3(previous_x, y, z), {width = settings.width, box_height = height})
    local half_width = settings.width * 0.5
    local damage = (pattern.damage or settings.damage) * C.damage_mult(boss)
    local knockback = pattern.ground_wave and pattern.ground_wave.knockback
        or pattern.knockback or settings.knockback
    local duration = settings.distance / settings.speed

    C.active_frames(front, duration, function(active, time)
        local x = origin.x + direction * math.min(settings.distance, settings.speed * time)
        if effect and go.exists(effect) then go.set_position(vmath.vector3(x, y, z), effect) end
        -- Sweep the travelled segment so a fast or short wave cannot skip a
        -- body between frames.
        local function overlaps(body)
            local reach = half_width + body.half_w
            if body.x < math.min(previous_x, x) - reach or body.x > math.max(previous_x, x) + reach then
                return false
            end
            return Floor.reaches(body, floor_y, settings.height)
        end
        if C.hit_body(active, overlaps, "swept_band", previous_x, x, half_width, y, height, origin.z) then
            local payload = C.build_payload(boss, pattern, damage, direction * knockback, 0)
            payload.status_id = settings.status
            payload.status_duration = settings.status_duration
            payload.source_attack = pattern._attack_name or "ground_wave"
            C.post_damage(payload)
        end
        previous_x = x
        if time >= duration then C.delete_owned(effect) end
    end, true)
    front._defer = instance._defer
end

local function launch(boss, pattern, instance, settings, facing)
    local origin = go.get_position()
    local floor_y, probed = Locomotion.attack_floor(boss, origin)
    if not probed then return false end
    if not floor_y then
        local name = pattern._attack_name or "ground_wave"
        -- A diagnostic is remembered until this boss instance is removed.
        boss._wave_floor_warnings = boss._wave_floor_warnings or {}
        if not boss._wave_floor_warnings[name] then
            boss._wave_floor_warnings[name] = true
            print(string.format("[BOSS] WARNING: ground wave '%s' has no floor within settle depth", name))
        end
        return true
    end
    travel(boss, pattern, instance, settings, origin, facing, floor_y)
    if settings.both_sides then travel(boss, pattern, instance, settings, origin, -facing, floor_y) end
    return true
end

function M.execute(boss, pattern, instance)
    local settings = C.stationary_options(pattern)
    if not settings then return end
    instance = C.stationary_instance(boss, pattern, instance)
    local cue = Telegraph.take_stationary(boss, pattern, settings)
    Telegraph.cancel(cue)
    if not launch(boss, pattern, instance, settings, cue.facing) then
        instance:each_frame(function(active)
            if launch(boss, pattern, active, settings, cue.facing) then return false end
        end)
    end
end

return M
