-- Game-time deadlines and the reference cadence used by boss decisions.
local Timers = require "mvtk.player.timers"
local DecisionClock = require "mvtk.enemies.decision_clock"
local M = {step = Timers.REFERENCE_STEP}

-- Accumulating binary32 display intervals can put a draw representing a
-- reference boundary a few nanoseconds on either side of it.
local EPSILON = 1e-6

function M.reached(now, deadline)
    return now + EPSILON >= deadline
end

function M.window_lead(dt)
    return math.min(dt, M.step) / 2
end

function M.reference_deadline(time)
    return math.ceil((time - EPSILON) / M.step) * M.step
end

function M.delta(dt, pause)
    if pause.get() then return 0 end
    local scale = pause.dt_scale and pause.dt_scale() or 1
    return math.max(0, dt * scale)
end

function M.steps(owner, now)
    local count = DecisionClock.ticks(nil, now, EPSILON)
    local previous = owner._boss_step or 0
    owner._boss_step = count
    return previous + 1, count
end

function M.time(record)
    return record and (record._boss_clock_at or record.fight_time) or 0
end

return M
