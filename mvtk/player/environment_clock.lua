local DecisionClock = require "mvtk.enemies.decision_clock"
local Pause = require "mvtk.core.pause"
local Timers = require "mvtk.player.timers"

local M = {}
local h = Timers.REFERENCE_STEP
local engine_step = Timers.engine_reference_step()
local epsilon = 1e-10
local proxy = {proxy_frame_scale = Pause.proxy_frame_scale}

local function unchanged(dt) return dt end

-- The decision clock recovers the real length of proxy-scaled callbacks.
-- Zone clocks spend scaled time on those decisions. The player's clock
-- also advances on callbacks with zero movement time.
function M.frame(dt)
    local elapsed, _, scaled_step, reference = DecisionClock.frame(dt, proxy, unchanged)
    if reference and math.abs(dt - h) <= epsilon then scaled_step = engine_step end
    return elapsed, scaled_step, reference
end

-- Keep the phase through a long frame and retire each crossed decision in
-- order. The callback returns no remainder and cannot reset the phase.
function M.advance(state, elapsed, visit)
    local first = state.step_left or h
    while first <= elapsed + epsilon do
        visit(math.min(first, elapsed))
        first = first + h
    end
    state.step_left = first - elapsed
end

local water_interval = 0.1
M.water_speed_scale = h / water_interval
-- A brief break in surface contact is part of the same swim and splash.
M.water_exit_grace = Timers.reference_duration(0.12)

function M.water_tick(state, step_dt)
    state.timer = math.max(0, (state.timer or 0) - step_dt)
    if state.timer > 0 then return false end
    state.timer = water_interval
    return true
end

-- Keep the first eligible draw available for newly reported overlaps.
function M.advance_water_phase(state, dt)
    local elapsed, step_dt = M.frame(dt)
    local draw_left = state.draw_left and state.draw_left - elapsed
    state.reported_late = nil
    M.advance(state, elapsed, function(offset)
        if M.water_tick(state, step_dt) then
            draw_left = offset + h - elapsed
            if draw_left <= epsilon then state.reported_late = true end
        end
    end)
    state.draw_left = draw_left and draw_left > epsilon and draw_left or nil
end

function M.wind_blowing(state)
    if not state.enabled or state.clock < 0 then return false end
    if state.on_seconds > 0 and state.off_seconds > 0 then
        return state.clock % (state.on_seconds + state.off_seconds) < state.on_seconds
    end
    return true
end

return M
