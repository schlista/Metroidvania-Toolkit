-- Engine-free fluid heights and painted-row thresholds. Heights never reach zero.
local M = {}
function M.height(value) return math.max(1, tonumber(value) or 1) end
function M.target(baked_height, offset, tile_height, on)
    return M.height(baked_height + (on and offset * tile_height or 0))
end
function M.step(height, target, speed, dt)
    target = M.height(target)
    if speed <= 0 then return target end
    local delta = math.max(0, dt) * speed
    if height < target then return math.min(target, height + delta) end
    return math.max(target, height - delta)
end
function M.row_visible(surface, middle) return surface >= middle end
-- Elapsed time is measured from the start signal, including its delay.
function M.rise(baked_height, speed, limit, tile_height, delay, elapsed)
    return M.height(baked_height + math.min(math.max(0, limit * tile_height),
        math.max(0, elapsed - delay) * math.max(0, speed)))
end
function M.new_rise() return {elapsed=0, running=false, entered=false} end
function M.reset_rise(state)
    state.elapsed, state.running = 0, false
end
function M.start_rise(state)
    state.running = true
end
-- Room entry is consumed once per instance, including a reset on that frame.
-- Returns/deaths stop a chase until another signal or a room reload.
function M.step_rise(state, dt, room_enter, reset)
    if room_enter and not state.entered then
        state.entered = true
        if not reset then M.start_rise(state) end
    end
    if reset then M.reset_rise(state)
    elseif state.running then state.elapsed = state.elapsed + math.max(0, dt) end
    return state.elapsed
end
return M
