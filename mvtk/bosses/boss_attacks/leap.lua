-- Commit to the warned landing at launch.
local Move = require "mvtk.bosses.boss_attacks.moving"
local AOE = require "mvtk.bosses.boss_attacks.aoe"
local Floor = require "mvtk.bosses.boss_floor_attacks"
local Telegraph = require "mvtk.bosses.boss_telegraph"
local Locomotion = require "mvtk.bosses.boss_locomotion"
local M = {}

local function finish(boss, pattern, active, move, target, settings)
    if boss.face_player then boss:face_player() end
    local center = target
    if settings.land.ground_only then
        center = vmath.vector3(target.x, Floor.feet_y(boss, target), target.z)
    end
    AOE.land(boss, pattern, active, center, settings.land)
    move.release()
    return false
end

local function leap_on_terrain(boss, pattern, active, settings, cue)
    local start, target = cue.origin, cue.center
    local move = Move.own(boss, active, cue)
    local dx, dy = target.x - start.x, target.y - start.y
    local elapsed, fall_speed, pending = 0, nil, 0
    local vertex = settings.height > 0 and math.min(1, 0.5 + dy / (8 * settings.height)) or 1
    local function height(t)
        return start.y + dy * t + 4 * settings.height * t * (1 - t)
    end

    local function fall(pos, dt, t)
        local gravity = Locomotion.gravity()
        local x = start.x + dx * t
        local y = pos.y - (fall_speed + gravity * dt * 0.5) * dt
        local floor = Locomotion.sweep_floor(boss, pos, x, y)
        if floor then
            local drop = math.max(0, pos.y - floor)
            local speed_at_floor = math.sqrt(fall_speed * fall_speed + 2 * gravity * drop)
            local spent = drop > 0 and 2 * drop / (fall_speed + speed_at_floor) or 0
            local arrival = elapsed - dt + spent
            local hit_x = start.x + dx * Move.progress(arrival, settings.time)
            -- Check that the same support continues under the exact
            -- touchdown. Keep the checked endpoint at a floor edge.
            if hit_x == x or Locomotion.sweep_floor(boss, pos, hit_x, y) == floor then x = hit_x end
            local landing = vmath.vector3(x, floor, start.z)
            Locomotion.land_at(boss, landing)
            Telegraph.move_landing(cue, landing.x, landing.y)
            return active:motion_arrival(arrival,
                function() finish(boss, pattern, active, move, landing, settings) end)
        end
        fall_speed = fall_speed + gravity * dt
        local cx, cy = Move.clamp(cue, x, y)
        Move.position(boss, cx, cy, start.z)
        if t == 1 and y <= target.y then
            -- The ceiling made the warned landing unreachable. Return
            -- control to gravity without snapping to its height.
            move.release()
            return false
        end
    end

    Move.face_travel(boss, dx)
    active:each_motion(function(_, dt)
        if move.finished then return false end
        pending = pending + dt
        if pending <= 0 then return end
        local pos = go.get_position(boss.self_url)
        local before = Move.progress(elapsed, settings.time)
        local rays = fall_speed and 2 or before < vertex and 1 or 0
        if not Locomotion.can_probe(boss, rays) then
            return
        end
        dt, pending = pending, 0
        elapsed = elapsed + dt
        local t = Move.progress(elapsed, settings.time)
        local x = start.x + dx * t
        if fall_speed then return fall(pos, dt, t) end
        if before < vertex then
            local ceiling_y, ceiling = Locomotion.clip_ceiling(boss, pos, x, height(math.min(t, vertex)))
            if ceiling then
                local rise = dy + 4 * settings.height
                local delta = ceiling_y - start.y
                local root = math.sqrt(math.max(0, rise * rise - 16 * settings.height * delta))
                local hit = math.max(before, math.min(t, 2 * delta / (rise + root)))
                local hit_x = start.x + dx * hit
                local tail = elapsed - hit * settings.time
                fall_speed = 0
                if tail > 0 and Locomotion.can_probe(boss, 2) then
                    return fall(vmath.vector3(hit_x, ceiling_y, start.z), tail, t)
                end
                elapsed, pending = hit * settings.time, math.max(0, tail)
                Move.position(boss, hit_x, ceiling_y, start.z)
                return
            end
        end
        if t == 1 then
            Locomotion.land_at(boss, target)
            return active:motion_arrival(settings.time,
                function() finish(boss, pattern, active, move, target, settings) end)
        end
        local y
        x, y = Move.clamp(cue, x, height(t))
        Move.position(boss, x, y, start.z)
    end)
end

local function launch(boss, pattern, active, settings, cue)
    if Locomotion.active(boss) then return leap_on_terrain(boss, pattern, active, settings, cue) end
    local start, target = cue.origin, cue.center
    local move = Move.own(boss, active, cue, function() Move.restore_height(boss, start.y) end)
    local dx = target.x - start.x
    local elapsed = 0
    Move.face_travel(boss, dx)

    active:each_motion(function(_, dt)
        if move.finished then return false end
        elapsed = elapsed + dt
        local t = Move.progress(elapsed, settings.time)
        local x = start.x + dx * t
        local y = start.y + 4 * settings.height * t * (1 - t)
        if t < 1 then
            Move.face_travel(boss, dx)
            x, y = Move.clamp(cue, x, y)
            Move.position(boss, x, y, start.z)
            return
        end
        Move.position(boss, target.x, start.y, start.z)
        return active:motion_arrival(settings.time,
            function() finish(boss, pattern, active, move, target, settings) end)
    end)
end

function M.execute(boss, pattern, instance)
    Move.prepare(boss, pattern, instance, launch)
end

return M
