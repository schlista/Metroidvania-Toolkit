-- Pure time-based platform motion. Preserve arithmetic order for existing users.
-- New motion contracts belong in new functions, leaving these results unchanged.
local M = {}
local TWO_PI = math.pi * 2

function M.ease_in_out(t)
    return t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
end

function M.line_offset(t01, dx, dy)
    local eased = M.ease_in_out(t01)
    return (dx or 0) * eased, (dy or 0) * eased
end

function M.circle_offset(t01, radius, start_angle_deg)
    local angle = math.rad(start_angle_deg or 0) + t01 * TWO_PI
    return radius * math.cos(angle), radius * math.sin(angle)
end

function M.segments_by_time(points, t01, closed)
    if not points or #points < 2 then
        return nil
    end

    local waypoint_count = #points
    local loop_path = closed == true
    local total_segments = loop_path and waypoint_count or (waypoint_count - 1)
    local segment_progress = t01 * total_segments
    local segment_index = math.floor(segment_progress)
    local segment_t = segment_progress - segment_index

    if loop_path then
        segment_index = segment_index % waypoint_count
        local wp1 = points[segment_index + 1]
        local wp2 = points[(segment_index + 1) % waypoint_count + 1]
        local x = wp1.x + (wp2.x - wp1.x) * segment_t
        local y = wp1.y + (wp2.y - wp1.y) * segment_t
        return x, y
    end

    if segment_index >= total_segments then
        segment_index = total_segments - 1
        segment_t = 1
    elseif segment_index < 0 then
        segment_index = 0
        segment_t = 0
    end

    local wp1 = points[segment_index + 1]
    local wp2 = points[segment_index + 2] or wp1

    local x = wp1.x + (wp2.x - wp1.x) * segment_t
    local y = wp1.y + (wp2.y - wp1.y) * segment_t
    return x, y
end

-- duration is already clamped by the caller; events leave waits/lifecycle there.
function M.advance(t, dir, dt, duration, mode)
    local dur = duration
    local event
    if mode == "wrap_mod" then
        t = t + dt
        if t >= dur then t = t % dur end
    elseif mode == "pingpong" or mode == "there_and_back" then
        if dir > 0 then
            t = t + dt
            if t >= dur then
                t = dur
                dir = -1
                event = "turn"
            end
        else
            t = t - dt
            if t <= 0 then
                t = 0
                dir = 1
                event = mode == "pingpong" and "turn" or "complete"
            end
        end
    elseif mode == "once_stop" then
        t = t + dt
        if t >= dur then
            t = dur
            event = "complete"
        end
    elseif mode == "wrap_sub" then
        t = t + dt
        if t >= dur then
            local remainder = t - dur
            t = remainder < dur and remainder or t % dur
        end
    elseif mode == "once_hold" then
        if dir > 0 then t = math.min(t + dt, dur) end
    end
    return t, dir, event
end

-- Arc-length paths for new callers. Existing platform contracts above stay intact.
function M.polyline(points, closed)
    local path = {points = {}, lengths = {}, total = 0, closed = closed == true}
    for _, p in ipairs(points or {}) do
        path.points[#path.points + 1] = {x = p.x, y = p.y}
    end
    local count = #path.points
    for i = 1, (closed and count or count - 1) do
        local a, b = path.points[i], path.points[i % count + 1]
        local dx, dy = b.x - a.x, b.y - a.y
        local length = math.sqrt(dx * dx + dy * dy)
        path.lengths[i] = length
        path.total = path.total + length
    end
    return path
end

function M.at_distance(path, s, wrap)
    local points, total = path.points, path.total
    if #points == 0 then return 0, 0, 0, 0 end
    if total <= 0 then return points[1].x, points[1].y, 0, 0 end
    s = wrap and s % total or math.max(0, math.min(total, s))
    for i, length in ipairs(path.lengths) do
        if length > 0 and s <= length then
            local a, b = points[i], points[i % #points + 1]
            local dx, dy = b.x - a.x, b.y - a.y
            return a.x + dx * s / length, a.y + dy * s / length, dx / length, dy / length
        end
        s = s - length
    end
    local p = points[#points]
    return p.x, p.y, 0, 0
end

-- Progress, state and direction. Pingpong waits at both ends, including load;
-- loop waits at its seam, once waits at the start and then holds the far end.
function M.cycle(t, travel_time, wait, mode)
    t, wait = math.max(0, t), math.max(0, wait or 0)
    if travel_time <= 0 then return 0, "wait", 1 end
    if mode == "loop" then
        t = t % (travel_time + wait)
        if t >= travel_time then return 1, "wait", 1 end
        return t / travel_time, "travel", 1
    elseif mode == "once" then
        if t < wait then return 0, "wait", 1 end
        if t >= wait + travel_time then return 1, "complete", 1 end
        return (t - wait) / travel_time, "travel", 1
    end
    t = t % (2 * (travel_time + wait))
    if t < wait then return 0, "wait", 1 end
    t = t - wait
    if t < travel_time then return t / travel_time, "travel", 1 end
    t = t - travel_time
    if t < wait then return 1, "wait", -1 end
    return 1 - (t - wait) / travel_time, "travel", -1
end

function M.orbit(pivot_x, pivot_y, radius, start_angle, degrees_per_second, t)
    local a = math.rad(start_angle + degrees_per_second * t)
    return pivot_x + radius * math.cos(a), pivot_y + radius * math.sin(a)
end

-- Timings use seconds (top, warn, drop, bottom, rise) and a positive distance.
-- The third return is horizontal shake, in pixels, only during the warning.
function M.slam(t, timings)
    local top, warn, drop, bottom, rise = timings.top, timings.warn, timings.drop, timings.bottom, timings.rise
    local period = top + warn + drop + bottom + rise
    if period <= 0 then return 0, "top", 0 end
    t = math.max(0, t) % period
    if t < top then return 0, "top", 0 end
    t = t - top
    if t < warn then return 0, "warn", 2 * math.sin(t * math.pi * 40) end
    t = t - warn
    if t < drop then return timings.distance * t / drop, "drop", 0 end
    t = t - drop
    if t < bottom then return timings.distance, "bottom", 0 end
    t = t - bottom
    if rise > 0 then return timings.distance * (1 - t / rise), "rise", 0 end
    return 0, "top", 0
end

-- All points/distances/pivots are offsets in Y-up room coordinates.
-- Return centre offset and full size, like the pendulum swept-box contract.
function M.sweep_bounds(spec, width, height)
    local kind = spec.motion_type or spec.type
    local min_x, max_x, min_y, max_y = 0, 0, 0, 0
    if kind == "orbit" then
        local x, y = spec.motion_pivot_x, spec.motion_pivot_y
        local r = math.abs(spec.motion_radius or 128)
        if x == nil then x, y = -r, 0 else r = math.sqrt(x * x + y * y) end
        min_x, max_x, min_y, max_y = x - r, x + r, y - r, y + r
    elseif kind == "path" and spec.points and #spec.points > 0 then
        min_x, max_x, min_y, max_y = spec.points[1].x, spec.points[1].x, spec.points[1].y, spec.points[1].y
        for _, p in ipairs(spec.points) do
            min_x, max_x = math.min(min_x, p.x), math.max(max_x, p.x)
            min_y, max_y = math.min(min_y, p.y), math.max(max_y, p.y)
        end
    elseif kind == "line" or kind == "slam" then
        local dx, dy = spec.motion_distance_x or 0, -(spec.motion_distance_y or 0)
        min_x, max_x, min_y, max_y = math.min(0, dx), math.max(0, dx), math.min(0, dy), math.max(0, dy)
        if kind == "slam" then min_x, max_x = math.min(min_x, -2), math.max(max_x, 2) end
    end
    return (min_x + max_x) / 2, (min_y + max_y) / 2,
        max_x - min_x + (width or 0), max_y - min_y + (height or 0)
end

return M
