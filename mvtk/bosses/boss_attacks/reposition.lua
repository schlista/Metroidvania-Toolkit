-- Walk along the launch row or blink to an anchor, then dispatch a follow-up.
local C = require "mvtk.bosses.boss_attacks.common"
local Move = require "mvtk.bosses.boss_attacks.moving"
local Blink = require "mvtk.bosses.boss_blink"
local Locomotion = require "mvtk.bosses.boss_locomotion"
local M = {}

local function arrive(boss, settings, instance, move)
    move.release()
    if boss.face_player then boss:face_player() end
    local name = settings["then"]
    local child = name and boss.get_attack_pattern and boss:get_attack_pattern(name)
    if child then
        if settings.then_overrides then
            child = C.copy_table(child)
            for key, value in pairs(settings.then_overrides) do child[key] = value end
        end
        -- The child belongs to the move for the remainder of the cast.
        C.execute_pattern(boss, child, {instance = instance:child(child), warn = settings.warn_follow_up})
    end
    return false
end

local function complete_move(boss, settings, instance, move, duration)
    return instance:motion_arrival(duration, function() arrive(boss, settings, instance, move) end)
end

local function walk(boss, settings, cue, instance)
    local start, target = cue.origin, cue.center
    local phase = boss.get_current_phase and boss:get_current_phase() or {}
    local config, data = boss.config or {}, boss.boss_data or {}
    local phase_speed = tonumber(phase.chase_speed)
    if phase_speed and phase_speed < 0 then phase_speed = nil end
    local speed = math.max(0, phase_speed or tonumber(config.chase_speed)
        or C.Defaults.chase_speed or 120) * (data.speed_multiplier or boss.speed_multiplier or 1)
    local dx = target.x - start.x
    local distance, direction = math.abs(dx), dx < 0 and -1 or 1
    local travel_time = speed > 0 and math.min(settings.timeout, distance / speed) or settings.timeout
    local on_terrain = Locomotion.active(boss)
    local function stop_walk()
        if on_terrain then Locomotion.stop_owned_walk(boss) end
    end
    local move = Move.own(boss, instance, cue, on_terrain and stop_walk)
    local elapsed = 0
    Move.face_travel(boss, dx)
    instance:each_motion(function(_, dt)
        if move.finished then return false end
        if on_terrain then
            local remaining = target.x - go.get_position(boss.self_url).x
            if remaining ~= 0 then
                Move.face_travel(boss, remaining)
                elapsed = elapsed + Locomotion.walk_owned(boss, (remaining < 0 and -1 or 1) * speed,
                    dt, target.x, settings.timeout - elapsed)
            end
            if math.abs(target.x - go.get_position(boss.self_url).x) < 0.001 or elapsed >= settings.timeout then
                stop_walk()
                local arrival = math.max(travel_time, elapsed - dt)
                return complete_move(boss, settings, instance, move, arrival)
            end
            return
        end
        elapsed = math.min(settings.timeout, elapsed + dt)
        local travelled = math.min(distance, speed * elapsed)
        local x = travelled >= distance and target.x or start.x + direction * travelled
        Move.face_travel(boss, dx)
        Move.position(boss, x, start.y, start.z)
        if travelled >= distance or elapsed >= settings.timeout then
            return complete_move(boss, settings, instance, move, travel_time)
        end
    end)
end

local function blink(boss, settings, cue, instance)
    local advance, cancel, duration = Blink.start(boss, function()
        if Locomotion.active(boss) then
            Locomotion.land_at(boss, cue.center)
        else
            Move.position(boss, cue.center.x, cue.center.y, cue.center.z)
        end
    end)
    local move = Move.own(boss, instance, cue, cancel)
    instance:each_motion(function(_, dt)
        if move.finished then return false end
        if advance(dt) then
            return complete_move(boss, settings, instance, move, duration)
        end
    end)
end

local function launch(boss, _, active, settings, cue)
    if settings.style == "blink" then
        blink(boss, settings, cue, active)
    else
        walk(boss, settings, cue, active)
    end
end

function M.execute(boss, pattern, instance)
    Move.prepare(boss, pattern, instance, launch)
end

return M
