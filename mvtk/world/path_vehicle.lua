-- Pure arc-length vehicle simulation. Positions use the caller's coordinates;
-- all clocks advance only through step, so pause freezes every mode.
local K = require "mvtk.world.kinematic_path"
local M = {}
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
    s.mode, s.empty_time, s.timer = "idle", 0, 0
    s.x, s.y = K.at_distance(s.tracks[1], 0)
    events.reappear = true
end

local function travel(s, delta, switch_on, events)
    local next_distance = s.distance + delta
    if s.track == 1 and s.junction and switch_on and delta > 0
        and s.distance <= s.junction and next_distance >= s.junction then
        s.track, next_distance = 2, next_distance - s.junction
        events.junction = true
    elseif s.track == 2 and next_distance < 0 then
        s.track, next_distance = 1, s.junction + next_distance
        events.junction = true
    end
    local path = s.tracks[s.track]
    s.distance = math.max(0, math.min(path.total, next_distance))
    s.x, s.y = K.at_distance(path, s.distance)
    return next_distance >= path.total and delta > 0, next_distance <= 0 and s.track == 1 and delta < 0
end

-- Tracks describe the basin floor. Never sample the previous floating height:
-- a draining or unregistered volume must let the raft settle back onto its track.
local function float(s, input)
    if not s.config.vehicle_float then return end
    local x, y = K.at_distance(s.tracks[s.track], s.distance)
    s.x, s.y = x, y
    local water = input.find_water and input.find_water(x, y)
    if water then
        -- The platform origin is bottom-left; the authored offset describes its top.
        local bottom = water.surface_y + (s.config.vehicle_float_offset or 16) - (s.config.height or 0)
        s.y = math.max(y, bottom)
        if bottom >= y then return water end
    end
end

function M.step(s, dt, input)
    input = input or {}
    local events = {}
    if input.paused or dt <= 0 then return s.x, s.y, events end
    local c = s.config
    local max_speed = math.max(0, c.vehicle_max_speed or 400)
    local delay = math.max(0, c.vehicle_return_delay or 2)
    if s.mode == "hidden" then
        s.timer = s.timer + dt
        if s.timer >= delay then home(s, events); float(s, input) end
        return s.x, s.y, events
    elseif s.mode == "falling" then
        local elapsed = math.min(dt, 1-s.timer)
        local gravity = c.gravity or 0
        s.y = s.y + s.fall_speed*elapsed + gravity*elapsed*elapsed/2
        s.fall_speed, s.timer = s.fall_speed + gravity*elapsed, s.timer + elapsed
        if s.timer >= 1 then s.mode, s.timer, s.speed = "hidden", 0, 0; events.hide = true end
        return s.x, s.y, events
    end
    if input.has_rider then s.empty_time = 0 else s.empty_time = s.empty_time + dt end
    -- A rider who boards a returning vehicle takes it back, keeping its momentum.
    if s.mode == "returning" and input.has_rider then s.mode = "riding" end
    if c.vehicle_end == "return" and not input.has_rider and s.empty_time >= delay
        and (s.track ~= 1 or s.distance > 0) then s.mode = "returning" end
    if s.mode == "returning" then
        local _, at_home = travel(s, -max_speed*dt, false, events)
        s.speed = -max_speed
        if at_home then home(s, events) end
        float(s, input)
        return s.x, s.y, events
    end
    local water = float(s, input)
    local _, _, tx, ty = K.at_distance(s.tracks[s.track], s.distance)
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
    elseif s.speed*target < 0 then rate = math.max(0, c.vehicle_brake or 1200)
    else rate = math.max(0, c.vehicle_acceleration or 600) end
    -- Opposing input brakes to rest before accelerating in the other direction.
    if s.speed*target < 0 then target = 0 end
    if s.speed < target then s.speed = math.min(target, s.speed + rate*dt)
    elseif s.speed > target then s.speed = math.max(target, s.speed - rate*dt) end
    s.mode = input.has_rider and "riding" or "idle"
    local at_end, at_home = travel(s, s.speed*dt, input.switch_on, events)
    if at_end or at_home then
        s.speed = 0
        events.endpoint = true
        if at_end and c.vehicle_end == "fall_away" then
            s.mode, s.timer, s.fall_speed = "falling", 0, 0
        end
    end
    float(s, input)
    return s.x, s.y, events
end

return M
