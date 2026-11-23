-- Pure arc-length vehicle simulation. Positions use the caller's coordinates;
-- all clocks advance only through step, so pause freezes every mode.
local K = require "mvtk.world.kinematic_path"
local Timers = require "mvtk.player.timers"
local M = {}
local STEP = Timers.REFERENCE_STEP
local EPSILON = 1e-12
local CURRENT_DIRECTIONS = {left={-1,0}, right={1,0}, up={0,1}, down={0,-1}}

-- A junction may lie anywhere on a segment, within the authored 2 px tolerance.
function M.junction(path, point, tolerance)
    local best, distance, along = math.huge, nil, 0
    for i, length in ipairs(path.lengths) do
        local a, b = path.points[i], path.points[i + 1]
        if length > 0 then
            local dx, dy = b.x - a.x, b.y - a.y
            local t = math.max(0, math.min(1, ((point.x-a.x)*dx + (point.y-a.y)*dy)/(length*length)))
            local ex, ey = point.x-a.x-dx*t, point.y-a.y-dy*t
            local d = math.sqrt(ex*ex+ey*ey)
            if d < best then best, distance = d, along + t*length end
        end
        along = along + length
    end
    if best <= (tolerance or 2) then return distance end
end

function M.new(points, alternate, config)
    config = config or {}
    local s = {tracks={K.polyline(points)}, track=1, distance=0, speed=0,
        mode="idle", empty_time=0, timer=0, config=config}
    if alternate and #alternate > 1 then
        s.tracks[2] = K.polyline(alternate)
        s.junction = M.junction(s.tracks[1], alternate[1])
    end
    s.x, s.y = K.at_distance(s.tracks[1], 0)
    return s
end

local function home(s, events)
    s.track, s.distance, s.speed = 1, 0, 0
    s.decision_distance, s.decision_speed = 0, 0
    s.mode, s.empty_time, s.timer = "idle", 0, 0
    s.x, s.y = K.at_distance(s.tracks[1], 0)
    events.reappear = true
end

local function travel(s, delta, switch_on, events, engine_delta)
    local next_distance = s.distance + delta
    local opening = engine_delta and s.decision_distance or s.distance
    local advance = engine_delta or delta
    local decision = opening + advance
    if s.track == 1 and s.junction and switch_on and advance > 0
        and opening <= s.junction and decision >= s.junction then
        s.track, next_distance = 2, next_distance - s.junction
        decision = decision - s.junction
        events.junction = true
    elseif s.track == 2 and decision < 0 then
        s.track, next_distance = 1, s.junction + next_distance
        decision = s.junction + decision
        events.junction = true
    end
    local path = s.tracks[s.track]
    local at_end = advance > 0 and decision >= path.total
    local at_home = advance < 0 and s.track == 1 and decision <= 0
    if at_end then next_distance = path.total
    elseif at_home then next_distance = 0 end
    s.distance = math.max(0, math.min(path.total, next_distance))
    s.decision_distance = math.max(0, math.min(path.total, decision))
    s.x, s.y = K.at_distance(path, s.distance)
    return at_end, at_home
end

local function ramp(speed, target, rate, dt)
    if speed < target then return math.min(target, speed + rate * dt) end
    if speed > target then return math.max(target, speed - rate * dt) end
    return speed
end

-- Tracks describe the basin floor. Never sample the previous floating height:
-- a draining or unregistered volume must let the raft settle back onto its track.
local function float(s, input)
    if not s.config.vehicle_float then return end
    local x, y = K.at_distance(s.tracks[s.track], s.distance)
    s.x, s.y = x, y
    if not input.find_water then return end
    local water, surface = input.find_water(x, y)
    if water then
        -- The platform origin is bottom-left; the authored offset describes its top.
        local bottom = (surface or water.surface_y) + (s.config.vehicle_float_offset or 16) - (s.config.height or 0)
        s.y = math.max(y, bottom)
        if bottom >= y then return water end
    end
end

local function reference_step(s, dt, timer_dt, input)
    local events = {}
    local c = s.config
    local max_speed = math.max(0, c.vehicle_max_speed or 400)
    local delay = math.max(0, c.vehicle_return_delay or 2)
    if s.mode == "hidden" then
        s.timer = s.timer + timer_dt
        if s.timer >= delay then home(s, events); float(s, input) end
        return s.x, s.y, events
    elseif s.mode == "falling" then
        local timer_slice = math.min(timer_dt, 1-s.timer)
        local elapsed = dt * (timer_slice / timer_dt)
        local gravity = c.gravity or 0
        s.y = s.y + s.fall_speed*elapsed + gravity*elapsed*elapsed/2
        s.fall_speed, s.timer = s.fall_speed + gravity*elapsed, s.timer + timer_slice
        if s.timer >= 1 then
            s.mode, s.timer, s.speed, s.decision_speed = "hidden", 0, 0, 0
            events.hide = true
        end
        return s.x, s.y, events
    end
    if input.has_rider then s.empty_time = 0 else s.empty_time = s.empty_time + timer_dt end
    -- A rider who boards a returning vehicle takes it back, keeping its momentum.
    if s.mode == "returning" and input.has_rider then s.mode = "riding" end
    if c.vehicle_end == "return" and not input.has_rider and s.empty_time >= delay
        and (s.track ~= 1 or s.distance > 0) then s.mode = "returning" end
    if s.mode == "returning" then
        local _, at_home = travel(s, -max_speed*dt, false, events, -max_speed*timer_dt)
        s.speed, s.decision_speed = -max_speed, -max_speed
        if at_home then home(s, events) end
        float(s, input)
        return s.x, s.y, events, -max_speed, 0, false
    end
    local water = float(s, input)
    local _, _, tx, ty = K.at_distance(s.tracks[s.track], s.decision_distance)
    local stick = math.max(-1, math.min(1, (input.stick_x or 0)*tx + (input.stick_y or 0)*ty))
    local target = input.has_rider and (c.vehicle_control == "auto" and max_speed or stick*max_speed) or 0
    -- The current sets the target only when nobody drives: an empty raft or a
    -- neutral throttle rider. An auto raft keeps running while it has a rider.
    -- Speed eases toward the drift through the usual acceleration and braking.
    if water and (not input.has_rider or (c.vehicle_control ~= "auto" and stick == 0)) then
        local direction = CURRENT_DIRECTIONS[water.current_direction]
        local projection = direction and (direction[1]*tx + direction[2]*ty) or 0
        if projection ~= 0 and (water.current_strength or 0) > 0 then
            target = math.min(max_speed, water.current_strength) * (projection > 0 and 1 or -1)
        end
    end
    local rate
    if c.vehicle_control == "throttle" and target == 0 then rate = math.max(0, c.vehicle_drag or 0)
    elseif s.decision_speed*target < 0 then rate = math.max(0, c.vehicle_brake or 1200)
    else rate = math.max(0, c.vehicle_acceleration or 600) end
    -- Opposing input brakes to rest before accelerating in the other direction.
    if s.decision_speed*target < 0 then target = 0 end
    local previous_speed = s.speed
    s.decision_speed = ramp(s.decision_speed, target, rate, timer_dt)
    s.speed = s.decision_speed == target and target or ramp(s.speed, target, rate, dt)
    s.mode = input.has_rider and "riding" or "idle"
    local end_speed = s.speed
    local at_end, at_home = travel(s, end_speed*dt, input.switch_on, events, s.decision_speed*timer_dt)
    if at_end or at_home then
        s.speed, s.decision_speed = 0, 0
        events.endpoint = true
        if at_end and c.vehicle_end == "fall_away" then
            s.mode, s.timer, s.fall_speed = "falling", 0, 0
        end
    end
    float(s, input)
    return s.x, s.y, events, end_speed, (end_speed - previous_speed) / dt, input.switch_on
end

-- Evaluate the incomplete reference interval without committing its decisions
-- or endpoint events. The ramp sums the saved end-speed samples, and the
-- final interval uses the actual clamped change in speed.
local function between_steps(s, elapsed, step, timer_step, input)
    if s.mode == "hidden" then return s.x, s.y end
    if s.mode == "falling" then
        local fall = math.min(elapsed, step * (1 - s.timer) / timer_step)
        return s.x, s.y + s.fall_speed * fall + (s.config.gravity or 0) * fall * fall / 2
    end
    local preview = setmetatable({}, {__index = s})
    local _, _, _, speed, acceleration, switch_on = reference_step(preview, step, timer_step, input)
    -- A sampled stop travels zero during its last step. Keep the interpolated
    -- speed from crossing zero on an interval whose endpoint clamps to it.
    local limit = math.abs(speed) / (step / 2)
    acceleration = math.max(-limit, math.min(limit, acceleration))
    local delta = speed * elapsed - acceleration * elapsed * (step - elapsed) / 2
    preview.track, preview.distance = s.track, s.distance
    travel(preview, delta, switch_on, {})
    float(preview, input)
    return preview.x, preview.y
end

function M.step(s, dt, input)
    input = input or {}
    local events = {}
    if input.paused or dt <= 0 then return s.x, s.y, events end
    if s.distance ~= s.sampled_distance or s.track ~= s.sampled_track then s.decision_distance = s.distance end
    if s.speed ~= s.sampled_speed then s.decision_speed = s.speed end
    local scale = Timers.binary32(input.reference_scale or 1)
    if scale <= 0 then scale = 1 end
    local step = STEP * scale
    local timer_step = Timers.binary32(Timers.engine_reference_step() * scale)
    local elapsed = (s.reference_elapsed or 0) + Timers.world_delta(dt, scale) / scale
    s.x, s.y = s.reference_x or s.x, s.reference_y or s.y
    while elapsed >= STEP - EPSILON do
        local _, _, dispatched = reference_step(s, step, timer_step, input)
        for name in pairs(dispatched) do events[name] = true end
        if dispatched.hide or dispatched.reappear then
            events.visibility = events.visibility or {}
            events.visibility[#events.visibility + 1] = not dispatched.hide
        end
        if dispatched.hide and input.has_rider then
            input = setmetatable({has_rider=false}, {__index=input})
        end
        elapsed = math.max(0, elapsed - STEP)
    end
    s.reference_elapsed = elapsed
    s.sampled_distance, s.sampled_track, s.sampled_speed = s.distance, s.track, s.speed
    s.reference_x, s.reference_y = s.x, s.y
    if elapsed > EPSILON then
        s.x, s.y = between_steps(s, elapsed * scale, step, timer_step, input)
    end
    return s.x, s.y, events
end

return M
