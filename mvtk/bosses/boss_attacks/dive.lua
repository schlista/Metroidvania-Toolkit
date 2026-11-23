-- Rise, track the player's horizontal movement, then commit to a drop.
local Move = require "mvtk.bosses.boss_attacks.moving"
local Telegraph = require "mvtk.bosses.boss_telegraph"
local AOE = require "mvtk.bosses.boss_attacks.aoe"
local Clock = require "mvtk.bosses.boss_clock"
local M = {}

local function launch(boss, pattern, active, settings, cue)
    local start = cue.origin
    local _, ceiling = Move.clamp(cue, start.x, start.y + settings.rise)
    local move = Move.own(boss, active, cue, function() Move.restore_height(boss, start.y) end)
    local rise_time = math.max(settings.rise_time, math.abs(ceiling - start.y) / settings.track_speed)
    local track_ends = rise_time + settings.track_time
    local elapsed, drop_time = 0, nil
    local x, landing_y = start.x, nil
    local landed = false
    local started_at = active:time()
    local aim, aim_at = Telegraph.dive_player(), Clock.reference_deadline(started_at + rise_time)

    active:each_motion(function(_, dt)
        if move.finished then return false end
        local previous = elapsed
        elapsed = elapsed + dt

        if not drop_time then
            local from, to = math.max(previous, rise_time), math.min(elapsed, track_ends)
            local function steer(seconds)
                if not aim or seconds <= 0 then return end
                local target_x = Telegraph.body_target(aim)
                local dx = target_x - x
                local limit = settings.track_speed * seconds
                x = x + math.max(-limit, math.min(limit, dx))
            end
            while Clock.reached(started_at + to, aim_at) do
                local edge = aim_at - started_at
                steer(edge - from)
                aim, from = Telegraph.dive_player(), math.max(from, edge)
                aim_at = aim_at + Clock.step
            end
            steer(to - from)
            local hit_y
            x, landing_y, hit_y = Telegraph.dive_landing(cue, x, aim, settings)
            if hit_y then Telegraph.move_landing(cue, x, hit_y) end
            if not Clock.reached(elapsed, track_ends) then
                local t = Move.progress(elapsed, rise_time)
                Move.position(boss, x, start.y + (ceiling - start.y) * t, start.z)
                return
            end
            if not landing_y then
                move.release(true)
                return false
            end
            drop_time = math.abs(ceiling - landing_y) / settings.speed
        end

        local target = cue.center
        local drop_elapsed = elapsed - track_ends
        local t = Move.progress(drop_elapsed, drop_time)
        if t < 1 then
            Move.position(boss, target.x, ceiling + (landing_y - ceiling) * t, start.z)
            return
        end
        if not landed then
            landed = true
            Move.position(boss, target.x, landing_y, start.z)
            active:motion_arrival(track_ends + drop_time, function()
                AOE.land(boss, pattern, active, target, settings.land)
                Telegraph.cancel(cue)
            end)
        end
        t = Move.progress(drop_elapsed - drop_time, settings.recover_time)
        Move.position(boss, target.x, landing_y + (start.y - landing_y) * t, start.z)
        if t == 1 then
            move.release()
            return active:motion_arrival(track_ends + drop_time + settings.recover_time)
        end
    end)
end

function M.execute(boss, pattern, instance)
    Move.prepare(boss, pattern, instance, launch)
end

return M
