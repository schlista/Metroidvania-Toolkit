--- Boss beam attack executor.
-- Telegraphs and fires a directional beam with an active damage window.
-- @module boss_attacks.beam

local C = require "mvtk.bosses.boss_attacks.common"
local Schema = require "mvtk.bosses.attack_pattern_schema"
local Indicator = require "mvtk.bosses.indicator_geometry"
local Telegraph = require "mvtk.bosses.boss_telegraph"

local M = {}

local function tracking_warning(boss, pattern, instance, origin, length, width, warning_pattern)
    local settings = pattern.beam
    local player = C.Detection.get_player_position()
    local direction = player and C.Geometry.aim_vector(origin, player) or vmath.vector3(boss.facing or 1, 0, 0)
    local angle = math.atan2(direction.y, direction.x)
    local speed = math.rad(settings.tracking_speed)
    local deadline = instance:time() + settings.track_time
    local warning = Telegraph.track_beam(boss, warning_pattern or pattern, instance, origin, direction, length, width)
    instance:each_motion(function(_, dt, now)
        local tracked = math.max(0, math.min(dt, deadline - (now - dt)))
        local player = tracked > 0 and C.Detection.get_player_position()
        if player and tracked > 0 then
            local target = math.atan2(player.y - origin.y, player.x - origin.x)
            local delta = target - angle
            local shortest = math.atan2(math.sin(delta), math.cos(delta))
            local turn = speed * tracked
            angle = angle + math.max(-turn, math.min(turn, shortest))
            direction = vmath.vector3(math.cos(angle), math.sin(angle), 0)
            Telegraph.move_beam_warning(warning, origin, direction, length, width)
        end
        if now >= deadline then return false, deadline end
    end)
    return warning, function() return direction end
end

function M.execute(boss, pattern, instance, warning_pattern)
    instance = C.instance(boss, pattern, instance)
    C.print("[BOSS_ATTACKS] Firing beam")

    local pos = go.get_position()
    local beam = pattern.beam or {}
    local beam_dir, length, width = Indicator.beam(boss, pattern, C.Defaults, pos, C.Detection, C.Geometry)
    local damage = (pattern.damage or C.Defaults.default_beam_damage) * C.damage_mult(boss)
    local duration = beam.duration or C.Defaults.default_beam_duration
    local windup = beam.windup or C.Defaults.default_beam_windup

    local warning, locked_direction
    if beam.track_time then
        local effective, err = Schema.tracking_beam_windup(pattern, C.Defaults)
        if not effective then C.print("[BOSS_ATTACKS] " .. err); return end
        windup = effective
        instance = C.stationary_instance(boss, pattern, instance)
        warning, locked_direction = tracking_warning(boss, pattern, instance, pos, length, width, warning_pattern)
    else
        warning = Telegraph.lock_beam(boss, warning_pattern or pattern, instance, pos, beam_dir, length, width)
    end

    local function overlaps(body)
        return C.Geometry.rect_in_beam(pos, beam_dir, length, width, body)
    end

    instance:after(windup, function()
        if locked_direction then beam_dir = locked_direction() end
        Telegraph.cancel(warning)
        local effect, spent
        local function spend()
            if effect and not spent then
                spent = true
                C.effect_look(effect, "spent")
            end
        end
        C.active_frames(instance, duration, function()
            local body, count = C.hit_body(instance, overlaps, "beam", pos, beam_dir, length, width)
            if not body then return end
            local kb = beam_dir * 100
            local payload = C.build_payload(boss, pattern, damage, kb.x, kb.y)
            for _ = 1, count do C.post_damage(payload) end
            C.print(string.format("[BOSS_ATTACKS] Beam hit player for %d damage", damage))
        end, false, spend)

        local beam_ok, beam_url = C.factory_exists("#beam_effect_factory")
        if beam_ok then
            local beam_end = pos + beam_dir * length
            local ok, id = pcall(factory.create, beam_url, pos, nil, {
                end_pos = beam_end,
                width = width,
                duration = duration,
                managed = true,
                single_hit = not duration or duration <= 0,
            })
            if ok then
                effect = instance:own(id)
                instance:after(duration, function()
                    spend()
                    C.effect_look(effect, "expire")
                end)
            end
        end
    end)
end

return M
