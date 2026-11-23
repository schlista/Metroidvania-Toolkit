local Timers = require "mvtk.player.timers"
local M = {}
local h = Timers.REFERENCE_STEP
local engine_step = Timers.engine_reference_step()
local epsilon = 1e-8
local last_unscaled_dt

-- The proxy stores both its factor and its output delta as binary32.
local function proxy_float(value)
    local mantissa, exponent = math.frexp(value)
    local significand = mantissa * 2^24
    local lower = math.floor(significand)
    local fraction = significand - lower
    if fraction > .5 or (fraction == .5 and lower % 2 == 1) then lower = lower + 1 end
    return math.ldexp(lower, exponent - 24)
end

function M.frame(dt, pause, snap)
    local scale_fn = pause and (pause.dt_scale or pause.scale)
    local script_scale = scale_fn and scale_fn() or 1
    local proxy_scale = pause and pause.proxy_frame_scale and pause.proxy_frame_scale(dt)
    local snapped = snap(dt)
    local scaled_dt = snapped * script_scale
    local raw_dt, step_scale
    if dt <= 0 then
        -- The proxy erases the duration of a stopped frame. Use the most
        -- recent live delta, shared with actors created during the stop.
        raw_dt, step_scale = last_unscaled_dt or h, 0
    elseif proxy_scale and proxy_scale > 0 and proxy_scale ~= 1 then
        step_scale = proxy_float(proxy_scale)
        raw_dt = snap(dt / step_scale)
    else
        raw_dt, step_scale = snapped, script_scale
    end
    local reference = Timers.reference_frame(raw_dt)
        or (proxy_scale and math.abs(raw_dt - engine_step) <= epsilon)
    if dt > 0 then last_unscaled_dt = raw_dt end
    local step_dt
    if reference then
        step_dt = scaled_dt
    elseif proxy_scale then
        local engine_dt = engine_step * step_scale
        if proxy_scale ~= 1 then engine_dt = proxy_float(engine_dt) end
        step_dt = snap(engine_dt)
    else
        step_dt = snap(engine_step) * step_scale
    end
    return reference and h or raw_dt, scaled_dt, step_dt, reference
end

function M.reset(actor)
    actor._decision_left = nil
    actor._decision_patterns = nil
    actor._decision_motion = nil
    actor._pending_decision_vx, actor._pending_decision_vy = nil, nil
    actor._patrol_wall_x, actor._patrol_wall_y = nil, nil
    actor._patrol_boxed_x, actor._patrol_boxed_y = nil, nil
    actor._swim_wall_x, actor._swim_wall_y, actor._swim_escape = nil, nil, nil
    actor._swim_boxed = nil
    actor._ghost_room_block = nil
    if actor._hop then actor._hop.blocked_direction = nil end
    actor._terrain_fix_x, actor._terrain_fix_y = nil, nil
end

function M.left(actor)
    if actor._decision_patterns ~= actor.patterns then
        M.reset(actor)
        actor._decision_patterns = actor.patterns
    end
    return actor._decision_left or 0
end

-- Opening boundaries belong to the frame that starts on them. Consume a
-- boundary at the end only on the next frame, even after a long callback.
function M.piece(left, remaining)
    local due = left == 0
    if due then left = h end
    local span = math.min(left, remaining)
    left, remaining = left - span, remaining - span
    return due, span, left <= epsilon and 0 or left, remaining <= epsilon and 0 or remaining
end

-- Interval timers spend a step when its closing boundary is reached. This
-- keeps a deadline from dispatching early just because a frame is shorter.
function M.ticks(left, remaining, tolerance)
    local elapsed = h - (left or h) + remaining
    local count = math.floor((elapsed + (tolerance or epsilon)) / h)
    return count, h - math.max(0, elapsed - count * h)
end

return M
