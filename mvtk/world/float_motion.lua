local Timers = require "mvtk.player.timers"

local M = {}
local STEP = Timers.REFERENCE_STEP
local EPSILON = 1e-12

local function spring(y, velocity, target, frequency, dt)
    local offset = y - target
    local drift = velocity + frequency * offset
    local decay = math.exp(-frequency * dt)
    return target + (offset + drift * dt) * decay,
        (velocity - frequency * drift * dt) * decay
end

-- The saved float spring samples a surface once per update. At other rates
-- reconstruct those samples from the adjacent observed water levels.
function M.step(state, y, velocity, target, frequency, dt, scale)
    if dt <= 0 then return y, velocity, state end
    if not state or math.abs(y-state.draw_y) > math.max(1,math.abs(y))*2^-23 or velocity ~= state.draw_velocity then
        state = { y = y, velocity = velocity, target = target, elapsed = 0 }
    end
    scale = scale or 1
    local seconds = Timers.world_delta(dt, scale) / scale
    local slope = (target - state.target) / seconds
    local elapsed = state.elapsed + seconds
    local boundary = STEP - state.elapsed
    while elapsed >= STEP - EPSILON do
        local sample = boundary >= seconds - EPSILON and target or state.target + slope * boundary
        local step = Timers.reference_frame(dt / scale) and dt or STEP * scale
        local y0 = state.elapsed == 0 and boundary == STEP and y or state.y
        state.y, state.velocity = spring(y0, state.velocity, sample, frequency, step)
        elapsed = math.max(0, elapsed - STEP)
        boundary = boundary + STEP
    end
    state.target, state.elapsed = target, elapsed
    local draw_y, draw_velocity = state.y, state.velocity
    if elapsed > EPSILON then
        local sample = target + slope * (STEP - elapsed)
        draw_y, draw_velocity = spring(state.y, state.velocity, sample, frequency, elapsed * scale)
    end
    state.draw_y, state.draw_velocity = draw_y, draw_velocity
    return draw_y, draw_velocity, state
end

return M
