-- Shared ownership and transforms for attacks that move the boss.
local C = require "mvtk.bosses.boss_attacks.common"
local Confinement = require "mvtk.bosses.boss_confinement"
local Telegraph = require "mvtk.bosses.boss_telegraph"
local Clock = require "mvtk.bosses.boss_clock"
local M = {}

function M.prepare(boss, pattern, instance, launch)
    local settings = C.moving_options(pattern)
    if not settings then return end
    instance = C.instance(boss, pattern, instance)
    C.supersede_motion(boss)
    local cue, ready, x, y = Telegraph.take_moving(boss, pattern, settings)
    local function start()
        if cue.center then launch(boss, pattern, instance, settings, cue)
        else Telegraph.cancel(cue) end
    end
    if ready then return start() end

    -- Reserve this cast while terrain queries are busy. Its scheduled
    -- launch time stays fixed so successful frame work can catch up.
    local at = instance:time()
    local pending = {instance = instance}
    instance.persist, instance.interruptible = false, true
    boss._active_charge = pending
    local function clear()
        if boss._active_charge == pending then boss._active_charge = nil end
        pending.finished = true
        instance:on_cancel(nil)
    end
    function pending.release()
        clear()
        Telegraph.cancel(cue)
    end
    instance:on_cancel(pending.release)
    instance:each_motion(function(active)
        if pending.finished then return false end
        if not Telegraph.retry_moving(cue, settings, x, y) then return end
        clear()
        active:at_time(at, start)
        return false
    end)
end

function M.own(boss, instance, cue, restore)
    instance.persist, instance.interruptible = false, true
    local move = {instance = instance}
    boss._active_charge = move
    function move.release(cancelled)
        if move.finished then return end
        move.finished = true
        if cancelled and restore then restore() end
        if boss._active_charge == move then boss._active_charge = nil end
        Telegraph.cancel(cue)
        instance:on_cancel(nil)
    end
    instance:on_cancel(function() move.release(true) end)
    return move
end

function M.position(boss, x, y, z)
    go.set_position(vmath.vector3(x, y, z), boss.self_url)
end

function M.clamp(cue, x, y)
    return Confinement.clamp_attack(cue, x, y)
end

function M.restore_height(boss, y)
    local pos = go.get_position(boss.self_url)
    M.position(boss, pos.x, y, pos.z)
end

function M.face_travel(boss, dx)
    if dx ~= 0 then boss.facing = dx > 0 and 1 or -1 end
end

function M.progress(elapsed, duration)
    if Clock.reached(elapsed, duration) then return 1 end
    return elapsed / duration
end

return M
